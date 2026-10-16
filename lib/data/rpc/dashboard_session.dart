/// The live link to one dashboard.
///
/// A phone loses its connection constantly while the agent keeps working, so a
/// dropped socket is a normal event here, not an error. This object owns the
/// whole cycle: mint a fresh single-use ticket, open the socket, and when it
/// dies, do it again after a short backoff — signing in again first if the
/// session cookie has expired.
///
/// Two failures are never retried automatically: an access proxy turning Iris
/// away, and an untrusted certificate. Retrying either would only repeat the
/// same refusal until the user changes something.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../net/server_connection.dart';
import 'rpc_client.dart';
import 'rpc_frame.dart';
import 'wire_socket.dart';

/// Where the link is.
enum LinkPhase {
  /// Not started, or disposed.
  idle,

  /// Minting a ticket and opening the socket.
  connecting,

  /// The socket is open.
  live,

  /// Waiting to try again after a drop or a transient failure.
  retrying,

  /// The saved login no longer works, or none was saved.
  needsSignIn,

  /// Stopped by something only the user can fix: an access proxy or an
  /// untrusted certificate.
  blocked,
}

@immutable
final class LinkState {
  const LinkState(this.phase, {this.attempt = 0, this.failure, this.retryIn});

  final LinkPhase phase;

  /// How many consecutive attempts have failed.
  final int attempt;
  final IrisFailure? failure;

  /// When [phase] is [LinkPhase.retrying], how long until the next attempt.
  final Duration? retryIn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinkState &&
          other.phase == phase &&
          other.attempt == attempt &&
          other.failure?.kind == failure?.kind);

  @override
  int get hashCode => Object.hash(phase, attempt, failure?.kind);

  @override
  String toString() =>
      'LinkState(${phase.name}, attempt $attempt'
      '${failure == null ? '' : ', ${failure!.kind.name}'})';
}

final class DashboardSession {
  DashboardSession({
    required ServerConnection http,
    WireConnector? connector,
    Duration Function(int attempt)? backoff,
  }) : _http = http,
       _connector = connector ?? _ioConnector(http),
       _backoff = backoff ?? defaultBackoff;

  static const _log = IrisLog('link');

  /// `min(5, 2^attempt)` seconds, as Hermes Conduit does: quick enough to
  /// recover from a blip, slow enough not to hammer a server that is down.
  static Duration defaultBackoff(int attempt) => Duration(
    milliseconds: (math.min(5, math.pow(2, attempt)) * 1000).round(),
  );

  /// The server requests Iris shows to a person; the rest are declined, so
  /// the tool waiting on one fails fast instead of waiting out its deadline.
  static const presentedServerRequests = {
    'approval',
    'clarify',
    'sudo',
    'secret',
    'vault.unlock_prompt',
    'vault.code',
    'vault.save_login',
  };

  static WireConnector _ioConnector(ServerConnection http) =>
      (uri, headers) => IoWireSocket.connect(
        uri,
        headers: headers,
        client: http.socketHttpClient(),
      );

  /// The socket URL for [ticket] on the dashboard at [base].
  static Uri socketUri(Uri base, String ticket) {
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$path/api/ws',
      queryParameters: {'ticket': ticket},
    );
  }

  final ServerConnection _http;
  final WireConnector _connector;
  final Duration Function(int attempt) _backoff;
  final _states = StreamController<LinkState>.broadcast();
  final _events = StreamController<RpcEvent>.broadcast();
  final _serverRequests = StreamController<RpcServerRequest>.broadcast();

  LinkState _state = const LinkState(LinkPhase.idle);
  RpcClient? _client;
  StreamSubscription<RpcEvent>? _eventSubscription;
  StreamSubscription<RpcServerRequest>? _requestSubscription;
  Timer? _retry;
  int _attempt = 0;
  int _generation = 0;
  bool _connecting = false;
  bool _disposed = false;

  LinkState get state => _state;

  Stream<LinkState> get states => _states.stream;

  /// Events from whichever socket is current, across reconnects.
  Stream<RpcEvent> get events => _events.stream;

  /// Approvals and clarifying questions the gateway asks, across reconnects.
  Stream<RpcServerRequest> get serverRequests => _serverRequests.stream;

  /// The HTTP side of this server: cookies, Access headers, REST.
  ServerConnection get connection => _http;

  bool get isLive => _state.phase == LinkPhase.live && (_client?.isOpen ?? false);

  /// Connects. Completes once the first attempt has settled.
  Future<void> start() => _run();

  /// Skips the backoff — for returning to the foreground, or a "try again" tap.
  Future<void> reconnectNow() async {
    if (_disposed || isLive) return;
    _retry?.cancel();
    _attempt = 0;
    await _run();
  }

  /// Calls [method] on the live socket. Never throws.
  Future<Result<Json>> call(
    String method, {
    Map<String, Object?>? params,
    Duration? timeout,
  }) {
    final client = _client;
    if (client == null || !client.isOpen) {
      return Future.value(
        Err(
          IrisFailure(
            FailureKind.offline,
            message: 'Not connected to the dashboard.',
            endpoint: method,
          ),
        ),
      );
    }
    return client.call(method, params: params, timeout: timeout);
  }

  /// Answers server request [id] on the live socket. False when there is no
  /// live socket, in which case the gateway withdraws the request itself.
  bool replyToServerRequest(String id, Map<String, Object?> result) =>
      _client?.reply(id, result) ?? false;

  Future<void> _run() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _retry?.cancel();
    _set(LinkState(LinkPhase.connecting, attempt: _attempt));
    final outcome = await _connectOnce();
    _connecting = false;
    if (_disposed) {
      await outcome.valueOrNull?.close();
      return;
    }
    switch (outcome) {
      case Ok(:final value):
        _adopt(value);
      case Err(:final failure):
        _onFailure(failure);
    }
  }

  Future<Result<RpcClient>> _connectOnce() async {
    final auth = _http.auth;
    var ticket = await auth.mintTicket();
    if (ticket case Err(:final failure)
        when failure.kind == FailureKind.unauthorized) {
      final secrets = _http.secrets;
      if (!secrets.hasLogin) return Err(failure);
      _log.info('session expired; signing in again');
      final signedIn = await auth.signIn(
        username: secrets.username!.trim(),
        password: secrets.password!,
      );
      if (signedIn case Err(failure: final signInFailure)) {
        return Err(signInFailure);
      }
      ticket = await auth.mintTicket();
    }
    switch (ticket) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final uri = socketUri(_http.config.uri, value);
        try {
          final socket = await _connector(uri, _http.accessHeadersFor(uri));
          return Ok(RpcClient(socket, presented: presentedServerRequests));
        } on Object catch (error, stackTrace) {
          return Err(_socketFailure(error, stackTrace));
        }
    }
  }

  static IrisFailure _socketFailure(Object error, StackTrace stackTrace) {
    final kind = switch (error) {
      TimeoutException() => FailureKind.timeout,
      TlsException() => FailureKind.tls,
      SocketException() => FailureKind.offline,
      WebSocketException() => FailureKind.rejected,
      _ => FailureKind.unknown,
    };
    // The exception text includes the URL, and the URL includes the ticket.
    _log.warn('socket open failed: ${kind.name}', data: IrisLog.redact('$error'));
    return IrisFailure(
      kind,
      message: kind == FailureKind.rejected
          ? 'The dashboard refused the live connection.'
          : null,
      endpoint: '/api/ws',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  void _adopt(RpcClient client) {
    final generation = ++_generation;
    _client = client;
    _attempt = 0;
    _eventSubscription = client.events.listen((event) {
      _events.add(event);
      // Hermes sends approvals and clarifying questions as server requests
      // only to a client that says it can answer them. Said once per socket,
      // when the gateway announces it is ready.
      if (event.type == 'gateway.ready') {
        unawaited(
          client.call(
            'client.capabilities',
            params: const {'server_requests': true},
            timeout: const Duration(seconds: 10),
          ),
        );
      }
    });
    _requestSubscription = client.serverRequests.listen(_serverRequests.add);
    unawaited(client.done.then((_) => _onDropped(generation)));
    _set(const LinkState(LinkPhase.live));
    _log.info('live');
  }

  void _onDropped(int generation) {
    if (_disposed || generation != _generation) return;
    _client = null;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_requestSubscription?.cancel());
    _requestSubscription = null;
    _scheduleRetry(
      const IrisFailure(
        FailureKind.offline,
        message: 'The live connection dropped.',
      ),
    );
  }

  void _onFailure(IrisFailure failure) {
    switch (failure.kind) {
      case FailureKind.accessGate || FailureKind.tls:
        _set(LinkState(LinkPhase.blocked, failure: failure));
      case FailureKind.unauthorized:
        _set(LinkState(LinkPhase.needsSignIn, failure: failure));
      default:
        _scheduleRetry(failure);
    }
  }

  void _scheduleRetry(IrisFailure failure) {
    final delay = _backoff(_attempt);
    _attempt++;
    _set(
      LinkState(
        LinkPhase.retrying,
        attempt: _attempt,
        failure: failure,
        retryIn: delay,
      ),
    );
    _retry = Timer(delay, () => unawaited(_run()));
  }

  void _set(LinkState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _retry?.cancel();
    await _eventSubscription?.cancel();
    await _requestSubscription?.cancel();
    await _client?.close();
    _client = null;
    _set(const LinkState(LinkPhase.idle));
    await _states.close();
    await _events.close();
    await _serverRequests.close();
  }
}
