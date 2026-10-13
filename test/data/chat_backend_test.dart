/// The real chat backend against a scripted socket and HTTP server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

void main() {
  late FakeHttp http;
  late FakeWireSocket socket;
  late DashboardChat chat;

  setUp(() async {
    http = FakeHttp()
      ..on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => FakeReply.json({'ticket': 't'}),
      );
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'H'),
      adapter: http,
    );
    final session = DashboardSession(
      http: connection,
      backoff: (_) => Duration.zero,
      connector: (uri, headers) async => socket = FakeWireSocket(),
    );
    await session.start();
    chat = DashboardChat(session);
    addTearDown(() async {
      await chat.dispose();
      await session.dispose();
      connection.close();
    });
  });

  /// Answers the request the chat just sent, and returns that request.
  Future<Json> answer(Object? result) async {
    await Future<void>.delayed(Duration.zero);
    final sent = socket.lastSent;
    socket.replyToLast(result: result);
    return sent;
  }

  test('lists conversations over session.list', () async {
    final future = chat.conversations();
    final sent = await answer({
      'sessions': [
        {'id': 'a', 'title': 'One'},
      ],
    });
    expect(sent['method'].stringOrNull, 'session.list');
    expect((await future).valueOrNull?.single.title, 'One');
  });

  test('reads history over REST, newest page first', () async {
    Map<String, String>? query;
    http.on('GET', '/api/sessions/abc/messages', (request) {
      query = request.uri.queryParameters;
      return FakeReply.json({
        'session_id': 'abc',
        'messages': [
          {'id': 1, 'role': 'user', 'content': 'hi'},
        ],
      });
    });
    final items = (await chat.history('abc')).valueOrNull!;
    expect(items.single, isA<UserTurn>());
    expect(query, containsPair('order', 'latest'));
    expect(query, containsPair('limit', '120'));
    expect(query, containsPair('include_compacted', 'true'));
  });

  test(
    'resume returns the runtime id and the decisions still waiting',
    () async {
      final future = chat.resume('abc');
      final sent = await answer({
        'session_id': 'run-1',
        'running': true,
        'open_requests': [
          {
            'id': 'srq-1',
            'method': 'clarify',
            'params': {'session_id': 'run-1', 'question': 'Which?'},
          },
          {
            'id': 'srq-2',
            'method': 'secret',
            'params': {'session_id': 'run-1'},
          },
        ],
      });
      expect(sent['method'].stringOrNull, 'session.resume');
      expect(sent['params']['session_id'].stringOrNull, 'abc');
      expect(sent['params']['omit_messages'].boolOrNull, isTrue);
      final resumed = (await future).valueOrNull!;
      expect(resumed.runtimeId, 'run-1');
      expect(resumed.running, isTrue);
      expect(resumed.pending.single, isA<ClarifyAsked>());
    },
  );

  test('create returns both ids', () async {
    final future = chat.create();
    final sent = await answer({
      'session_id': 'run-2',
      'stored_session_id': 'st-2',
    });
    expect(sent['method'].stringOrNull, 'session.create');
    expect(sent['params']['source'].stringOrNull, 'desktop');
    final created = (await future).valueOrNull!;
    expect(created.runtimeId, 'run-2');
    expect(created.storedId, 'st-2');
  });

  test('create without a session id is malformed', () async {
    final future = chat.create();
    await answer(<String, Object?>{});
    expect((await future).failureOrNull?.kind, FailureKind.malformed);
  });

  test('submit sends the text to the runtime session', () async {
    final future = chat.submit('run-1', 'hello');
    final sent = await answer({'status': 'streaming'});
    expect(sent['method'].stringOrNull, 'prompt.submit');
    expect(sent['params']['session_id'].stringOrNull, 'run-1');
    expect(sent['params']['text'].stringOrNull, 'hello');
    expect((await future).isOk, isTrue);
  });

  test('interrupt stops the runtime session', () async {
    final future = chat.interrupt('run-1');
    final sent = await answer({'ok': true});
    expect(sent['method'].stringOrNull, 'session.interrupt');
    expect(sent['params']['session_id'].stringOrNull, 'run-1');
    expect((await future).isOk, isTrue);
  });

  test('an approval answer names its queue entry', () async {
    const request = ApprovalRequest(
      sessionId: 'run-1',
      command: 'ls',
      description: 'List files',
      choices: ['once', 'deny'],
      queueId: 'q1',
      serverRequestId: 'srq-3',
    );
    final future = chat.answerApproval(request, 'once');
    final sent = await answer({'resolved': 1});
    expect(sent['method'].stringOrNull, 'approval.respond');
    expect(sent['params']['choice'].stringOrNull, 'once');
    expect(sent['params']['session_id'].stringOrNull, 'run-1');
    expect(sent['params']['request_id'].stringOrNull, 'q1');
    expect((await future).isOk, isTrue);
  });

  test(
    'a single server-request question is answered with a result frame',
    () async {
      const request = ClarifyRequest(
        requestId: 'srq-4',
        sessionId: 'run-1',
        questions: [ClarifyQuestion(id: 'q0', text: 'Which?', synthetic: true)],
      );
      final result = await chat.answerClarify(
        request,
        request.questions.single,
        'main',
      );
      expect(result.isOk, isTrue);
      expect(socket.lastSent['id'].stringOrNull, 'srq-4');
      expect(socket.lastSent['result']['answer'].stringOrNull, 'main');
      expect(socket.lastSent['method'].exists, isFalse);
    },
  );

  test('a batch question is locked by its qid', () async {
    const request = ClarifyRequest(
      requestId: 'srq-5',
      sessionId: 'run-1',
      questions: [
        ClarifyQuestion(id: 'a', text: 'One?'),
        ClarifyQuestion(id: 'b', text: 'Two?'),
      ],
    );
    final future = chat.answerClarify(request, request.questions.first, 'x');
    final sent = await answer({
      'status': 'ok',
      'remaining': ['b'],
    });
    expect(sent['method'].stringOrNull, 'clarify.lock');
    expect(sent['params']['request_id'].stringOrNull, 'srq-5');
    expect(sent['params']['question_id'].stringOrNull, 'a');
    expect(sent['params']['answer'].stringOrNull, 'x');
    expect((await future).isOk, isTrue);
  });

  test(
    'a legacy clarify uses clarify.respond without a made-up question id',
    () async {
      const request = ClarifyRequest(
        requestId: 'c-1',
        sessionId: 'run-1',
        questions: [ClarifyQuestion(id: 'q0', text: 'Which?', synthetic: true)],
      );
      final future = chat.answerClarify(
        request,
        request.questions.single,
        'main',
      );
      final sent = await answer({'status': 'ok'});
      expect(sent['method'].stringOrNull, 'clarify.respond');
      expect(sent['params']['request_id'].stringOrNull, 'c-1');
      expect(sent['params']['answer'].stringOrNull, 'main');
      expect(sent['params']['question_id'].exists, isFalse);
      expect((await future).isOk, isTrue);
    },
  );

  test('stream events and server requests arrive as chat events', () async {
    final events = <ChatEvent>[];
    final subscription = chat.events.listen(events.add);
    addTearDown(subscription.cancel);
    socket
      ..serverSends({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'message.delta',
          'session_id': 'run-1',
          'payload': {'text': 'Hi'},
        },
      })
      ..serverSends({
        'jsonrpc': '2.0',
        'id': 'srq-6',
        'method': 'approval',
        'params': {'session_id': 'run-1', 'command': 'ls'},
      });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events.map((e) => e.runtimeType), [TextDelta, ApprovalAsked]);
  });

  test('a reconnect is announced once the link is live again', () async {
    var reconnects = 0;
    final subscription = chat.reconnected.listen((_) => reconnects++);
    addTearDown(subscription.cancel);
    final first = socket;
    await first.serverCloses();
    for (var i = 0; i < 100 && reconnects == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(reconnects, 1);
    expect(identical(socket, first), isFalse);
  });
}
