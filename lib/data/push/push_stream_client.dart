/// The Android push connection: the hermes-iris plugin's Server-Sent Events stream (`push/stream`), held open by
/// the foreground service for as long as notifications are on.
///
/// It resumes from the last event it saw (the server replays a short window after it), signs in again from the
/// stored login when the dashboard session expires, and backs off 2, 4, 8 … 60 s while the server cannot be reached.
/// A stream that goes quiet past the server's 25 s pings is treated as dead and reopened.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/logging.dart';
import '../net/server_connection.dart';
import 'push_models.dart';

/// What the "connected" notification and Settings say.
enum PushConnection {
  /// Notifications are off: no service, no stream.
  off,

  /// Opening the first stream.
  connecting,

  /// A stream is open.
  connected,

  /// The last attempt failed; waiting to try again.
  unreachable;

  static PushConnection? fromWire(Object? value) =>
      value is String ? values.asNameMap()[value] : null;
}

// ---------------------------------------------------------------------------------------------------------------
// SSE

sealed class SseFrame {
  const SseFrame();
}

/// A `:` line. The server's keep-alive.
final class SseComment extends SseFrame {
  const SseComment();
}

final class SseEvent extends SseFrame {
  const SseEvent({this.id, this.event = 'message', required this.data});

  final String? id;
  final String event;

  /// Every `data:` line of the frame, joined with newlines.
  final String data;
}

/// Frames from an SSE body, per the WHATWG event-stream rules Iris needs: `id`, `event`, multi-line `data`, comments.
/// `retry` and unknown fields are ignored; an unfinished frame at the end is dropped.
///
/// Built from transformers rather than an `async*` generator so that cancelling it cancels the body at once: a
/// generator waiting on a silent stream would keep the HTTP connection open after the caller gave up on it.
Stream<SseFrame> decodeSse(Stream<List<int>> bytes) {
  String? id;
  String? event;
  final data = <String>[];
  var comment = false;
  return bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(
        StreamTransformer<String, SseFrame>.fromHandlers(
          handleData: (line, sink) {
            if (line.isEmpty) {
              if (data.isNotEmpty) {
                sink.add(
                  SseEvent(
                    id: id,
                    event: event ?? 'message',
                    data: data.join('\n'),
                  ),
                );
              } else if (comment) {
                sink.add(const SseComment());
              }
              event = null;
              data.clear();
              comment = false;
              return;
            }
            if (line.startsWith(':')) {
              comment = true;
              return;
            }
            final colon = line.indexOf(':');
            final name = colon < 0 ? line : line.substring(0, colon);
            var value = colon < 0 ? '' : line.substring(colon + 1);
            if (value.startsWith(' ')) value = value.substring(1);
            switch (name) {
              case 'id':
                id = value;
              case 'event':
                event = value;
              case 'data':
                data.add(value);
            }
          },
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------
// Transport

sealed class StreamOpening {
  const StreamOpening();
}

final class StreamOpened extends StreamOpening {
  const StreamOpened(this.body);

  final Stream<List<int>> body;
}

/// The server answered with something other than a stream, or ([status] null) did not answer at all.
final class StreamRefused extends StreamOpening {
  const StreamRefused(this.status);

  final int? status;

  /// The dashboard session expired: a 401/403, or a redirect to its login page.
  bool get needsSignIn =>
      status == 401 ||
      status == 403 ||
      (status != null && status! >= 300 && status! < 400);

  /// The plugin does not know this device (not registered, or removed).
  bool get unknownDevice => status == 404;
}

abstract interface class PushStreamTransport {
  /// Opens the stream after [after] (no cursor: from now).
  Future<StreamOpening> open({String? after});

  /// Signs in again with the stored login. False when there is none or it was refused.
  Future<bool> signIn();
}

/// The real transport, over one server connection's Dio (its cookie jar and Access headers).
final class DashboardPushStreamTransport implements PushStreamTransport {
  DashboardPushStreamTransport(
    this._connection, {
    required this.deviceId,
    this.profile = 'default',
  });

  final ServerConnection _connection;
  final String deviceId;
  final String profile;

  @override
  Future<StreamOpening> open({String? after}) async {
    try {
      final response = await _connection.client.dio.get<ResponseBody>(
        '/api/plugins/iris/push/stream',
        queryParameters: {
          'device_id': deviceId,
          'after': ?after,
          if (profile != 'default') 'profile': profile,
        },
        options: Options(
          responseType: ResponseType.stream,
          // The stream is meant to stay open; the client's own idle timer judges whether it is alive.
          receiveTimeout: Duration.zero,
          headers: const {'Accept': 'text/event-stream'},
        ),
      );
      final status = response.statusCode;
      final body = response.data;
      if (status == 200 && body != null) return StreamOpened(body.stream);
      unawaited(body?.stream.drain<void>().catchError((Object _) {}));
      return StreamRefused(status);
    } on DioException catch (error) {
      return StreamRefused(error.response?.statusCode);
    } on Object {
      return const StreamRefused(null);
    }
  }

  @override
  Future<bool> signIn() async {
    final secrets = _connection.secrets;
    if (!secrets.hasLogin) return false;
    final result = await _connection.auth.signIn(
      username: secrets.username!,
      password: secrets.password!,
    );
    return result.isOk;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Client

final class PushStreamClient {
  PushStreamClient({
    required PushStreamTransport transport,
    required String? cursor,
    required void Function(String cursor) onCursor,
    required void Function(PushNotice notice) onNotice,
    required void Function(PushConnection state) onState,
    Future<void> Function(Duration)? sleep,
    this.idleTimeout = const Duration(seconds: 70),
  }) : _transport = transport,
       _cursor = cursor,
       _onCursor = onCursor,
       _onNotice = onNotice,
       _onState = onState,
       _sleep = sleep ?? Future<void>.delayed;

  static const _log = IrisLog('push.stream');

  static const _maxBackoff = Duration(seconds: 60);

  /// Wait before attempt [failures] + 1: 2, 4, 8, 16, 32, then 60 s.
  static Duration backoff(int failures) => failures >= 5
      ? _maxBackoff
      : Duration(seconds: min(2 << failures, _maxBackoff.inSeconds));

  final PushStreamTransport _transport;
  final void Function(String) _onCursor;
  final void Function(PushNotice) _onNotice;
  final void Function(PushConnection) _onState;
  final Future<void> Function(Duration) _sleep;

  /// No bytes for this long (the server pings every 25 s) and the stream is dead.
  final Duration idleTimeout;

  String? _cursor;
  PushConnection? _state;
  bool _stopped = false;
  final _stop = Completer<void>();
  StreamSubscription<SseFrame>? _subscription;
  Completer<void>? _streamDone;

  String? get cursor => _cursor;

  /// Keeps a stream open until [stop]. Never throws.
  Future<void> run() async {
    var failures = 0;
    var signedIn = false;
    _set(PushConnection.connecting);
    while (!_stopped) {
      final opening = await _transport.open(after: _cursor);
      if (_stopped) {
        if (opening is StreamOpened) {
          unawaited(opening.body.drain<void>().catchError((Object _) {}));
        }
        break;
      }
      switch (opening) {
        case StreamOpened(:final body):
          failures = 0;
          signedIn = false;
          _set(PushConnection.connected);
          final heard = await _consume(body);
          // A stream that ends having delivered something is a normal drop (a proxy's limit, a restart): reopen
          // at once. One that delivered nothing counts as a failure, so a server that accepts and closes is not
          // hammered.
          if (!heard && !_stopped) {
            _set(PushConnection.unreachable);
            await _wait(backoff(failures++));
          }
        case StreamRefused() when opening.needsSignIn && !signedIn:
          signedIn = true;
          if (await _transport.signIn()) {
            _log.info('signed in again');
            continue;
          }
          _set(PushConnection.unreachable);
          await _wait(backoff(failures++));
        case StreamRefused():
          _log.debug(
            'stream refused',
            data: opening.status?.toString() ?? 'no answer',
          );
          _set(PushConnection.unreachable);
          await _wait(opening.unknownDevice ? _maxBackoff : backoff(failures));
          failures++;
          signedIn = false;
      }
    }
  }

  /// Ends [run]: closes the open stream and cuts a wait short.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    if (!_stop.isCompleted) _stop.complete();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _set(PushConnection state) {
    if (_state == state) return;
    _state = state;
    _onState(state);
  }

  Future<void> _wait(Duration duration) =>
      Future.any([_sleep(duration), _stop.future]);

  /// Reads [body] until it ends, errors or goes quiet. True when it carried at least one frame.
  Future<bool> _consume(Stream<List<int>> body) async {
    var heard = false;
    final done = _streamDone = Completer<void>();
    _subscription = decodeSse(body)
        .timeout(idleTimeout)
        .listen(
          (frame) {
            heard = true;
            if (frame is SseEvent) _handle(frame);
          },
          onError: (Object error) {
            _log.debug('stream ended', data: error.runtimeType.toString());
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    await done.future;
    await _subscription?.cancel();
    _subscription = null;
    return heard;
  }

  void _handle(SseEvent frame) {
    if (frame.event == 'notice') {
      try {
        final notice = PushNotice.fromJson(jsonDecode(frame.data));
        if (notice != null) _onNotice(notice);
      } on FormatException {
        _log.warn('a notice that is not JSON was skipped');
      }
    }
    final id = frame.id;
    if (id != null && id.isNotEmpty) {
      _cursor = id;
      _onCursor(id);
    }
  }
}
