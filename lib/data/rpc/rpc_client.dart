/// JSON-RPC over one open socket.
///
/// Deliberately thin: it correlates requests with responses, forwards events,
/// and declines requests the gateway makes that Iris has no screen for. It
/// does not reconnect — one client lives exactly as long as one socket, and
/// `DashboardSession` replaces it when the socket dies.
library;

import 'dart:async';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'rpc_frame.dart';
import 'wire_socket.dart';

final class RpcClient {
  RpcClient(
    this._socket, {
    this.defaultTimeout = const Duration(seconds: 30),
  }) {
    _subscription = _socket.frames.listen(
      _onFrame,
      onError: (Object _) => _shutdown(),
      onDone: _shutdown,
      cancelOnError: true,
    );
  }

  static const _log = IrisLog('rpc');

  final WireSocket _socket;
  final Duration defaultTimeout;
  late final StreamSubscription<String> _subscription;
  final Map<int, _Pending> _pending = {};
  final _events = StreamController<RpcEvent>.broadcast();
  final _closed = Completer<void>();
  int _nextId = 0;

  /// Stream events, in arrival order. Closes with the socket.
  Stream<RpcEvent> get events => _events.stream;

  /// Completes when the socket has closed, for whatever reason.
  Future<void> get done => _closed.future;

  bool get isOpen => !_closed.isCompleted;

  /// Calls [method]. Never throws.
  Future<Result<Json>> call(
    String method, {
    Map<String, Object?>? params,
    Duration? timeout,
  }) {
    if (!isOpen) return Future.value(Err(_closedFailure(method)));
    final id = ++_nextId;
    final completer = Completer<Result<Json>>();
    final timer = Timer(timeout ?? defaultTimeout, () {
      if (_pending.remove(id) != null) {
        completer.complete(
          Err(
            IrisFailure(
              FailureKind.timeout,
              message: 'No answer to $method in time.',
              endpoint: method,
            ),
          ),
        );
      }
    });
    _pending[id] = _Pending(method, completer, timer);
    try {
      _socket.send(RpcEncode.request(id, method, params));
    } on Object catch (error, stackTrace) {
      _pending.remove(id);
      timer.cancel();
      return Future.value(
        Err(
          IrisFailure(
            FailureKind.offline,
            endpoint: method,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
    _log.debug('→ $method #$id');
    return completer.future;
  }

  /// Proves the socket is alive.
  ///
  /// A gateway without `ping` answers "method not found" — and that answer
  /// travelled over this socket just as a pong would.
  Future<Result<void>> ping({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await call('ping', timeout: timeout);
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final failure) when failure.rpcError?.isMethodNotFound ?? false =>
        const Ok(null),
      Err(:final failure) => Err(failure),
    };
  }

  void _onFrame(String text) {
    switch (RpcFrame.parse(text)) {
      case RpcResponse(:final id, :final result, :final error):
        final pending = _pending.remove(id);
        if (pending == null) {
          _log.debug('unmatched response #$id');
          return;
        }
        pending.timer.cancel();
        pending.completer.complete(
          error == null
              ? Ok(result)
              : Err(
                  IrisFailure(
                    FailureKind.rejected,
                    message: IrisLog.redact(error.message),
                    endpoint: pending.method,
                    cause: error,
                  ),
                ),
        );
      case final RpcEvent event:
        _events.add(event);
      case RpcServerRequest(:final id, :final method):
        // Phase 1 has no approval or clarify cards. Declining at once makes the
        // tool fail fast instead of waiting out its deadline.
        _log.info('declined server request $method');
        _trySend(
          RpcEncode.errorReply(
            id,
            RpcCodes.methodNotFound,
            'Iris has no handler for $method',
          ),
        );
      case RpcUnreadable(:final reason):
        _log.warn('dropped frame: $reason');
    }
  }

  void _trySend(String text) {
    try {
      _socket.send(text);
    } on Object {
      // The socket is closing; the gateway withdraws the request itself.
    }
  }

  void _shutdown() {
    if (_closed.isCompleted) return;
    _closed.complete();
    for (final pending in _pending.values) {
      pending.timer.cancel();
      pending.completer.complete(Err(_closedFailure(pending.method)));
    }
    _pending.clear();
    unawaited(_events.close());
  }

  static IrisFailure _closedFailure(String method) => IrisFailure(
    FailureKind.offline,
    message: 'The live connection closed.',
    endpoint: method,
  );

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
    _shutdown();
  }
}

final class _Pending {
  _Pending(this.method, this.completer, this.timer);

  final String method;
  final Completer<Result<Json>> completer;
  final Timer timer;
}
