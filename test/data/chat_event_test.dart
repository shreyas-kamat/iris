/// Stream events and server requests become chat events, with every field
/// spelling Hermes has used.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/connection_models.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

RpcEvent event(String type, {Map<String, Object?> payload = const {}}) =>
    RpcEvent(
      type: type,
      sessionId: 'r1',
      payload: Json.of(payload),
      raw: Json.of({'type': type, 'session_id': 'r1', 'payload': payload}),
    );

RpcServerRequest request(
  String id,
  String method,
  Map<String, Object?> params,
) => RpcServerRequest(id: id, method: method, params: Json.of(params));

void main() {
  test('a delta carries its text and session', () {
    final parsed = ChatEvent.fromEvent(
      event('message.delta', payload: {'text': 'Hel'}),
    );
    expect(parsed, isA<TextDelta>().having((e) => e.text, 'text', 'Hel'));
    expect(parsed?.sessionId, 'r1');
  });

  test('an empty delta is dropped', () {
    expect(
      ChatEvent.fromEvent(event('message.delta', payload: {'text': ''})),
      isNull,
    );
  });

  test('reasoning arrives under any of its names', () {
    for (final key in ['reasoning', 'reasoning_content', 'text']) {
      final parsed = ChatEvent.fromEvent(
        event('reasoning.delta', payload: {key: 'hmm'}),
      );
      expect(
        parsed,
        isA<ReasoningDelta>().having((e) => e.text, 'text', 'hmm'),
        reason: key,
      );
    }
  });

  test('thinking.delta, the name Hermes 0.18.2 streams, is reasoning', () {
    // Seen on the real server: thinking.delta {text}, then message.delta,
    // reasoning.available, message.complete {text, usage, status}.
    expect(
      ChatEvent.fromEvent(event('thinking.delta', payload: {'text': 'hmm'})),
      isA<ReasoningDelta>().having((e) => e.text, 'text', 'hmm'),
    );
    expect(
      ChatEvent.fromEvent(event('reasoning.available', payload: {'text': 'x'})),
      isNull,
    );
  });

  test('a tool start reads its id, name and structured arguments', () {
    final parsed = ChatEvent.fromEvent(
      event(
        'tool.start',
        payload: {
          'tool_id': 't1',
          'name': 'terminal',
          'args': {'command': 'ls'},
        },
      ),
    );
    expect(parsed, isA<ToolStarted>());
    final start = parsed! as ToolStarted;
    expect(start.toolId, 't1');
    expect(start.name, 'terminal');
    expect(start.input, '{"command":"ls"}');
  });

  test('a tool result reads its output', () {
    final parsed = ChatEvent.fromEvent(
      event(
        'tool.complete',
        payload: {'tool_call_id': 't1', 'name': 'terminal', 'output': 'a.txt'},
      ),
    );
    final done = parsed! as ToolCompleted;
    expect(done.toolId, 't1');
    expect(done.output, 'a.txt');
    expect(done.failed, isFalse);
  });

  test('busy, completion, errors and titles', () {
    expect(
      ChatEvent.fromEvent(event('session.busy', payload: {'busy': false})),
      isA<BusyChanged>().having((e) => e.busy, 'busy', isFalse),
    );
    expect(
      ChatEvent.fromEvent(
        event('message.complete', payload: {'content': 'Hi'}),
      ),
      isA<MessageCompleted>().having((e) => e.content, 'content', 'Hi'),
    );
    expect(
      ChatEvent.fromEvent(event('error', payload: {'message': 'boom'})),
      isA<TurnFailed>().having((e) => e.message, 'message', 'boom'),
    );
    expect(
      ChatEvent.fromEvent(event('session.title', payload: {'title': 'Plans'})),
      isA<TitleChanged>().having((e) => e.title, 'title', 'Plans'),
    );
    expect(
      ChatEvent.fromEvent(event('message.interrupted')),
      isA<TurnInterrupted>(),
    );
  });

  test('an approval event offers the default choices', () {
    final parsed = ChatEvent.fromEvent(
      event(
        'approval.request',
        payload: {
          'command': 'rm -rf build',
          'description': 'Delete build output',
          'request_id': 'q1',
        },
      ),
    );
    final approval = (parsed! as ApprovalAsked).request;
    expect(approval.choices, ['once', 'session', 'always', 'deny']);
    expect(approval.queueId, 'q1');
    expect(approval.serverRequestId, isNull);
    expect(approval.command, 'rm -rf build');
    expect(parsed.sessionId, 'r1');
  });

  test('an approval that forbids permanent drops always', () {
    final parsed = ChatEvent.fromEvent(
      event(
        'approval.request',
        payload: {'command': 'ls', 'allow_permanent': false},
      ),
    );
    expect((parsed! as ApprovalAsked).request.choices, [
      'once',
      'session',
      'deny',
    ]);
  });

  test('an approval server request keeps both ids and its choices', () {
    final parsed = ChatEvent.fromServerRequest(
      request('srq-1', 'approval', {
        'session_id': 'r1',
        'request_id': 'q9',
        'command': 'git push',
        'choices': ['once', 'deny'],
      }),
    );
    final approval = (parsed! as ApprovalAsked).request;
    expect(approval.serverRequestId, 'srq-1');
    expect(approval.queueId, 'q9');
    expect(approval.choices, ['once', 'deny']);
    expect(approval.matches('srq-1'), isTrue);
    expect(approval.matches('q9'), isTrue);
  });

  test('an approval without a session is dropped', () {
    expect(
      ChatEvent.fromServerRequest(
        request('srq-1', 'approval', {'command': 'ls'}),
      ),
      isNull,
    );
  });

  test('a single clarify question gets a synthetic id', () {
    final parsed = ChatEvent.fromServerRequest(
      request('srq-2', 'clarify', {
        'session_id': 'r1',
        'question': 'Which branch?',
        'choices': [
          'main',
          {'label': 'Dev', 'value': 'dev'},
        ],
      }),
    );
    final clarify = (parsed! as ClarifyAsked).request;
    expect(clarify.requestId, 'srq-2');
    expect(clarify.isServerRequest, isTrue);
    final question = clarify.questions.single;
    expect(question.synthetic, isTrue);
    expect(question.text, 'Which branch?');
    expect(question.choices.map((c) => c.label), ['main', 'Dev']);
    expect(question.choices.map((c) => c.value), ['main', 'dev']);
  });

  test('batch clarify questions keep their qids and drop duplicates', () {
    final parsed = ChatEvent.fromServerRequest(
      request('srq-3', 'clarify', {
        'session_id': 'r1',
        'questions': [
          {'qid': 'a', 'question': 'One?'},
          {'qid': 'b', 'question': 'Two?'},
          {'qid': 'a', 'question': 'dup'},
        ],
      }),
    );
    final clarify = (parsed! as ClarifyAsked).request;
    expect(clarify.questions.map((q) => q.id), ['a', 'b']);
    expect(clarify.questions.every((q) => !q.synthetic), isTrue);
  });

  test('a clarify without a question is dropped', () {
    expect(
      ChatEvent.fromServerRequest(
        request('srq-4', 'clarify', {'session_id': 'r1'}),
      ),
      isNull,
    );
  });

  test('a withdrawn request names its id', () {
    expect(
      ChatEvent.fromEvent(
        event(
          'request.cancel',
          payload: {'id': 'srq-2', 'method': 'clarify', 'reason': 'timeout'},
        ),
      ),
      isA<RequestWithdrawn>().having((e) => e.requestId, 'requestId', 'srq-2'),
    );
    expect(
      ChatEvent.fromEvent(
        event('clarify.expire', payload: {'request_id': 'c-1'}),
      ),
      isA<RequestWithdrawn>().having((e) => e.requestId, 'requestId', 'c-1'),
    );
  });

  test('unknown events and other server requests are ignored', () {
    expect(ChatEvent.fromEvent(event('context.update')), isNull);
    expect(
      ChatEvent.fromServerRequest(
        request('srq-5', 'vault.save_login', {'session_id': 'r1'}),
      ),
      isNull,
    );
  });

  test('the model in use arrives in session.info and model.update', () {
    final info = ChatEvent.fromEvent(
      event('session.info', payload: {'model': 'gpt-6.1-sol', 'provider': 'openai-codex'}),
    );
    expect(info, isA<ModelChanged>().having((e) => e.model, 'model', 'gpt-6.1-sol'));
    expect((info! as ModelChanged).provider, 'openai-codex');
    expect(
      ChatEvent.fromEvent(event('model.update', payload: {'model': 'gpt-6-luna'})),
      isA<ModelChanged>().having((e) => e.model, 'model', 'gpt-6-luna'),
    );
    expect(ChatEvent.fromEvent(event('session.info', payload: {'running': true})), isNull);
  });

  test('sudo and secret requests become input prompts', () {
    final sudo = ChatEvent.fromServerRequest(
      request('srq-7', 'sudo', {'session_id': 'r1', 'command': 'apt install jq'}),
    );
    expect(
      sudo,
      isA<InputAsked>()
          .having((e) => e.request.kind, 'kind', InputKind.sudo)
          .having((e) => e.request.command, 'command', 'apt install jq')
          .having((e) => e.request.requestId, 'id', 'srq-7')
          .having((e) => e.sessionId, 'session', 'r1'),
    );
    final secret = ChatEvent.fromServerRequest(
      request('srq-8', 'secret', {'session_id': 'r1', 'env_var': 'GITHUB_TOKEN', 'prompt': ''}),
    );
    expect(
      (secret! as InputAsked).request.title,
      'Hermes needs a value for GITHUB_TOKEN',
    );
  });

  test('an input prompt without a session is not shown', () {
    expect(
      ChatEvent.fromServerRequest(request('srq-9', 'sudo', {'command': 'x'})),
      isNull,
    );
  });

  test('session.info and session.usage carry the context window', () {
    final info = ChatEvent.contextFromEvent(
      event('session.info', payload: {'model': 'm', 'context_percent': 0.5, 'context_max': 100}),
    );
    expect(info, isA<ContextChanged>().having((e) => e.usage.percent, 'percent', 50));
    final usage = ChatEvent.contextFromEvent(
      event('session.usage', payload: {'usage': {'context_used': 10, 'context_max': 40}}),
    );
    expect(usage?.usage.percent, 25);
    expect(ChatEvent.contextFromEvent(event('message.delta', payload: {'text': 'x'})), isNull);
    expect(ChatEvent.contextFromEvent(event('session.info', payload: {'model': 'm'})), isNull);
  });

  group('Phase 6 server requests and events', () {
    test('vault unlock and code become input prompts', () {
      final unlock = ChatEvent.fromServerRequest(
        request('srq-1', 'vault.unlock_prompt', {
          'session_id': 'r1',
          'backend': 'onepassword',
          'display_name': '1Password',
        }),
      );
      expect(
        unlock,
        isA<InputAsked>()
            .having((e) => e.request.kind, 'kind', InputKind.vaultUnlock)
            .having((e) => e.request.displayName, 'name', '1Password'),
      );
      final code = ChatEvent.fromServerRequest(
        request('srq-2', 'vault.code', {
          'session_id': 'r1',
          'site': 'GitHub',
          'hint': '6 digits from your authenticator app',
        }),
      );
      expect(
        code,
        isA<InputAsked>()
            .having((e) => e.request.kind, 'kind', InputKind.vaultCode)
            .having((e) => e.request.site, 'site', 'GitHub')
            .having((e) => e.request.hint, 'hint', contains('6 digits')),
      );
    });

    test('save_login becomes a login prompt', () {
      final parsed = ChatEvent.fromServerRequest(
        request('srq-3', 'vault.save_login', {
          'session_id': 'r1',
          'origin': 'https://github.com',
          'site': 'GitHub',
        }),
      );
      expect(
        parsed,
        isA<LoginAsked>()
            .having((e) => e.request.origin, 'origin', 'https://github.com')
            .having((e) => e.request.siteName, 'siteName', 'GitHub'),
      );
    });

    test('a login prompt without a session is dropped', () {
      expect(
        ChatEvent.fromServerRequest(
          request('srq-3', 'vault.save_login', {'origin': 'https://x.test'}),
        ),
        isNull,
      );
    });

    test('connection.request and connection.update become card events', () {
      final asked = ChatEvent.fromEvent(
        event('connection.request', payload: {
          'op_id': 'op1',
          'timeout_seconds': 60,
          'targets': [
            {'name': 'Linear', 'kind': 'connector', 'action': 'authorize', 'state': 'pending'},
          ],
        }),
      );
      expect(
        asked,
        isA<ConnectionAsked>().having((e) => e.request.opId, 'op', 'op1'),
      );
      final changed = ChatEvent.fromEvent(
        event('connection.update', payload: {
          'op_id': 'op1',
          'settled': false,
          'targets': [
            {'name': 'Linear', 'kind': 'connector', 'action': 'authorize', 'state': 'connected'},
          ],
        }),
      );
      expect(
        changed,
        isA<ConnectionChanged>()
            .having((e) => e.opId, 'op', 'op1')
            .having((e) => e.targets.single.state, 'state', TargetState.connected),
      );
    });

    test('session.info carries the effort and fast mode', () {
      final info = ChatEvent.infoFromEvent(
        event('session.info', payload: {'model': 'm', 'reasoning_effort': 'high', 'fast': true}),
      );
      expect(
        info,
        isA<SessionInfoChanged>()
            .having((e) => e.effort, 'effort', ReasoningEffort.high)
            .having((e) => e.fast, 'fast', isTrue),
      );
    });

    test('effort may arrive as a dict, and fast as a service tier', () {
      final info = ChatEvent.infoFromEvent(
        event('session.info', payload: {
          'reasoning': {'enabled': false},
          'service_tier': 'priority',
        }),
      );
      expect(
        info,
        isA<SessionInfoChanged>()
            .having((e) => e.effort, 'effort', ReasoningEffort.none)
            .having((e) => e.fast, 'fast', isTrue),
      );
    });

    test('a session.info with neither field makes no info event', () {
      expect(
        ChatEvent.infoFromEvent(event('session.info', payload: {'model': 'm'})),
        isNull,
      );
    });
  });

  group('Phase 6 value types', () {
    test('busy modes round-trip and default to interrupt', () {
      expect(BusyMode.fromWire('queue'), BusyMode.queue);
      expect(BusyMode.fromWire(' STEER '), BusyMode.steer);
      expect(BusyMode.fromWire(null), BusyMode.interrupt);
      expect(BusyMode.fromWire('???'), BusyMode.interrupt);
    });

    test('efforts fold Hermes spellings onto the five Iris shows', () {
      expect(ReasoningEffort.fromWire('minimal'), ReasoningEffort.low);
      expect(ReasoningEffort.fromWire('xhigh'), ReasoningEffort.max);
      expect(ReasoningEffort.fromWire('false'), ReasoningEffort.none);
      expect(ReasoningEffort.fromWire('banana'), isNull);
      expect(ReasoningEffort.high.wire, 'high');
    });

    test('a live status is replying while working or waiting', () {
      const working = LiveStatus(runtimeId: 'r', storedId: 's', status: 'working');
      const idle = LiveStatus(runtimeId: 'r', storedId: 's', status: 'idle');
      const starting = LiveStatus(runtimeId: 'r', storedId: 's', status: 'starting');
      expect(working.replying, isTrue);
      expect(idle.replying, isFalse);
      expect(starting.replying, isFalse, reason: 'starting is not a turn');
    });
  });

}
