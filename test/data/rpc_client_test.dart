/// Request/response matching, events, declines, timeouts and shutdown.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/rpc/rpc_client.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

import '../support/fake_wire_socket.dart';

void main() {
  late FakeWireSocket socket;
  late RpcClient client;

  setUp(() {
    socket = FakeWireSocket();
    client = RpcClient(socket);
  });

  tearDown(() => client.close());

  test('a request is a JSON-RPC text frame with an integer id', () {
    client.call('session.list');
    final frame = socket.lastSent;
    expect(frame['jsonrpc'].stringOrNull, '2.0');
    expect(frame['method'].stringOrNull, 'session.list');
    expect(frame['id'].raw, isA<int>());
    expect(frame['params'].exists, isFalse);
  });

  test('a response settles its own request', () async {
    final call = client.call('session.list');
    socket.replyToLast(result: {'sessions': <Object>[]});
    final result = await call;
    expect(result.valueOrNull?['sessions'].isList, isTrue);
  });

  test('responses are matched by id, not by order', () async {
    final first = client.call('a');
    final firstId = socket.lastSent['id'].raw;
    final second = client.call('b');
    socket.replyToLast(result: 'B');
    socket.serverSends({'jsonrpc': '2.0', 'id': firstId, 'result': 'A'});
    expect((await first).valueOrNull?.stringOrNull, 'A');
    expect((await second).valueOrNull?.stringOrNull, 'B');
  });

  test('an error response is a rejected failure carrying the RpcError', () async {
    final call = client.call('prompt.submit');
    socket.replyToLast(
      error: {
        'code': 4090,
        'message': 'owned elsewhere',
        'data': {'reason': 'SESSION_NOT_OWNED'},
      },
    );
    final failure = (await call).failureOrNull!;
    expect(failure.kind, FailureKind.rejected);
    expect(failure.rpcError?.reason, 'SESSION_NOT_OWNED');
    expect(failure.endpoint, 'prompt.submit');
  });

  test('an unanswered request times out', () async {
    final result = await client.call(
      'slow',
      timeout: const Duration(milliseconds: 20),
    );
    expect(result.failureOrNull?.kind, FailureKind.timeout);
  });

  test('a closed socket fails pending calls and completes done', () async {
    final call = client.call('session.list');
    await socket.serverCloses();
    expect((await call).failureOrNull?.kind, FailureKind.offline);
    await client.done;
    expect(client.isOpen, isFalse);
    expect(
      (await client.call('again')).failureOrNull?.kind,
      FailureKind.offline,
    );
  });

  test('events are forwarded', () async {
    final next = client.events.first;
    socket.serverSends({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready'},
    });
    expect((await next).type, 'gateway.ready');
  });

  test('a server request is declined at once, echoing its id', () async {
    socket.serverSends({
      'jsonrpc': '2.0',
      'id': 'srq-1',
      'method': 'clarify',
      'params': {'session_id': 's1'},
    });
    await Future<void>.delayed(Duration.zero);
    final reply = socket.lastSent;
    expect(reply['id'].stringOrNull, 'srq-1');
    expect(reply['error']['code'].intOrNull, RpcCodes.methodNotFound);
  });

  test('ping treats method-not-found as alive', () async {
    final ping = client.ping();
    socket.replyToLast(error: {'code': -32601, 'message': 'Method not found'});
    expect((await ping).isOk, isTrue);
  });

  test('ping reports a real failure', () async {
    final ping = client.ping(timeout: const Duration(milliseconds: 20));
    expect((await ping).failureOrNull?.kind, FailureKind.timeout);
  });

  group('presented server requests', () {
    late FakeWireSocket presentedSocket;
    late RpcClient presenting;

    setUp(() {
      presentedSocket = FakeWireSocket();
      presenting = RpcClient(presentedSocket, presented: const {'approval'});
    });

    tearDown(() => presenting.close());

    test('are handed over instead of declined', () async {
      final next = presenting.serverRequests.first;
      presentedSocket.serverSends({
        'jsonrpc': '2.0',
        'id': 'srq-9',
        'method': 'approval',
        'params': {'session_id': 's1', 'command': 'rm -rf build'},
      });
      final request = await next;
      expect(request.id, 'srq-9');
      expect(request.params['command'].stringOrNull, 'rm -rf build');
      expect(presentedSocket.sent, isEmpty);
    });

    test('others are still declined', () async {
      presentedSocket.serverSends({
        'jsonrpc': '2.0',
        'id': 'srq-2',
        'method': 'secret',
        'params': {'session_id': 's1'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        presentedSocket.lastSent['error']['code'].intOrNull,
        RpcCodes.methodNotFound,
      );
    });

    test('reply answers with a result frame echoing the id', () {
      expect(presenting.reply('srq-9', {'answer': 'yes'}), isTrue);
      final frame = presentedSocket.lastSent;
      expect(frame['id'].stringOrNull, 'srq-9');
      expect(frame['result']['answer'].stringOrNull, 'yes');
      expect(frame['error'].exists, isFalse);
    });

    test('reply after the socket closed reports false', () async {
      await presentedSocket.serverCloses();
      await presenting.done;
      expect(presenting.reply('srq-9', {'answer': 'yes'}), isFalse);
    });
  });
}
