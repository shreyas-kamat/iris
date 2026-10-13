/// One open conversation: loading, following its own events, sending,
/// stopping and answering.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/chat/chat_state.dart';

import '../support/fake_chat_backend.dart';

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  ChatController controllerFor({String? id = 'stored-1'}) {
    final controller = ChatController(backend, conversationId: id);
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  const approval = ApprovalRequest(
    sessionId: 'run-1',
    command: 'git push',
    description: 'Push',
    choices: ['once', 'deny'],
    serverRequestId: 'srq-1',
  );

  test('opening reads the history, then attaches', () async {
    backend.historyResult = const Ok([UserTurn(id: '1', text: 'hi')]);
    final controller = controllerFor();
    await controller.open();
    expect(backend.calls, ['history stored-1', 'resume stored-1']);
    expect(controller.value.phase, ChatPhase.ready);
    expect(controller.value.items.single, isA<UserTurn>());
  });

  test('a history failure is shown, not thrown', () async {
    backend.historyResult = const Err(IrisFailure(FailureKind.notFound));
    final controller = controllerFor();
    await controller.open();
    expect(controller.value.phase, ChatPhase.failed);
    expect(controller.value.failure?.kind, FailureKind.notFound);
    expect(backend.calls, isNot(contains('resume stored-1')));
  });

  test('events for this conversation stream in; others are ignored', () async {
    final controller = controllerFor();
    await controller.open();
    backend
      ..emit(const TextDelta('run-1', 'Hi'))
      ..emit(const TextDelta('someone-else', 'X'));
    await settle();
    expect(
      controller.value.items.single,
      isA<AssistantTurn>().having((t) => t.text, 'text', 'Hi'),
    );
  });

  test('a decision still waiting from before shows at once', () async {
    backend.resumeResult = Ok(
      ResumedConversation(
        runtimeId: 'run-1',
        running: true,
        pending: [ApprovalAsked(approval)],
      ),
    );
    final controller = controllerFor();
    await controller.open();
    expect(controller.value.approvals.single.command, 'git push');
    expect(controller.value.turn, TurnPhase.waiting);
  });

  test(
    'sending shows the message and submits it to the runtime session',
    () async {
      final controller = controllerFor();
      await controller.open();
      await controller.send('  hello  ');
      expect(backend.submitted.single, ('run-1', 'hello'));
      expect(
        controller.value.items.last,
        isA<UserTurn>().having((t) => t.text, 'text', 'hello'),
      );
      expect(controller.value.turn, TurnPhase.thinking);
    },
  );

  test('a new chat is created on the first send', () async {
    final controller = controllerFor(id: null);
    await controller.open();
    expect(backend.calls, isEmpty);
    await controller.send('hi');
    expect(backend.calls, ['create']);
    expect(backend.submitted.single, ('run-new', 'hi'));
    expect(controller.conversationId, 'stored-new');
  });

  test('a failed send says why in the transcript', () async {
    backend.submitResult = const Err(IrisFailure.offline());
    final controller = controllerFor();
    await controller.open();
    await controller.send('hi');
    expect(
      controller.value.items.last,
      isA<Notice>()
          .having((n) => n.isError, 'isError', isTrue)
          .having((n) => n.text, 'text', contains('Not connected')),
    );
    expect(controller.value.turn, TurnPhase.idle);
  });

  test('nothing is sent while a turn is running', () async {
    final controller = controllerFor();
    await controller.open();
    await controller.send('one');
    await controller.send('two');
    expect(backend.submitted, hasLength(1));
  });

  test('stop interrupts the runtime session', () async {
    final controller = controllerFor();
    await controller.open();
    await controller.send('hi');
    await controller.stop();
    expect(backend.calls, contains('interrupt run-1'));
  });

  test('approving removes the card and answers', () async {
    backend.resumeResult = Ok(
      ResumedConversation(
        runtimeId: 'run-1',
        pending: [ApprovalAsked(approval)],
      ),
    );
    final controller = controllerFor();
    await controller.open();
    await controller.approve(controller.value.approvals.single, 'once');
    expect(backend.approvals, ['once']);
    expect(controller.value.approvals, isEmpty);
  });

  test('a failed answer puts the card back', () async {
    backend
      ..resumeResult = Ok(
        ResumedConversation(
          runtimeId: 'run-1',
          pending: [ApprovalAsked(approval)],
        ),
      )
      ..answerResult = const Err(IrisFailure.offline());
    final controller = controllerFor();
    await controller.open();
    await controller.approve(controller.value.approvals.single, 'once');
    expect(controller.value.approvals.single.serverRequestId, 'srq-1');
    expect(controller.value.items.last, isA<Notice>());
    expect(controller.value.turn, TurnPhase.waiting);
  });

  test('answering a question sends it and clears the card', () async {
    const clarify = ClarifyRequest(
      requestId: 'srq-2',
      sessionId: 'run-1',
      questions: [ClarifyQuestion(id: 'q0', text: 'Which?', synthetic: true)],
    );
    backend.resumeResult = Ok(
      ResumedConversation(runtimeId: 'run-1', pending: [ClarifyAsked(clarify)]),
    );
    final controller = controllerFor();
    await controller.open();
    await controller.answer(clarify, clarify.questions.single, ' main ');
    expect(backend.answers, ['q0=main']);
    expect(controller.value.questions, isEmpty);
  });

  test('a reconnect attaches again and catches up on the reply', () async {
    // Seen on the emulator: the socket dropped mid-turn, the reply went to the
    // old socket, and Stop then failed with "session not found".
    final controller = controllerFor();
    await controller.open();
    await controller.send('hi');
    backend
      ..historyResult = const Ok([
        UserTurn(id: '1', text: 'hi'),
        AssistantTurn(id: '2', text: 'pong'),
      ])
      ..resumeResult = const Ok(ResumedConversation(runtimeId: 'run-2'))
      ..reconnect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      backend.calls.where((call) => call == 'resume stored-1'),
      hasLength(2),
    );
    expect(
      controller.value.items.last,
      isA<AssistantTurn>().having((t) => t.text, 'text', 'pong'),
    );
    expect(controller.value.turn, TurnPhase.idle);
    backend.emit(const TextDelta('run-2', 'more'));
    await settle();
    expect(
      controller.value.items.last,
      isA<AssistantTurn>().having((t) => t.text, 'text', 'more'),
    );
  });

  test('a long conversation opens with a way to earlier messages', () async {
    backend
      ..historyResult = const Ok([UserTurn(id: '65', text: 'newest')])
      ..historyEarlier = const HistoryCursor(offset: 64, fromNewest: false)
      ..earlierResult = const Ok(
        HistoryPage(items: [UserTurn(id: '1', text: 'oldest')]),
      );
    final controller = controllerFor();
    await controller.open();
    expect(controller.value.earlier?.offset, 64);
    await controller.loadEarlier();
    expect(backend.calls, contains('earlier stored-1 64'));
    expect(controller.value.items.map((i) => i.id), ['1', '65']);
    expect(controller.value.earlier, isNull);
  });

  test('the model comes from the resume and follows the session', () async {
    backend.resumeResult = const Ok(
      ResumedConversation(
        runtimeId: 'run-1',
        model: 'gpt-6.1-sol',
        provider: 'openai-codex',
      ),
    );
    final controller = controllerFor();
    await controller.open();
    expect(controller.value.model, 'gpt-6.1-sol');
    backend.emit(const ModelChanged('run-1', model: 'gpt-6-luna'));
    await settle();
    expect(controller.value.model, 'gpt-6-luna');
  });

  test('a switch that needs confirming changes nothing', () async {
    backend.switchResult = const Ok(
      ModelSwitch(model: 'big', confirmRequired: true, confirmMessage: 'Costly'),
    );
    final controller = controllerFor();
    await controller.open();
    final result = await controller.switchModel('big', 'p', confirmed: false);
    expect(result.valueOrNull?.confirmRequired, isTrue);
    expect(controller.value.model, isNull);
    expect(controller.value.items, isEmpty);
  });

  test('a confirmed switch updates the model and says so', () async {
    backend.switchResult = const Ok(ModelSwitch(model: 'gpt-6-luna'));
    final controller = controllerFor();
    await controller.open();
    await controller.switchModel('gpt-6-luna', 'openai-codex', confirmed: true);
    expect(backend.switches, ['gpt-6-luna@openai-codex confirmed']);
    expect(controller.value.model, 'gpt-6-luna');
    expect(
      controller.value.items.last,
      isA<Notice>().having((n) => n.text, 'text', 'Now using gpt-6-luna.'),
    );
  });

  test('switching before the conversation exists says why', () async {
    final controller = controllerFor(id: null);
    await controller.open();
    final result = await controller.switchModel('m', 'p', confirmed: false);
    expect(result.isErr, isTrue);
    expect(backend.switches, isEmpty);
  });

  test('slash output is shown and the turn ends', () async {
    backend.slashResult = const Ok(
      SlashOutcome(kind: SlashKind.exec, text: 'Tokens: 12k'),
    );
    final controller = controllerFor();
    await controller.open();
    await controller.send('/usage');
    expect(backend.slashes, ['/usage']);
    expect(backend.submitted, isEmpty);
    expect(
      controller.value.items.map((i) => i.runtimeType),
      [UserTurn, Notice],
    );
    expect(
      controller.value.items.last,
      isA<Notice>().having((n) => n.text, 'text', 'Tokens: 12k'),
    );
    expect(controller.value.turn, TurnPhase.idle);
  });

  test('a slash command that expands to a prompt sends it', () async {
    backend.slashResult = const Ok(
      SlashOutcome(kind: SlashKind.send, text: 'Plan the week'),
    );
    final controller = controllerFor();
    await controller.open();
    await controller.send('/plan');
    expect(backend.submitted.single, ('run-1', 'Plan the week'));
    expect(
      controller.value.items.last,
      isA<UserTurn>().having((t) => t.text, 'text', 'Plan the week'),
    );
  });

  test('a prefill goes to the composer', () async {
    backend.slashResult = const Ok(
      SlashOutcome(kind: SlashKind.prefill, text: 'Write a plan for '),
    );
    final controller = controllerFor();
    String? prefilled;
    controller.onPrefill = (text) => prefilled = text;
    await controller.open();
    await controller.send('/plan');
    expect(prefilled, 'Write a plan for ');
    expect(controller.value.turn, TurnPhase.idle);
  });

  test('an alias runs its target with the same arguments, three deep at most', () async {
    backend.slashResult = const Ok(
      SlashOutcome(kind: SlashKind.alias, target: 'new'),
    );
    final controller = controllerFor();
    await controller.open();
    await controller.send('/n now');
    expect(backend.slashes, ['/n now', '/new now', '/new now', '/new now']);
    expect(
      controller.value.items.last,
      isA<Notice>().having(
        (n) => n.text,
        'text',
        'That command points nowhere.',
      ),
    );
  });

  test('commands load once, on demand', () async {
    backend.commandsResult = const Ok([
      SlashCommand(name: '/new', description: 'Start'),
    ]);
    final controller = controllerFor();
    await controller.open();
    expect(backend.calls, isNot(contains('commands')));
    await controller.loadCommands();
    await controller.loadCommands();
    expect(backend.calls.where((c) => c == 'commands'), hasLength(1));
    expect(controller.value.commands.single.name, '/new');
  });
}
