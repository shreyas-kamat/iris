/// The real chat backend against a scripted socket and HTTP server.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/connection_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

void main() {
  late FakeHttp http;
  late FakeWireSocket socket;
  late DashboardSession session;
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
    session = DashboardSession(
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

  List<Map<String, Object?>> rows(int from, int to) => [
    for (var i = from; i <= to; i++)
      {'id': i, 'role': 'user', 'content': 'm$i'},
  ];

  group('conversations and profiles', () {
    test(
      'lists conversations over REST for the profile, a page at a time',
      () async {
        Map<String, String>? query;
        http.on('GET', '/api/profiles/sessions', (request) {
          query = request.uri.queryParameters;
          return FakeReply.json({
            'sessions': [
              {
                'id': 'a',
                'title': null,
                'preview': 'Hello',
                'profile': 'default',
              },
            ],
            'total': 256,
            'limit': 50,
            'offset': 50,
          });
        });
        final page = (await chat.conversations(50)).valueOrNull!;
        expect(page.items.single.title, 'Hello');
        expect(page.items.single.profile, 'default');
        expect(page.total, 256);
        expect(query, containsPair('profile', 'default'));
        expect(query, containsPair('offset', '50'));
        expect(query, containsPair('limit', '50'));
        expect(query, containsPair('order', 'recent'));
      },
    );

    test('lists profiles', () async {
      http.on(
        'GET',
        '/api/profiles',
        (_) => FakeReply.json({
          'profiles': [
            {'name': 'default', 'is_default': true},
            {'name': 'ananta', 'is_default': false},
          ],
        }),
      );
      final profiles = (await chat.profiles()).valueOrNull!;
      expect(profiles.map((p) => p.name), ['default', 'ananta']);
    });
  });

  group('history', () {
    test(
      'a dashboard that pages from the oldest opens on the newest page',
      () async {
        http
          ..on('GET', '/api/sessions/abc/messages', (request) {
            final q = request.uri.queryParameters;
            final offset = int.parse(q['offset']!);
            final limit = int.parse(q['limit']!);
            final last = math.min(offset + limit, 184);
            return FakeReply.json({
              'session_id': 'abc',
              'messages': rows(offset + 1, last),
              'pagination': {
                'limit': limit,
                'offset': offset,
                'returned': math.max(0, last - offset),
              },
            });
          })
          ..on(
            'GET',
            '/api/sessions/abc',
            (_) => FakeReply.json({'id': 'abc', 'message_count': 184}),
          );
        final page = (await chat.history('abc')).valueOrNull!;
        expect(page.items.first.id, '65');
        expect(page.items.last.id, '184');
        expect(page.earlier?.offset, 64);
        expect(page.earlier?.fromNewest, isFalse);

        final earlier = (await chat.history(
          'abc',
          before: page.earlier,
        )).valueOrNull!;
        expect(earlier.items.first.id, '1');
        expect(earlier.items.last.id, '64');
        expect(earlier.earlier, isNull);
      },
    );

    test('a dashboard that honours order=latest is used as it is', () async {
      http.on(
        'GET',
        '/api/sessions/abc/messages',
        (_) => FakeReply.json({
          'messages': rows(65, 184),
          'pagination': {
            'limit': 120,
            'offset': 0,
            'returned': 120,
            'order': 'latest',
          },
        }),
      );
      final page = (await chat.history('abc')).valueOrNull!;
      expect(page.items.last.id, '184');
      expect(page.earlier?.offset, 120);
      expect(page.earlier?.fromNewest, isTrue);
      expect(http.to('/api/sessions/abc'), isEmpty);
    });

    test('a short conversation is a single page', () async {
      http.on(
        'GET',
        '/api/sessions/abc/messages',
        (_) => FakeReply.json({
          'messages': rows(1, 5),
          'pagination': {'limit': 120, 'offset': 0, 'returned': 5},
        }),
      );
      final page = (await chat.history('abc')).valueOrNull!;
      expect(page.items, hasLength(5));
      expect(page.earlier, isNull);
      expect(http.to('/api/sessions/abc'), isEmpty);
      final sent = http.to('/api/sessions/abc/messages').single;
      expect(sent.uri.queryParameters.containsKey('profile'), isFalse);
    });

    test('a named profile scopes its routes and calls', () async {
      final scoped = DashboardChat(session, profile: 'ananta');
      addTearDown(scoped.dispose);
      http.on(
        'GET',
        '/api/sessions/abc/messages',
        (_) => FakeReply.json({'messages': rows(1, 2)}),
      );
      await scoped.history('abc');
      expect(
        http
            .to('/api/sessions/abc/messages')
            .single
            .uri
            .queryParameters['profile'],
        'ananta',
      );
      final resume = scoped.resume('abc');
      final resumed = await answer({'session_id': 'run-1'});
      expect(resumed['params']['profile'].stringOrNull, 'ananta');
      await resume;
      final create = scoped.create();
      final created = await answer({'session_id': 'run-2'});
      expect(created['params']['profile'].stringOrNull, 'ananta');
      await create;
    });
  });

  test(
    'resume returns the runtime id, model and decisions still waiting',
    () async {
      final future = chat.resume('abc');
      final sent = await answer({
        'session_id': 'run-1',
        'running': true,
        'info': {'model': 'gpt-6.1-sol', 'provider': 'openai-codex'},
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
      expect(sent['params']['profile'].exists, isFalse);
      final resumed = (await future).valueOrNull!;
      expect(resumed.runtimeId, 'run-1');
      expect(resumed.running, isTrue);
      expect(resumed.model, 'gpt-6.1-sol');
      expect(resumed.provider, 'openai-codex');
      // Both the question and the secret prompt are shown; nothing is declined.
      expect(resumed.pending, [isA<ClarifyAsked>(), isA<InputAsked>()]);
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
    expect(sent['params']['profile'].exists, isFalse);
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

  group('attachments', () {
    final png = Attachment(name: 'a.png', bytes: Uint8List.fromList([1]));
    final txt = Attachment(name: 'n.txt', bytes: Uint8List.fromList([104]));

    test('an image goes up as image bytes and needs no reference', () async {
      final future = chat.attach('run-1', png);
      final sent = await answer({'path': '/s/a.png'});
      expect(sent['method'].stringOrNull, 'image.attach_bytes');
      expect(sent['params']['content_base64'].stringOrNull, 'AQ==');
      expect(sent['params']['filename'].stringOrNull, 'a.png');
      expect((await future).valueOrNull, isNull);
    });

    test('a file goes up as a data URL and returns its reference', () async {
      final future = chat.attach('run-1', txt);
      final sent = await answer({'ref_text': '@file:/s/n.txt'});
      expect(sent['method'].stringOrNull, 'file.attach');
      expect(
        sent['params']['data_url'].stringOrNull,
        'data:text/plain;base64,aA==',
      );
      expect((await future).valueOrNull, '@file:/s/n.txt');
    });

    test('a reply with only a path builds a quoted reference', () async {
      final future = chat.attach('run-1', txt);
      await answer({'path': '/s/my notes.txt'});
      expect((await future).valueOrNull, '@file:`/s/my notes.txt`');
    });

    test('an image Hermes refuses as an image goes up as a file', () async {
      final future = chat.attach('run-1', png);
      await Future<void>.delayed(Duration.zero);
      socket.replyToLast(error: {'code': 4016, 'message': 'unsupported image'});
      final sent = await answer({'ref_text': '@file:/s/a.png'});
      expect(sent['method'].stringOrNull, 'file.attach');
      expect((await future).valueOrNull, '@file:/s/a.png');
    });

    test('any other image failure is reported', () async {
      final future = chat.attach('run-1', png);
      await Future<void>.delayed(Duration.zero);
      socket.replyToLast(error: {'code': 5000, 'message': 'disk full'});
      expect((await future).failureOrNull?.kind, FailureKind.rejected);
    });
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

  group('models', () {
    test('options for the live session', () async {
      final options = chat.modelOptions(runtimeId: 'run-1');
      final sent = await answer({
        'model': 'gpt-6.1-sol',
        'provider': 'openai-codex',
        'providers': [
          {
            'slug': 'openai-codex',
            'name': 'OpenAI Codex',
            'authenticated': true,
            'models': ['gpt-6.1-sol', 'gpt-6-luna'],
          },
        ],
      });
      expect(sent['method'].stringOrNull, 'model.options');
      expect(sent['params']['explicit_only'].boolOrNull, isTrue);
      expect(sent['params']['session_id'].stringOrNull, 'run-1');
      final got = (await options).valueOrNull!;
      expect(got.model, 'gpt-6.1-sol');
      expect(got.usable.single.models, ['gpt-6.1-sol', 'gpt-6-luna']);
    });

    test('a switch that needs confirming, then confirmed', () async {
      final first = chat.switchModel(
        'run-1',
        model: 'gpt-6-luna',
        provider: 'openai-codex',
        confirmed: false,
      );
      final asked = await answer({
        'confirm_required': true,
        'confirm_message': 'Expensive.',
      });
      expect(asked['method'].stringOrNull, 'config.set');
      expect(asked['params']['key'].stringOrNull, 'model');
      expect(asked['params']['session_id'].stringOrNull, 'run-1');
      expect(
        asked['params']['value'].stringOrNull,
        'gpt-6-luna --provider openai-codex --session',
      );
      expect(asked['params']['confirm_expensive_model'].exists, isFalse);
      final outcome = (await first).valueOrNull!;
      expect(outcome.confirmRequired, isTrue);
      expect(outcome.confirmMessage, 'Expensive.');

      final second = chat.switchModel(
        'run-1',
        model: 'gpt-6-luna',
        provider: 'openai-codex',
        confirmed: true,
      );
      final again = await answer({
        'value': 'gpt-6-luna --provider openai-codex --session',
      });
      expect(again['params']['confirm_expensive_model'].boolOrNull, isTrue);
      expect((await second).valueOrNull?.model, 'gpt-6-luna');
    });
  });

  group('slash commands', () {
    test('the catalogue, and a command run without its slash', () async {
      final catalog = chat.commands();
      final asked = await answer({
        'pairs': [
          ['/new', 'Start a new session'],
          ['/model', 'Switch model'],
        ],
      });
      expect(asked['method'].stringOrNull, 'commands.catalog');
      expect((await catalog).valueOrNull?.map((c) => c.name), [
        '/new',
        '/model',
      ]);

      final run = chat.runSlash('run-1', '/usage');
      final sent = await answer({'type': 'exec', 'output': 'Tokens: 12k'});
      expect(sent['method'].stringOrNull, 'slash.exec');
      expect(sent['params']['session_id'].stringOrNull, 'run-1');
      expect(sent['params']['command'].stringOrNull, 'usage');
      final outcome = (await run).valueOrNull!;
      expect(outcome.kind, SlashKind.exec);
      expect(outcome.text, 'Tokens: 12k');
    });

    test(
      'a command slash.exec declines falls back to command.dispatch',
      () async {
        final run = chat.runSlash('run-1', '/plan write the tests');
        await Future<void>.delayed(Duration.zero);
        socket.replyToLast(
          error: {
            'code': 4004,
            'message': 'skill command: use command.dispatch for /plan',
          },
        );
        final dispatched = await answer({
          'type': 'send',
          'message': 'Plan: write the tests',
        });
        expect(dispatched['method'].stringOrNull, 'command.dispatch');
        expect(dispatched['params']['name'].stringOrNull, 'plan');
        expect(dispatched['params']['arg'].stringOrNull, 'write the tests');
        final outcome = (await run).valueOrNull!;
        expect(outcome.kind, SlashKind.send);
        expect(outcome.text, 'Plan: write the tests');
      },
    );

    test(
      'a slash command that fails without a gateway answer is not dispatched again',
      () async {
        // Only a gateway rejection proves the command did not run. A timeout or
        // a dropped socket may mean it is running, and dispatching it again
        // could run it twice. A dropped socket takes the same path as a
        // timeout, without a 30-second wait.
        final first = socket;
        final run = chat.runSlash('run-1', '/compress');
        await Future<void>.delayed(Duration.zero);
        await first.serverCloses();
        final result = await run;
        expect(result.failureOrNull?.kind, FailureKind.offline);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final everything = [...first.sent, ...socket.sent];
        expect(
          everything.where((frame) => frame.contains('command.dispatch')),
          isEmpty,
        );
      },
    );
  });

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

  group('phase 4', () {
    test('a steer reaches the session; a rejection says so', () async {
      final accepted = chat.steer('run-1', 'use the staging db');
      final sent = await answer({'status': 'queued'});
      expect(sent['method'].string(), 'session.steer');
      expect(sent['params']['session_id'].string(), 'run-1');
      expect(sent['params']['text'].string(), 'use the staging db');
      expect((await accepted).valueOrNull, SteerOutcome.accepted);

      final rejected = chat.steer('run-1', 'x');
      await answer({'status': 'rejected'});
      expect((await rejected).valueOrNull, SteerOutcome.rejected);
    });

    test(
      'a sudo request is presented, not declined, and answered with a value',
      () async {
        final asked = chat.events.firstWhere((e) => e is InputAsked);
        socket.serverSends({
          'jsonrpc': '2.0',
          'id': 'srq-5',
          'method': 'sudo',
          'params': {'session_id': 'run-1', 'command': 'apt install jq'},
        });
        final event = await asked as InputAsked;
        // Nothing was sent back: a decline would be an error frame.
        expect(socket.sent.where((f) => f.contains('srq-5')), isEmpty);

        expect((await chat.answerInput(event.request, 'hunter2')).isOk, isTrue);
        final reply = socket.lastSent;
        expect(reply['id'].string(), 'srq-5');
        expect(reply['result']['value'].string(), 'hunter2');
      },
    );

    test('answering an input without a live socket fails offline', () async {
      // A session that was never started has no socket to answer on.
      final idleConnection = ServerConnection.create(
        const ServerConfig(
          id: 'idle',
          baseUrl: 'https://h.example',
          label: 'H',
        ),
        adapter: FakeHttp(),
      );
      final idleSession = DashboardSession(
        http: idleConnection,
        connector: (uri, headers) async => FakeWireSocket(),
      );
      final idle = DashboardChat(idleSession);
      addTearDown(() async {
        await idle.dispose();
        await idleSession.dispose();
        idleConnection.close();
      });
      final result = await idle.answerInput(
        const InputRequest(
          requestId: 'srq-1',
          sessionId: 'run-1',
          kind: InputKind.secret,
        ),
        'value',
      );
      expect(result.failureOrNull?.kind, FailureKind.offline);
    });

    test('rename and archive patch the stored session', () async {
      final bodies = <Object?>[];
      http.on('PATCH', '/api/sessions/abc', (request) {
        bodies.add(request.data);
        return FakeReply.json({'ok': true});
      });
      expect((await chat.rename('abc', 'Deploy notes')).isOk, isTrue);
      expect((await chat.setArchived('abc', archived: true)).isOk, isTrue);
      expect(bodies, [
        {'title': 'Deploy notes'},
        {'archived': true},
      ]);
    });

    test('a named profile carries itself in the patch body', () async {
      final named = DashboardChat(session, profile: 'ananta');
      addTearDown(named.dispose);
      Object? body;
      http.on('PATCH', '/api/sessions/abc', (request) {
        body = request.data;
        return FakeReply.json({'ok': true});
      });
      await named.setArchived('abc', archived: false);
      expect(body, {'archived': false, 'profile': 'ananta'});
    });

    test('archived conversations ask for archived only', () async {
      Map<String, String>? query;
      http.on('GET', '/api/profiles/sessions', (request) {
        query = request.uri.queryParameters;
        return FakeReply.json({
          'sessions': [
            {'id': 'z', 'title': 'Old'},
          ],
          'total': 1,
        });
      });
      final page = (await chat.archivedConversations(0)).valueOrNull!;
      expect(page.items.single.id, 'z');
      expect(query, containsPair('archived', 'only'));
      expect(query, containsPair('profile', 'default'));
    });

    test('search names the profile and folds rows per conversation', () async {
      Map<String, String>? query;
      http.on('GET', '/api/sessions/search', (request) {
        query = request.uri.queryParameters;
        return FakeReply.json({
          'results': [
            {
              'session_id': 'a',
              'title': 'Deploy',
              'snippet': '>>>deploy<<< it',
            },
            {'session_id': 'a', 'title': 'Deploy', 'snippet': 'again'},
          ],
        });
      });
      final hits = (await chat.search('deploy')).valueOrNull!;
      expect(hits.single.storedId, 'a');
      expect(query, containsPair('q', 'deploy'));
      expect(query, containsPair('profile', 'default'));
      expect(query, containsPair('limit', '${DashboardChat.searchLimit}'));
    });

    test('session.info reports the context window as an event', () async {
      final context = chat.events.firstWhere((e) => e is ContextChanged);
      socket.serverSends({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'session.info',
          'session_id': 'run-1',
          'payload': {
            'model': 'm',
            'context_percent': 0.25,
            'context_max': 400,
          },
        },
      });
      expect(((await context) as ContextChanged).usage.percent, 25);
    });

    test('a resume carries the context window when it has one', () async {
      final resumed = chat.resume('abc');
      await answer({
        'session_id': 'run-9',
        'info': {'model': 'm', 'context_used': 30, 'context_max': 120},
      });
      expect((await resumed).valueOrNull?.context?.percent, 25);
    });

    test(
      'a resume that carries a pending connection re-announces it',
      () async {
        final pending = chat.resume('stored-1');
        await answer({
          'session_id': 'run-1',
          'info': <String, Object?>{},
          'pending_connection': {
            'op_id': 'op9',
            'timeout_seconds': 60,
            'targets': [
              {
                'name': 'Linear',
                'kind': 'connector',
                'action': 'authorize',
                'state': 'pending',
              },
            ],
          },
        });
        final resumed = (await pending).valueOrNull!;
        final asked = resumed.pending.whereType<ConnectionAsked>().single;
        expect(asked.request.opId, 'op9');
        expect(asked.request.sessionId, 'run-1');
      },
    );

    test('a resume without a pending connection adds nothing', () async {
      final pending = chat.resume('stored-1');
      await answer({'session_id': 'run-1', 'info': <String, Object?>{}});
      expect((await pending).valueOrNull!.pending, isEmpty);
    });
  });

  group('transcription', () {
    test('posts the clip as a WAV data URL and returns the words', () async {
      Object? body;
      http.on('POST', '/api/audio/transcribe', (request) {
        body = request.data;
        return FakeReply.json({'transcript': '  hello there '});
      });
      final result = await chat.transcribe(Uint8List.fromList([1, 2]));
      expect(result.valueOrNull, 'hello there');
      expect((body as Map)['data_url'], 'data:audio/wav;base64,AQI=');
      expect((body as Map)['mime_type'], 'audio/wav');
    });

    test('an error field is a failure in Hermes words', () async {
      http.on(
        'POST',
        '/api/audio/transcribe',
        (_) => FakeReply.json({
          'error': 'No speech-to-text provider is configured',
        }),
      );
      final result = await chat.transcribe(Uint8List(1));
      expect(result.failureOrNull?.message, contains('speech-to-text'));
    });

    test('a named profile is passed along', () async {
      Map<String, dynamic>? query;
      http.on('POST', '/api/audio/transcribe', (request) {
        query = request.queryParameters;
        return FakeReply.json({'text': 'hi'});
      });
      final named = DashboardChat(session, profile: 'work');
      addTearDown(named.dispose);
      await named.transcribe(Uint8List(1));
      expect(query?['profile'], 'work');
    });
  });

  group('Phase 6 calls', () {
    test('delete is a REST DELETE, scoped to the profile', () async {
      Uri? seen;
      String? method;
      http.on('DELETE', '/api/sessions/abc', (request) {
        seen = request.uri;
        method = request.method;
        return FakeReply.json({'deleted': 'abc'});
      });
      expect((await chat.delete('abc')).isOk, isTrue);
      expect(method, 'DELETE');
      expect(
        seen?.queryParameters,
        isEmpty,
        reason: 'the default profile is implicit',
      );
    });

    test('a named profile is sent with the delete', () async {
      Uri? seen;
      http.on('DELETE', '/api/sessions/abc', (request) {
        seen = request.uri;
        return FakeReply.json({'deleted': 'abc'});
      });
      final named = DashboardChat(session, profile: 'ananta');
      addTearDown(named.dispose);
      await named.delete('abc');
      expect(seen?.queryParameters['profile'], 'ananta');
    });

    test('undo returns how many messages were removed', () async {
      final pending = chat.undo('run-1');
      final sent = await answer({'removed': 2});
      expect(sent['method'].string(), 'session.undo');
      expect(sent['params']['session_id'].string(), 'run-1');
      expect((await pending).valueOrNull, 2);
    });

    test(
      'branchWhole copies a stored parent and returns the child ids',
      () async {
        final pending = chat.branchWhole('parent-1');
        final sent = await answer({
          'session_id': 'run-9',
          'stored_session_id': 'stored-9',
        });
        expect(sent['method'].string(), 'session.branch_stored');
        expect(sent['params']['parent_session_id'].string(), 'parent-1');
        final child = (await pending).valueOrNull!;
        expect(child.runtimeId, 'run-9');
        expect(child.storedId, 'stored-9');
      },
    );

    test('branchFrom seeds a new session with the prefix', () async {
      final pending = chat.branchFrom('parent-1', const [
        SeedMessage('user', 'hi'),
        SeedMessage('assistant', 'hello'),
      ], title: 'Branch of x');
      final sent = await answer({
        'session_id': 'run-9',
        'stored_session_id': 'stored-9',
      });
      expect(sent['method'].string(), 'session.create');
      expect(sent['params']['parent_session_id'].string(), 'parent-1');
      expect(sent['params']['title'].string(), 'Branch of x');
      expect(sent['params']['messages'].list.map((m) => m['role'].string()), [
        'user',
        'assistant',
      ]);
      expect((await pending).valueOrNull?.storedId, 'stored-9');
    });

    test('compress asks the session to summarise itself', () async {
      final pending = chat.compress('run-1');
      final sent = await answer({'status': 'ok'});
      expect(sent['method'].string(), 'session.compress');
      expect((await pending).isOk, isTrue);
    });

    test('submit reports what Hermes did with a busy message', () async {
      final pending = chat.submit('run-1', 'later', queued: true);
      final sent = await answer({'status': 'queued'});
      expect(sent['params']['queued'].boolean(), isTrue);
      expect((await pending).valueOrNull, SubmitOutcome.queued);
    });

    test('an ordinary submit does not send the queued flag', () async {
      final pending = chat.submit('run-1', 'now');
      final sent = await answer({'status': 'streaming'});
      expect(sent['params']['queued'].exists, isFalse);
      expect((await pending).valueOrNull, SubmitOutcome.started);
    });

    test('the busy mode is read with status and written by name', () async {
      final read = chat.busyMode();
      var sent = await answer({'value': 'queue'});
      expect(sent['params']['key'].string(), 'busy');
      expect(sent['params']['value'].string(), 'status');
      expect((await read).valueOrNull, BusyMode.queue);

      final write = chat.setBusyMode(BusyMode.steer);
      sent = await answer({'value': 'steer'});
      expect(sent['params']['value'].string(), 'steer');
      expect((await write).isOk, isTrue);
    });

    test('reasoning and fast are session-scoped config', () async {
      final effort = chat.setReasoning('run-1', ReasoningEffort.high);
      var sent = await answer({'value': 'high'});
      expect(sent['params']['key'].string(), 'reasoning');
      expect(sent['params']['session_id'].string(), 'run-1');
      expect(sent['params']['value'].string(), 'high');
      await effort;

      final fast = chat.setFast('run-1', fast: true);
      sent = await answer({'value': 'fast'});
      expect(sent['params']['key'].string(), 'fast');
      expect(sent['params']['value'].string(), 'fast');
      await fast;
    });

    test(
      'a login is answered with a JSON value on the request frame',
      () async {
        const login = LoginRequest(
          requestId: 'srq-3',
          sessionId: 'run-1',
          origin: 'https://github.com',
        );
        final result = await chat.answerLogin(
          login,
          identifier: 'jamie@hermes.dev',
          password: 'hunter2',
        );
        expect(result.isOk, isTrue);
        final reply = socket.lastSent;
        expect(reply['id'].string(), 'srq-3');
        final value = Json.decode(reply['result']['value'].string());
        expect(value['identifier'].string(), 'jamie@hermes.dev');
        expect(value['password'].string(), 'hunter2');
      },
    );

    test('skipping a login sends an empty value, not an empty login', () async {
      const login = LoginRequest(
        requestId: 'srq-3',
        sessionId: 'run-1',
        origin: 'https://github.com',
      );
      await chat.answerLogin(login, identifier: '', password: '');
      expect(socket.lastSent['result']['value'].string(), '');
    });

    test(
      'a connection answer names the owner session and each target',
      () async {
        final request = ConnectionRequest.parse(
          Json.of({'op_id': 'op1', 'timeout_seconds': 60}),
          sessionId: 'run-1',
        )!;
        final pending = chat.answerConnection(request, const [
          TargetAnswer.approved('GitHub', env: {'GITHUB_TOKEN': 'ghp_x'}),
          TargetAnswer.skipped('Linear'),
        ], settle: true);
        final sent = await answer({'status': 'ok', 'settled': true});
        final params = sent['params'];
        expect(sent['method'].string(), 'connection.respond');
        expect(params['owner']['type'].string(), 'session');
        expect(params['owner']['session_id'].string(), 'run-1');
        expect(params['op_id'].string(), 'op1');
        expect(params['result']['settled_by'].string(), 'continue');
        expect(
          params['result']['targets'].list.map((t) => t['status'].string()),
          ['approved', 'skipped'],
        );
        expect(
          params['result']['targets'].list.first['env']['GITHUB_TOKEN']
              .string(),
          'ghp_x',
        );
        expect((await pending).isOk, isTrue);
      },
    );

    test('active sessions list the replying ones', () async {
      final pending = chat.activeSessions();
      await answer({
        'sessions': [
          {'id': 'r1', 'session_key': 's1', 'status': 'working'},
          {'id': 'r2', 'session_key': 's2', 'status': 'idle'},
          {'status': 'working'},
        ],
      });
      final rows = (await pending).valueOrNull!;
      expect(rows.map((r) => r.storedId), [
        's1',
        's2',
      ], reason: 'a row without an id is dropped');
      expect(rows.where((r) => r.replying).map((r) => r.storedId), ['s1']);
    });

    test('the dashboard events stream carries the new events', () async {
      final events = <ChatEvent>[];
      final sub = chat.events.listen(events.add);
      addTearDown(sub.cancel);
      socket.pushRequest('srq-5', 'vault.unlock_prompt', {
        'session_id': 'run-1',
        'display_name': '1Password',
      });
      socket.pushEvent('session.info', 'run-1', {'reasoning_effort': 'low'});
      await Future<void>.delayed(Duration.zero);
      expect(
        events.whereType<InputAsked>().single.request.kind,
        InputKind.vaultUnlock,
      );
      expect(
        events.whereType<SessionInfoChanged>().single.effort,
        ReasoningEffort.low,
      );
    });
  });

  test('one conversation is read by id, scoped to the profile', () async {
    http.on(
      'GET',
      '/api/sessions/abc',
      (_) => FakeReply.json({
        'id': 'abc',
        'title': 'Old notes',
        'message_count': 3,
      }),
    );
    final row = (await chat.conversation('abc')).valueOrNull!;
    expect(row.id, 'abc');
    expect(row.title, 'Old notes');
    expect(row.messageCount, 3);
  });

  test('a conversation that is gone is a notFound failure', () async {
    http.on(
      'GET',
      '/api/sessions/gone',
      (_) => FakeReply.json({'detail': 'not found'}, status: 404),
    );
    expect(
      (await chat.conversation('gone')).failureOrNull?.kind,
      FailureKind.notFound,
    );
  });
}
