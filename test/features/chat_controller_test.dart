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

  test('sending shows the message and submits it to the runtime session', () async {
    final controller = controllerFor();
    await controller.open();
    await controller.send('  hello  ');
    expect(backend.submitted.single, ('run-1', 'hello'));
    expect(
      controller.value.items.last,
      isA<UserTurn>().having((t) => t.text, 'text', 'hello'),
    );
    expect(controller.value.turn, TurnPhase.thinking);
  });

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
      ResumedConversation(runtimeId: 'run-1', pending: [ApprovalAsked(approval)]),
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
        ResumedConversation(runtimeId: 'run-1', pending: [ApprovalAsked(approval)]),
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
}
