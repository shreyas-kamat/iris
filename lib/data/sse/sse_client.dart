/// A resilient Server-Sent Events connection to a Hermes run.
///
/// A phone loses its connection constantly — a lift, a tunnel, a Wi-Fi to LTE
/// handover — while the agent keeps working on the user's machine regardless.
/// So a dropped stream is a normal condition here, not an error: this client
/// reconnects with backoff, resumes from the last event id it saw, and hands
/// the caller a single uninterrupted [Stream] across all of it.
///
/// What it deliberately does not do is decide what a reconnect means for the
/// transcript. When the server cannot honour a cursor it replies with
/// `session_snapshot`, and reconciling that against optimistically-rendered
/// deltas is the chat layer's job, not the transport's.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../models/stream_event.dart';
import 'sse_frame.dart';
import 'sse_parser.dart';

/// Why a connection attempt is being made, surfaced so the UI can distinguish
/// "connecting" from "reconnecting" without inferring it.
enum SseConnectionState { connecting, open, reconnecting, closed }

/// Opens and maintains one event stream.
final class SseClient {
  SseClient({
    required Dio dio,
    required String path,
    this.query = const {},
    this.maxRetries = 8,
    this.heartbeatTimeout = const Duration(seconds: 90),
  }) : _dio = dio,
       _path = path;

  static const _log = IrisLog('sse');

  final Dio _dio;
  final String _path;
  final Map<String, Object?> query;

  /// How many consecutive reconnects to attempt before giving up. Eight with
  /// the backoff below spans roughly two minutes, long enough to cross a
  /// tunnel or a network handover.
  final int maxRetries;

  /// How long a connection may produce nothing at all — not even a heartbeat
  /// comment — before it is treated as dead. Hermes beats every 30s, so this
  /// tolerates two missed beats before acting.
  final Duration heartbeatTimeout;

  final _events = StreamController<StreamEvent>.broadcast();
  final _states = StreamController<SseConnectionState>.broadcast();

  CancelToken? _cancelToken;
  Timer? _watchdog;
  String? _lastEventId;
  bool _closed = false;
  int _attempt = 0;

  /// The decoded event stream. Broadcast, so the transcript and a background
  /// notification listener can both observe one connection.
  Stream<StreamEvent> get events => _events.stream;

  /// Connection lifecycle, for status affordances.
  Stream<SseConnectionState> get states => _states.stream;

  /// The cursor to resume from, exposed so a caller can persist it and resume a
  /// run across an app restart.
  String? get lastEventId => _lastEventId;

  /// Starts the stream. Returns when the run reaches a terminal event, the
  /// retry budget is exhausted, or [close] is called.
  Future<void> start({String? resumeFrom}) async {
    _lastEventId ??= resumeFrom;
    while (!_closed) {
      final terminated = await _connectOnce();
      if (terminated || _closed) break;

      if (_attempt >= maxRetries) {
        _log.warn('giving up after $_attempt attempts');
        _fail(
          const IrisFailure(
            FailureKind.offline,
            message: 'Lost connection to the agent.',
          ),
        );
        break;
      }
      _attempt++;
      _emitState(SseConnectionState.reconnecting);
      await Future<void>.delayed(_backoffFor(_attempt));
    }
    await _shutdown();
  }

  /// Exponential backoff capped at 30s, with the first retry nearly immediate
  /// so the common case — a one-second blip — is invisible to the user.
  static Duration _backoffFor(int attempt) {
    const base = 400;
    final millis = base * (1 << (attempt - 1).clamp(0, 6));
    return Duration(milliseconds: millis.clamp(base, 30000));
  }

  /// Runs one connection to completion. Returns true if the run finished and
  /// no reconnect should be attempted.
  Future<bool> _connectOnce() async {
    _emitState(
      _attempt == 0
          ? SseConnectionState.connecting
          : SseConnectionState.reconnecting,
    );
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    try {
      final response = await _dio.get<ResponseBody>(
        _path,
        queryParameters: {
          for (final entry in query.entries)
            if (entry.value != null) entry.key: entry.value,
        },
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          // Long-lived by design: the receive timeout is replaced by the
          // heartbeat watchdog, which can tell a silent connection from a slow
          // one. A fixed receive timeout would kill a legitimately long turn.
          receiveTimeout: Duration.zero,
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            if (_lastEventId != null) 'Last-Event-ID': _lastEventId,
          },
          validateStatus: (_) => true,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        _log.warn('stream open failed: HTTP $status');
        if (status == 401 || status == 403) {
          _fail(
            IrisFailure(
              FailureKind.unauthorized,
              statusCode: status,
              endpoint: _path,
            ),
          );
          return true;
        }
        // 404 means the stream id is gone — the run ended while disconnected,
        // and retrying would only fail identically.
        if (status == 404) return true;
        return false;
      }

      _attempt = 0;
      _emitState(SseConnectionState.open);
      return await _consume(response.data!);
    } on Object catch (error, stackTrace) {
      if (cancelToken.isCancelled || _closed) return true;
      _log.debug('stream dropped', data: error);
      if (error is DioException &&
          error.type == DioExceptionType.badCertificate) {
        _fail(
          IrisFailure(
            FailureKind.tls,
            endpoint: _path,
            cause: error,
            stackTrace: stackTrace,
          ),
        );
        return true;
      }
      return false;
    } finally {
      _watchdog?.cancel();
      _watchdog = null;
    }
  }

  /// Reads frames until the body ends or a terminal event arrives.
  Future<bool> _consume(ResponseBody body) async {
    final completer = Completer<bool>();
    _resetWatchdog();

    late final StreamSubscription<SseFrame> subscription;
    subscription = body.stream
        .cast<List<int>>()
        .transform(SseParser(onComment: (_) => _resetWatchdog()))
        .listen(
          (frame) {
            _resetWatchdog();
            if (frame.id != null && frame.id!.isNotEmpty) {
              _lastEventId = frame.id;
            }
            final event = StreamEvent.fromFrame(frame);
            if (!_events.isClosed) _events.add(event);
            if (event.isTerminal && !completer.isCompleted) {
              completer.complete(true);
              unawaited(subscription.cancel());
            }
          },
          onError: (Object error) {
            if (!completer.isCompleted) completer.complete(false);
          },
          onDone: () {
            // The body ended without a terminal event: the connection dropped
            // mid-run, so a reconnect is warranted.
            if (!completer.isCompleted) completer.complete(false);
          },
          cancelOnError: true,
        );

    final terminated = await completer.future;
    await subscription.cancel();
    return terminated;
  }

  /// Restarts the silence timer. A connection producing neither events nor
  /// heartbeats is dead even though the socket looks open — the common
  /// symptom of a proxy or captive portal swallowing the stream.
  void _resetWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(heartbeatTimeout, () {
      _log.warn('no traffic for ${heartbeatTimeout.inSeconds}s; reconnecting');
      _cancelToken?.cancel('heartbeat timeout');
    });
  }

  void _emitState(SseConnectionState state) {
    if (!_states.isClosed) _states.add(state);
  }

  void _fail(IrisFailure failure) {
    if (!_events.isClosed) _events.addError(failure);
  }

  /// Stops the stream and releases the connection. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancelToken?.cancel('closed by client');
    await _shutdown();
  }

  Future<void> _shutdown() async {
    _watchdog?.cancel();
    _watchdog = null;
    _emitState(SseConnectionState.closed);
    if (!_events.isClosed) await _events.close();
    if (!_states.isClosed) await _states.close();
  }
}
