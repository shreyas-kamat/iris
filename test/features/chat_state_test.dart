/// How events change an open conversation, including the streaming edges.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/chat_state.dart';

void main() {
  const ready = ChatState(phase: ChatPhase.ready);

  test('deltas build one live reply', () {
    final state = ready
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'Hel'))
        .apply(const TextDelta('r', 'lo'));
    final reply = state.items.single as AssistantTurn;
    expect(reply.text, 'Hello');
    expect(reply.streaming, isTrue);
    expect(state.turn, TurnPhase.streaming);
    expect(state.running, isTrue);
  });

  test('completion settles the reply and ends the turn', () {
    final state = ready
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'Hello'))
        .apply(const MessageCompleted('r'));
    final reply = state.items.single as AssistantTurn;
    expect(reply.text, 'Hello');
    expect(reply.streaming, isFalse);
    expect(state.turn, TurnPhase.idle);
  });

  test('completion fills in text the deltas missed', () {
    final state = ready
        .withUserTurn('hi')
        .apply(const MessageStarted('r'))
        .apply(const MessageCompleted('r', content: 'All of it'));
    expect(state.items.last, isA<AssistantTurn>().having((t) => t.text, 'text', 'All of it'));
  });

  test('completion does not repeat text from before a tool', () {
    final state = ready
        .withUserTurn('check it')
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'Checking.'))
        .apply(const ToolStarted('r', toolId: 't1', name: 'terminal'))
        .apply(const ToolCompleted('r', toolId: 't1', name: 'terminal', output: 'ok'))
        .apply(const MessageCompleted('r', content: 'Checking. Done.'));
    expect(state.items.map((i) => i.runtimeType), [UserTurn, AssistantTurn, ToolCall]);
    expect((state.items[1] as AssistantTurn).text, 'Checking.');
  });

  test('a tool call becomes a card that completes in place', () {
    var state = ready.apply(
      const ToolStarted('r', toolId: 't1', name: 'terminal', input: 'ls'),
    );
    final running = state.items.single as ToolCall;
    expect(running.status, ToolStatus.running);
    expect(running.arguments, 'ls');
    expect(state.turn, TurnPhase.working);
    state = state.apply(
      const ToolCompleted('r', toolId: 't1', name: 'terminal', output: 'a.txt'),
    );
    final done = state.items.single as ToolCall;
    expect(done.status, ToolStatus.done);
    expect(done.output, 'a.txt');
    expect(state.turn, TurnPhase.thinking);
  });

  test('a tool without ids is matched by name', () {
    final state = ready
        .apply(const ToolStarted('r', name: 'web'))
        .apply(const ToolCompleted('r', name: 'web', output: 'page', failed: true));
    final call = state.items.single as ToolCall;
    expect(call.status, ToolStatus.failed);
    expect(call.output, 'page');
  });

  test('text before a tool is kept as its own segment', () {
    final state = ready
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'Let me look.'))
        .apply(const ToolStarted('r', toolId: 't1', name: 'web'))
        .apply(const TextDelta('r', 'Found it.'));
    expect(state.items.map((i) => i.runtimeType), [AssistantTurn, ToolCall, AssistantTurn]);
    final first = state.items[0] as AssistantTurn;
    final last = state.items[2] as AssistantTurn;
    expect(first.text, 'Let me look.');
    expect(first.streaming, isFalse);
    expect(last.text, 'Found it.');
    expect(last.streaming, isTrue);
  });

  test('an empty live reply is dropped when a tool starts', () {
    final state = ready
        .apply(const MessageStarted('r'))
        .apply(const ToolStarted('r', toolId: 't1', name: 'web'));
    expect(state.items.single, isA<ToolCall>());
  });

  test('an error ends the turn with a notice', () {
    final state = ready.withUserTurn('hi').apply(const TurnFailed('r', 'boom'));
    expect(
      state.items.last,
      isA<Notice>()
          .having((n) => n.text, 'text', 'boom')
          .having((n) => n.isError, 'isError', isTrue),
    );
    expect(state.turn, TurnPhase.idle);
  });

  test('stopping adds a notice and ends the turn', () {
    final state = ready
        .withUserTurn('hi')
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'Part'))
        .apply(const TurnInterrupted('r'));
    expect(state.items.last, isA<Notice>().having((n) => n.text, 'text', 'Stopped.'));
    expect((state.items[1] as AssistantTurn).streaming, isFalse);
    expect(state.turn, TurnPhase.idle);
  });

  test('busy false settles a live reply', () {
    final state = ready
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'x'))
        .apply(const BusyChanged('r', busy: false));
    expect((state.items.single as AssistantTurn).streaming, isFalse);
    expect(state.turn, TurnPhase.idle);
  });

  test('the title updates', () {
    expect(ready.apply(const TitleChanged('r', 'Plans')).title, 'Plans');
  });

  group('decisions', () {
    const approval = ApprovalRequest(
      sessionId: 'r',
      command: 'ls',
      description: 'List',
      choices: ['once'],
      serverRequestId: 'srq-1',
    );

    test('an approval waits, and answering it resumes thinking', () {
      var state = ready.withUserTurn('x').apply(ApprovalAsked(approval));
      expect(state.turn, TurnPhase.waiting);
      expect(state.approvals.single.serverRequestId, 'srq-1');
      state = state.withoutApproval(approval);
      expect(state.approvals, isEmpty);
      expect(state.turn, TurnPhase.thinking);
    });

    test('the same approval announced twice shows once', () {
      final state = ready.apply(ApprovalAsked(approval)).apply(ApprovalAsked(approval));
      expect(state.approvals, hasLength(1));
    });

    test('a withdrawn request removes its card', () {
      final state = ready
          .apply(ApprovalAsked(approval))
          .apply(const RequestWithdrawn('r', 'srq-1'));
      expect(state.approvals, isEmpty);
    });

    test('answering one batch question keeps the rest', () {
      const request = ClarifyRequest(
        requestId: 'srq-2',
        sessionId: 'r',
        questions: [
          ClarifyQuestion(id: 'a', text: 'One?'),
          ClarifyQuestion(id: 'b', text: 'Two?'),
        ],
      );
      var state = ready.withUserTurn('x').apply(ClarifyAsked(request));
      expect(state.turn, TurnPhase.waiting);
      state = state.withoutQuestion(request, request.questions.first);
      expect(state.questions.single.questions.single.id, 'b');
      expect(state.turn, TurnPhase.waiting);
      state = state.withoutQuestion(state.questions.single, state.questions.single.questions.single);
      expect(state.questions, isEmpty);
      expect(state.turn, TurnPhase.thinking);
    });
  });

  test('the model follows ModelChanged', () {
    final state = ready.apply(
      const ModelChanged('r', model: 'gpt-6-luna', provider: 'openai-codex'),
    );
    expect(state.model, 'gpt-6-luna');
    expect(state.provider, 'openai-codex');
  });

  test('a notice keeps the turn; settled ends it', () {
    final running = ready.withUserTurn('/usage').withNotice('Tokens: 12k');
    expect(running.items.last, isA<Notice>().having((n) => n.text, 'text', 'Tokens: 12k'));
    expect(running.turn, TurnPhase.thinking);
    expect(running.settled().turn, TurnPhase.idle);
    expect(ready.withNotice('   ').items, isEmpty);
  });

  test('an earlier page goes above, and the cursor moves', () {
    const cursor = HistoryCursor(offset: 64, fromNewest: false);
    final newest = ready.withNewestPage(
      const [UserTurn(id: '65', text: 'newer')],
      cursor,
    );
    expect(newest.earlier?.offset, 64);
    final both = newest
        .copyWith(loadingEarlier: true)
        .withEarlierPage(const [UserTurn(id: '1', text: 'older')], null);
    expect(both.items.map((i) => i.id), ['1', '65']);
    expect(both.earlier, isNull);
    expect(both.loadingEarlier, isFalse);
  });
}
