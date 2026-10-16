/// A scripted WebSocket, so RPC behaviour is tested frame by frame.
library;

import 'dart:async';
import 'dart:convert';

import 'package:iris/core/json.dart';
import 'package:iris/data/rpc/wire_socket.dart';

final class FakeWireSocket implements WireSocket {
  final _incoming = StreamController<String>();
  final List<String> sent = [];
  int? _closeCode;

  @override
  Stream<String> get frames => _incoming.stream;

  @override
  void send(String text) {
    if (_closeCode != null) throw StateError('socket closed');
    sent.add(text);
  }

  @override
  Future<void> close([int code = 1000]) async {
    _closeCode ??= code;
    // Not awaited: once the client has cancelled its subscription, the done
    // future of a single-subscription controller may never complete.
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  int? get closeCode => _closeCode;

  /// Delivers [frame] (a JSON-encodable value or a raw string) to the client.
  void serverSends(Object frame) =>
      _incoming.add(frame is String ? frame : jsonEncode(frame));

  /// Simulates the server or the network dropping the connection.
  Future<void> serverCloses() => close(1006);

  /// Delivers a server→client request, such as an approval or a prompt.
  void pushRequest(String id, String method, Map<String, Object?> params) =>
      serverSends({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});

  /// Delivers a stream event for [session].
  void pushEvent(String type, String session, Map<String, Object?> payload) =>
      serverSends({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': type, 'session_id': session, 'payload': payload},
      });

  Json get lastSent => Json.decode(sent.last);

  /// Answers the most recent request.
  void replyToLast({Object? result, Map<String, Object?>? error}) =>
      serverSends({
        'jsonrpc': '2.0',
        'id': lastSent['id'].raw,
        if (error != null) 'error': error else 'result': result,
      });
}
