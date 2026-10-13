/// Reading and writing the dashboard's JSON-RPC frames.
///
/// Frame shapes follow Hermes Conduit's client (`HermesClient.swift`), which
/// tracks the gateway in `tui_gateway/server.py`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

void main() {
  group('parse', () {
    test('a response carries its id and result', () {
      final frame = RpcFrame.parse(
        '{"jsonrpc":"2.0","id":7,"result":{"sessions":[]}}',
      );
      expect(frame, isA<RpcResponse>());
      final response = frame as RpcResponse;
      expect(response.id, 7);
      expect(response.error, isNull);
      expect(response.result['sessions'].isList, isTrue);
    });

    test('an error response keeps the machine-readable reason', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","id":3,"error":{"code":4090,'
                '"message":"session is owned elsewhere",'
                '"data":{"reason":"SESSION_NOT_OWNED"}}}',
              )
              as RpcResponse;
      expect(frame.error?.code, 4090);
      expect(frame.error?.reason, 'SESSION_NOT_OWNED');
    });

    test('an event has a type, a session and a payload', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","method":"event","params":{'
                '"type":"message.delta","session_id":"s1",'
                '"payload":{"text":"Hel"}}}',
              )
              as RpcEvent;
      expect(frame.type, 'message.delta');
      expect(frame.sessionId, 's1');
      expect(frame.payload['text'].stringOrNull, 'Hel');
    });

    test('gateway.ready needs no session', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}}',
              )
              as RpcEvent;
      expect(frame.type, 'gateway.ready');
      expect(frame.sessionId, isNull);
    });

    test('a server request has a string id', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","id":"srq-1a2b","method":"clarify",'
                '"params":{"session_id":"s1","question":"Which?"}}',
              )
              as RpcServerRequest;
      expect(frame.id, 'srq-1a2b');
      expect(frame.method, 'clarify');
      expect(frame.params['question'].stringOrNull, 'Which?');
    });

    test('a server request with a numeric id is unreadable', () {
      // It could collide with one of our own request ids and settle the wrong
      // call, so it is never treated as a request or a response.
      expect(
        RpcFrame.parse('{"jsonrpc":"2.0","id":4,"method":"clarify"}'),
        isA<RpcUnreadable>(),
      );
    });

    test('an event without a type is unreadable', () {
      expect(
        RpcFrame.parse('{"jsonrpc":"2.0","method":"event","params":{}}'),
        isA<RpcUnreadable>(),
      );
    });

    test('garbage is unreadable, not an exception', () {
      expect(RpcFrame.parse('not json'), isA<RpcUnreadable>());
      expect(RpcFrame.parse('[1,2]'), isA<RpcUnreadable>());
    });
  });

  group('encode', () {
    test('a request omits empty params', () {
      final json = Json.decode(RpcEncode.request(1, 'ping', null));
      expect(json['jsonrpc'].stringOrNull, '2.0');
      expect(json['id'].intOrNull, 1);
      expect(json['method'].stringOrNull, 'ping');
      expect(json['params'].exists, isFalse);
      expect(Json.decode(RpcEncode.request(2, 'x', {}))['params'].exists, isFalse);
    });

    test('a request carries its params', () {
      final json = Json.decode(
        RpcEncode.request(3, 'session.resume', {'session_id': 's1'}),
      );
      expect(json['params']['session_id'].stringOrNull, 's1');
    });

    test('a decline echoes the string id', () {
      final json = Json.decode(
        RpcEncode.errorReply('srq-9', RpcCodes.methodNotFound, 'no handler'),
      );
      expect(json['id'].stringOrNull, 'srq-9');
      expect(json['error']['code'].intOrNull, -32601);
    });
  });

  group('method not found', () {
    test('is recognised by code', () {
      expect(
        const RpcError(code: -32601, message: 'x').isMethodNotFound,
        isTrue,
      );
    });

    test('is recognised by wording', () {
      expect(
        const RpcError(message: 'Unknown method: ping').isMethodNotFound,
        isTrue,
      );
      expect(const RpcError(message: 'busy').isMethodNotFound, isFalse);
    });

    test('is reachable from a failure', () {
      const failure = IrisFailure(
        FailureKind.rejected,
        cause: RpcError(code: -32601, message: 'x'),
      );
      expect(failure.rpcError?.isMethodNotFound, isTrue);
    });
  });
}
