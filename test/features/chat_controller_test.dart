/// One open conversation: loading, following its own events, sending,
/// stopping and answering.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/connection_models.dart';
import 'package:iris/data/rpc/rpc_frame.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/chat/chat_state.dart';

import '../support/fake_chat_backend.dart';
import '../support/fakes.dart';

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

  test('attachments are staged, then named ahead of the prompt', () async {
    final controller = controllerFor();
    await controller.open();
    await controller.send(
      'read these',
      attachments: [
        Attachment(name: 'a.png', bytes: Uint8List(1)),
        Attachment(name: 'n.txt', bytes: Uint8List(1)),
      ],
    );
    expect(backend.attached.map((a) => a.$2), ['a.png', 'n.txt']);
    expect(backend.submitted.single.$2, '@file:/s/n.txt\n\nread these');
    final turn = controller.value.items.whereType<UserTurn>().single;
    expect(turn.text, 'read these');
    expect(turn.attachments, ['a.png', 'n.txt']);
  });

  test('a photo alone can be sent', () async {
    final controller = controllerFor();
    await controller.open();
    await controller.send(
      '',
      attachments: [Attachment(name: 'a.png', bytes: Uint8List(1))],
    );
    expect(backend.submitted.single.$2, '');
    expect(controller.value.items.whereType<UserTurn>().single.attachments, [
      'a.png',
    ]);
  });

  test('a failed upload is reported and nothing is submitted', () async {
    backend.attachResult = (_) => Err(const IrisFailure(FailureKind.offline));
    final controller = controllerFor();
    await controller.open();
    await controller.send(
      'hi',
      attachments: [Attachment(name: 'n.txt', bytes: Uint8List(1))],
    );
    expect(backend.submitted, isEmpty);
    expect(controller.value.items.last, isA<Notice>());
    expect(controller.value.turn, TurnPhase.idle);
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
    backend.busyModeResult = const Ok(BusyMode.queue);
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
        HistoryPage(
          items: [UserTurn(id: '1', text: 'oldest')],
        ),
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
      ModelSwitch(
        model: 'big',
        confirmRequired: true,
        confirmMessage: 'Costly',
      ),
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
    expect(controller.value.items.map((i) => i.runtimeType), [
      UserTurn,
      Notice,
    ]);
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

  test(
    'an alias runs its target with the same arguments, three deep at most',
    () async {
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
    },
  );

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
    // The server's commands come first; Iris's own are added after them.
    expect(controller.value.commands.first.name, '/new');
  });

  group('steering', () {
    Future<ChatController> running() async {
      backend.busyModeResult = const Ok(BusyMode.steer);
      final controller = controllerFor();
      await controller.open();
      await settle();
      backend.emit(const MessageStarted('run-1'));
      await settle();
      expect(controller.value.running, isTrue);
      return controller;
    }

    test('sending during a run steers it', () async {
      final controller = await running();
      await controller.send('use the staging db');
      expect(backend.steers, [('run-1', 'use the staging db')]);
      expect(backend.submitted, isEmpty);
      final last = controller.value.items.last as UserTurn;
      expect(last.steered, isTrue);
      expect(controller.value.running, isTrue);
    });

    test('slash text during a run neither steers nor sends', () async {
      final controller = await running();
      await controller.send('/model');
      expect(backend.steers, isEmpty);
      expect(backend.submitted, isEmpty);
      expect(backend.slashes, isEmpty);
    });

    test(
      'a rejected steer comes back to the composer while the run goes on',
      () async {
        backend.steerResult = const Ok(SteerOutcome.rejected);
        final controller = await running();
        String? returned;
        controller.onSteerReturned = (text) => returned = text;
        await controller.send('wait');
        expect(returned, 'wait');
        expect(controller.value.items.last, isA<Notice>());
        expect(backend.submitted, isEmpty);
      },
    );

    test('a rejected steer after the turn ended is sent as a prompt', () async {
      backend
        ..steerResult = const Ok(SteerOutcome.rejected)
        ..steerGate = Completer<void>();
      final controller = await running();
      final sending = controller.send('one more thing');
      backend.emit(const MessageCompleted('run-1', content: 'Done'));
      await settle();
      backend.steerGate!.complete();
      await sending;
      expect(backend.submitted, [('run-1', 'one more thing')]);
      expect((controller.value.items.last as UserTurn).steered, isFalse);
    });

    test('a steer that fails to send comes back to the composer', () async {
      backend.steerResult = const Err(IrisFailure(FailureKind.offline));
      final controller = await running();
      String? returned;
      controller.onSteerReturned = (text) => returned = text;
      await controller.send('later');
      expect(returned, 'later');
    });
  });

  group('retry', () {
    test(
      'runs /retry, then shows the transcript as Hermes now has it',
      () async {
        backend.slashResult = const Ok(
          SlashOutcome(kind: SlashKind.send, text: 'hello'),
        );
        final controller = controllerFor();
        await controller.open();
        backend.emit(const TurnFailed('run-1', 'Gateway timed out'));
        await settle();
        expect(
          controller.value.items.whereType<Notice>().single.retryable,
          isTrue,
        );

        backend.historyResult = const Ok([UserTurn(id: '9', text: 'hello')]);
        await controller.retry();
        expect(backend.slashes, ['/retry']);
        expect(controller.value.retrying, isTrue);

        backend.emit(const MessageCompleted('run-1', content: 'Hi'));
        await settle();
        await settle();
        expect(backend.calls.where((c) => c == 'history stored-1').length, 2);
        expect(controller.value.retrying, isFalse);
        expect(controller.value.items.single, isA<UserTurn>());
      },
    );

    test('does nothing while a turn runs', () async {
      final controller = controllerFor();
      await controller.open();
      backend.emit(const MessageStarted('run-1'));
      await settle();
      await controller.retry();
      expect(backend.slashes, isEmpty);
    });

    test(
      'each retry counts as an attempt, and a new message starts again',
      () async {
        backend.historyResult = const Ok([UserTurn(id: '1', text: 'x')]);
        final controller = controllerFor();
        await controller.open();
        backend.emit(const TurnFailed('run-1', 'boom'));
        await settle();
        expect(controller.value.attempt, 1);
        await controller.retry();
        expect(controller.value.attempt, 2);
        backend.emit(const MessageCompleted('run-1', content: 'ok'));
        await settle();
        await controller.send('next');
        expect(controller.value.attempt, 1);
      },
    );
  });

  group('input prompts', () {
    const sudo = InputRequest(
      requestId: 'srq-1',
      sessionId: 'run-1',
      kind: InputKind.sudo,
      command: 'apt install jq',
    );

    test('an answer is sent once and never kept', () async {
      final controller = controllerFor();
      await controller.open();
      backend.emit(InputAsked(sudo));
      await settle();
      expect(controller.value.inputs.single.requestId, 'srq-1');

      await controller.answerInput(sudo, 'hunter2');
      expect(backend.inputAnswers, [('srq-1', 'hunter2')]);
      expect(controller.value.inputs, isEmpty);
      expect(
        controller.value.items.whereType<PromptRecord>().single.title,
        'Ran with sudo',
      );
      expect(_mentions(controller.value, 'hunter2'), isFalse);
    });

    test('an empty answer skips', () async {
      final controller = controllerFor();
      await controller.open();
      backend.emit(InputAsked(sudo));
      await settle();
      await controller.answerInput(sudo, '');
      expect(backend.inputAnswers, [('srq-1', '')]);
      expect(
        controller.value.items.whereType<PromptRecord>().single.outcome,
        PromptOutcome.skipped,
      );
    });

    test(
      'a failed input answer brings the card back without the value',
      () async {
        backend.answerResult = const Err(IrisFailure(FailureKind.offline));
        final controller = controllerFor();
        await controller.open();
        backend.emit(InputAsked(sudo));
        await settle();
        await controller.answerInput(sudo, 'hunter2');
        expect(controller.value.inputs.single.requestId, 'srq-1');
        expect(
          controller.value.items.last,
          isA<Notice>().having((n) => n.isError, 'error', isTrue),
        );
        expect(_mentions(controller.value, 'hunter2'), isFalse);
      },
    );
  });

  test(
    'a password card from before a reconnect goes; the resume re-announces',
    () async {
      final controller = controllerFor();
      await controller.open();
      backend.emit(
        InputAsked(
          const InputRequest(
            requestId: 'srq-1',
            sessionId: 'run-1',
            kind: InputKind.sudo,
          ),
        ),
      );
      await settle();
      expect(controller.value.inputs, isNotEmpty);
      backend.reconnect();
      await settle();
      await settle();
      expect(controller.value.inputs, isEmpty);
    },
  );

  test('the context window from the resume shows at once', () async {
    backend.resumeResult = const Ok(
      ResumedConversation(
        runtimeId: 'run-1',
        context: ContextUsage(percent: 40, used: 4, max: 10),
      ),
    );
    final controller = controllerFor();
    await controller.open();
    expect(controller.value.context?.percent, 40);
  });

  group('undo', () {
    Future<(ChatController, List<String>)> opened() async {
      backend.historyResult = const Ok([
        UserTurn(id: '1', text: 'first'),
        AssistantTurn(id: '2', text: 'one'),
        UserTurn(id: '3', text: 'Draft the fix as a PR.'),
        AssistantTurn(id: '4', text: 'Opened #482'),
      ]);
      final toasts = <String>[];
      final controller = controllerFor()
        ..collapseDelay = Duration.zero
        ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
      await controller.open();
      return (controller, toasts);
    }

    test(
      'removes the last exchange, returns the prompt, and says so',
      () async {
        final (controller, toasts) = await opened();
        String? returned;
        controller.onPromptReturned = (text) => returned = text;
        await controller.undo();
        expect(backend.undos, ['run-1']);
        expect(controller.value.items.map((i) => i.id), ['1', '2']);
        expect(returned, 'Draft the fix as a PR.');
        expect(toasts.single, 'Undid the last turn');
      },
    );

    test(
      'is refused while a reply is running, without calling the server',
      () async {
        final (controller, toasts) = await opened();
        backend.emit(const MessageStarted('run-1'));
        await settle();
        await controller.undo();
        expect(backend.undos, isEmpty);
        expect(toasts.single, 'Stop the reply first to undo.');
      },
    );

    test(
      'a 4009 from Hermes gives the same advice and keeps the transcript',
      () async {
        final (controller, toasts) = await opened();
        backend.undoResult = const Err(
          IrisFailure(
            FailureKind.rejected,
            message: 'session busy',
            cause: RpcError(code: 4009, message: 'session busy'),
          ),
        );
        await controller.undo();
        expect(toasts.single, 'Stop the reply first to undo.');
        expect(controller.value.items, hasLength(4));
      },
    );

    test('a server without session.undo says so', () async {
      final (controller, toasts) = await opened();
      backend.undoResult = Err(unknownMethod('session.undo'));
      await controller.undo();
      expect(toasts.single, "Undo isn't supported on this server.");
      expect(controller.value.items, hasLength(4));
    });

    test('nothing removed means nothing changes', () async {
      final (controller, toasts) = await opened();
      backend.undoResult = const Ok(0);
      await controller.undo();
      expect(toasts.single, 'Nothing to undo');
      expect(controller.value.items, hasLength(4));
    });

    test(
      'steered turns inside the exchange go with it, and files are noted',
      () async {
        backend.historyResult = const Ok([
          UserTurn(id: '1', text: 'go', attachments: ['log.txt']),
          AssistantTurn(id: '2', text: 'working'),
          UserTurn(id: '3', text: 'only prod', steered: true),
          AssistantTurn(id: '4', text: 'done'),
        ]);
        final toasts = <String>[];
        final controller = controllerFor()
          ..collapseDelay = Duration.zero
          ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
        await controller.open();
        String? returned;
        controller.onPromptReturned = (text) => returned = text;
        await controller.undo();
        expect(controller.value.items, isEmpty);
        expect(returned, 'go');
        expect(toasts.single, 'Undid the last turn. Re-attach any files.');
      },
    );

    test(
      'typing /undo runs undo, not a slash command, and adds no bubble',
      () async {
        final (controller, _) = await opened();
        await controller.send('/undo');
        expect(backend.undos, ['run-1']);
        expect(backend.slashes, isEmpty);
      },
    );

    test(
      'with the user turn off the loaded page the newest page is reloaded',
      () async {
        backend.historyResult = const Ok([
          AssistantTurn(id: '9', text: 'tail of a long reply'),
        ]);
        final controller = controllerFor()..collapseDelay = Duration.zero;
        await controller.open();
        backend.calls.clear();
        await controller.undo();
        expect(backend.calls, contains('history stored-1'));
      },
    );
  });

  test('the local slash commands are always offered', () async {
    backend.commandsResult = const Ok([
      SlashCommand(name: '/help', description: 'Help'),
    ]);
    final controller = controllerFor();
    await controller.open();
    await controller.loadCommands();
    final names = controller.value.commands.map((c) => c.name);
    expect(
      names,
      containsAll(['/help', '/queue', '/steer', '/undo', '/branch']),
    );
  });

  group('branch', () {
    List<TranscriptItem> history() => const [
      UserTurn(id: '1', text: 'Why did it fail?'),
      AssistantTurn(id: '2', text: 'The backup job.'),
      ToolCall(id: 't', name: 'read_logs'),
      UserTurn(id: '3', text: 'Draft the fix.'),
      AssistantTurn(id: '4', text: 'Opened #482.'),
    ];

    test(
      'the seed keeps user and assistant text and drops tool calls and notices',
      () {
        final seed = ChatController.seedFrom([
          ...history(),
          const Notice(id: 'n', text: 'Stopped.'),
          const AssistantTurn(id: '5', text: '   '),
        ]);
        expect(
          [for (final m in seed) (m.role, m.content)],
          [
            ('user', 'Why did it fail?'),
            ('assistant', 'The backup job.'),
            ('user', 'Draft the fix.'),
            ('assistant', 'Opened #482.'),
          ],
        );
      },
    );

    test('the newest reply branches the whole stored chat', () async {
      backend.historyResult = Ok(history());
      final controller = controllerFor();
      await controller.open();
      final outcome = (await controller.branch(fromItemId: '4')).valueOrNull!;
      expect(backend.branches, ['stored-1']);
      expect(
        backend.branchPrefixes.single,
        isEmpty,
        reason: 'branchWhole carries no prefix',
      );
      expect(outcome.conversation.storedId, 'stored-branch');
      expect(outcome.summarised, isFalse);
    });

    test(
      'an older reply seeds a new session with the prefix through that reply',
      () async {
        backend.historyResult = Ok(history());
        final controller = controllerFor();
        await controller.open();
        final outcome = (await controller.branch(fromItemId: '2')).valueOrNull!;
        expect(
          [for (final m in backend.branchPrefixes.single) m.content],
          ['Why did it fail?', 'The backup job.'],
        );
        expect(outcome.count, 2);
      },
    );

    test('earlier pages are loaded before the prefix is built', () async {
      backend
        ..historyResult = const Ok([
          UserTurn(id: '3', text: 'Draft the fix.'),
          AssistantTurn(id: '4', text: 'Opened #482.'),
        ])
        ..historyEarlier = const HistoryCursor(offset: 64, fromNewest: false)
        ..earlierResult = const Ok(
          HistoryPage(
            items: [
              UserTurn(id: '1', text: 'Why did it fail?'),
              AssistantTurn(id: '2', text: 'The backup job.'),
            ],
          ),
        );
      final controller = controllerFor();
      await controller.open();
      await controller.branch(fromItemId: '2');
      expect(backend.calls, contains('earlier stored-1 64'));
      expect(backend.branchPrefixes.single.first.content, 'Why did it fail?');
    });

    test('a chat with no stored id cannot branch', () async {
      final controller = controllerFor(id: null);
      expect((await controller.branch(fromItemId: 'x')).isErr, isTrue);
      expect(backend.branches, isEmpty);
    });

    test('a reply that is still streaming cannot be branched from', () async {
      backend.historyResult = Ok(history());
      final controller = controllerFor();
      await controller.open();
      backend.emit(const MessageStarted('run-1'));
      backend.emit(const TextDelta('run-1', 'partial'));
      await settle();
      final live = controller.value.items.last.id;
      expect(controller.canBranchFrom(live), isFalse);
      expect(controller.canBranchFrom('2'), isTrue);
    });

    test(
      'summarise runs compress on the new chat, and a failure still opens it',
      () async {
        backend.historyResult = Ok(history());
        final controller = controllerFor();
        await controller.open();
        var outcome = (await controller.branch(summarise: true)).valueOrNull!;
        expect(backend.compressions, ['run-branch']);
        expect(outcome.summarised, isTrue);

        backend.compressResult = Err(unknownMethod('session.compress'));
        outcome = (await controller.branch(summarise: true)).valueOrNull!;
        expect(outcome.summarised, isFalse);
        expect(outcome.conversation.storedId, 'stored-branch');
      },
    );

    test('a server without session.branch_stored says so', () async {
      backend.historyResult = Ok(history());
      backend.branchResult = Err(unknownMethod('session.branch_stored'));
      final controller = controllerFor();
      await controller.open();
      final result = await controller.branch();
      expect(
        result.failureOrNull?.message,
        "This server can't branch conversations.",
      );
    });

    test('/branch branches the whole chat', () async {
      backend.historyResult = Ok(history());
      final controller = controllerFor();
      var branched = false;
      controller.onBranchRequested = () => branched = true;
      await controller.open();
      await controller.send('/branch');
      expect(branched, isTrue);
      expect(backend.slashes, isEmpty);
    });
  });

  group('effort and fast', () {
    test('setting the effort tells Hermes and shows at once', () async {
      final controller = controllerFor();
      await controller.open();
      expect(await controller.setEffort(ReasoningEffort.high), isTrue);
      expect(backend.efforts, [ReasoningEffort.high]);
      expect(controller.value.effort, ReasoningEffort.high);
    });

    test(
      'a failure is toasted and a known previous value comes back',
      () async {
        final toasts = <String>[];
        final controller = controllerFor()
          ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
        await controller.open();
        backend.emit(
          const SessionInfoChanged('run-1', effort: ReasoningEffort.low),
        );
        await settle();
        backend.effortResult = const Err(
          IrisFailure(FailureKind.rejected, message: 'no'),
        );
        expect(await controller.setEffort(ReasoningEffort.max), isFalse);
        expect(controller.value.effort, ReasoningEffort.low);
        expect(toasts.single, startsWith('Could not change'));
      },
    );

    test('a server without the setting says so', () async {
      final toasts = <String>[];
      final controller = controllerFor()
        ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
      await controller.open();
      backend.fastResult = Err(unknownMethod('config.set'));
      expect(await controller.setFast(fast: true), isFalse);
      expect(toasts.single, "This server can't change that.");
    });

    test('fast mode goes through', () async {
      final controller = controllerFor();
      await controller.open();
      expect(await controller.setFast(fast: true), isTrue);
      expect(backend.fasts, [true]);
      expect(controller.value.fast, isTrue);
    });
  });

  group('prompts', () {
    const unlock = InputRequest(
      requestId: 'srq-1',
      sessionId: 'run-1',
      kind: InputKind.vaultUnlock,
      displayName: '1Password',
    );
    const login = LoginRequest(
      requestId: 'srq-2',
      sessionId: 'run-1',
      origin: 'https://github.com',
      site: 'GitHub',
    );

    ChatController opened() =>
        controllerFor()..clock = () => DateTime(2026, 10, 16, 14, 2);

    String everything(ChatController c) => [
      for (final item in c.value.items)
        if (item is PromptRecord) '${item.title} ${item.detail}' else item.id,
      '${c.value.inputs}',
      '${c.value.logins}',
    ].join(' ');

    test(
      'answering an unlock sends the password, leaves a settled line, and keeps no trace',
      () async {
        final controller = opened();
        await controller.open();
        backend.emit(InputAsked(unlock));
        await settle();
        await controller.answerInput(unlock, 'hunter2');
        expect(backend.inputAnswers, [('srq-1', 'hunter2')]);
        expect(controller.value.inputs, isEmpty);
        final record = controller.value.items.whereType<PromptRecord>().single;
        expect(record.title, 'Unlocked 1Password');
        expect(record.outcome, PromptOutcome.answered);
        expect(everything(controller), isNot(contains('hunter2')));
      },
    );

    test('skipping records a skip and sends an empty value', () async {
      final controller = opened();
      await controller.open();
      backend.emit(InputAsked(unlock));
      await settle();
      await controller.answerInput(unlock, '');
      expect(backend.inputAnswers, [('srq-1', '')]);
      expect(
        controller.value.items.whereType<PromptRecord>().single.outcome,
        PromptOutcome.skipped,
      );
    });

    test(
      'a send that fails brings the card back and records nothing',
      () async {
        final controller = opened();
        await controller.open();
        backend.emit(InputAsked(unlock));
        await settle();
        backend.answerResult = const Err(IrisFailure(FailureKind.offline));
        await controller.answerInput(unlock, 'hunter2');
        expect(controller.value.inputs, hasLength(1));
        expect(controller.value.items.whereType<PromptRecord>(), isEmpty);
      },
    );

    test(
      'a login is answered with both values, recorded, and kept nowhere',
      () async {
        final controller = opened();
        await controller.open();
        backend.emit(LoginAsked(login));
        await settle();
        await controller.answerLogin(
          login,
          identifier: 'jamie@hermes.dev',
          password: 'hunter2',
        );
        expect(backend.logins, [('srq-2', 'jamie@hermes.dev', 'hunter2')]);
        expect(controller.value.logins, isEmpty);
        expect(
          controller.value.items.whereType<PromptRecord>().single.title,
          'Saved GitHub login',
        );
        final text = everything(controller);
        expect(text, isNot(contains('hunter2')));
        expect(text, isNot(contains('jamie@hermes.dev')));
      },
    );

    test('skipping a login sends an empty answer', () async {
      final controller = opened();
      await controller.open();
      backend.emit(LoginAsked(login));
      await settle();
      await controller.skipLogin(login);
      expect(backend.logins, [('srq-2', '', '')]);
      expect(
        controller.value.items.whereType<PromptRecord>().single.outcome,
        PromptOutcome.skipped,
      );
    });

    test('a withdrawn prompt leaves an expired line', () async {
      final controller = opened();
      await controller.open();
      backend.emit(InputAsked(unlock));
      await settle();
      backend.emit(const RequestWithdrawn('run-1', 'srq-1'));
      await settle();
      expect(controller.value.inputs, isEmpty);
      final record = controller.value.items.whereType<PromptRecord>().single;
      expect(record.outcome, PromptOutcome.expired);
      expect(record.detail, 'expired 14:02 · Hermes stopped waiting');
    });
  });

  group('connection card', () {
    ConnectionRequest card() => ConnectionRequest.parse(
      Json.of({
        'op_id': 'op1',
        'timeout_seconds': 300,
        'targets': [
          {
            'name': 'Linear',
            'kind': 'connector',
            'action': 'authorize',
            'state': 'pending',
            'connect_url': 'https://linear.app/oauth',
          },
          {
            'name': 'GitHub',
            'kind': 'mcp',
            'action': 'connect',
            'state': 'pending',
          },
        ],
      }),
      sessionId: 'run-1',
    )!;

    Future<ChatController> withCard() async {
      final controller = controllerFor()
        ..clock = () => DateTime(2026, 10, 16, 14, 7);
      await controller.open();
      backend.emit(ConnectionAsked(card()));
      await settle();
      return controller;
    }

    test(
      'approving one target sends just that target and keeps the card',
      () async {
        final controller = await withCard();
        await controller.answerConnectionTarget(
          card(),
          const TargetAnswer.approved('GitHub', env: {'GITHUB_TOKEN': 'ghp_x'}),
        );
        final (op, answers, settles) = backend.connectionAnswers.single;
        expect(op, 'op1');
        expect(answers.single.name, 'GitHub');
        expect(settles, isFalse);
        expect(controller.value.connections, hasLength(1));
      },
    );

    test('credentials are never kept in state', () async {
      final controller = await withCard();
      await controller.answerConnectionTarget(
        card(),
        const TargetAnswer.approved(
          'GitHub',
          env: {'GITHUB_TOKEN': 'ghp_secret'},
        ),
      );
      expect(
        '${controller.value.connections}${controller.value.items}',
        isNot(contains('ghp_secret')),
      );
    });

    test('a failed answer says so and the card stays', () async {
      final toasts = <String>[];
      final controller = await withCard()
        ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
      backend.connectionResult = const Err(IrisFailure(FailureKind.offline));
      await controller.answerConnectionTarget(
        card(),
        const TargetAnswer.skipped('Linear'),
      );
      expect(toasts.single, startsWith('Could not send'));
      expect(controller.value.connections, hasLength(1));
    });

    test('Continue skips everything still open and closes the card', () async {
      final controller = await withCard();
      await controller.settleConnection(card());
      final (_, answers, settles) = backend.connectionAnswers.single;
      expect(settles, isTrue);
      expect(answers.map((a) => (a.name, a.approved)), [
        ('Linear', false),
        ('GitHub', false),
      ]);
      expect(controller.value.connections, isEmpty);
    });

    test('Continue leaves resolved targets alone', () async {
      final controller = await withCard();
      backend.emit(
        ConnectionChanged(
          'run-1',
          opId: 'op1',
          targets: [card().targets.first.withState(TargetState.connected)],
          settled: false,
        ),
      );
      await settle();
      await controller.settleConnection(controller.value.connections.single);
      expect(backend.connectionAnswers.single.$2.map((a) => a.name), [
        'GitHub',
      ]);
    });

    test('a failed Continue says so and the card stays', () async {
      final toasts = <String>[];
      final controller = await withCard()
        ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
      backend.connectionResult = const Err(IrisFailure(FailureKind.offline));
      await controller.settleConnection(card());
      expect(toasts.single, startsWith('Could not send'));
      expect(controller.value.connections, hasLength(1));
    });

    test('an expired card becomes an expired line', () async {
      final controller = await withCard();
      controller.expireConnection('op1');
      expect(controller.value.connections, isEmpty);
      final record = controller.value.items.whereType<PromptRecord>().single;
      expect(record.outcome, PromptOutcome.expired);
      expect(record.detail, 'expired 14:07 · Hermes stopped waiting');
    });

    test('expiring a card that is not open does nothing', () async {
      final controller = await withCard();
      controller.expireConnection('nope');
      expect(controller.value.connections, hasLength(1));
      expect(controller.value.items.whereType<PromptRecord>(), isEmpty);
    });
  });
}

/// Whether [secret] appears anywhere the state could show or keep it.
bool _mentions(ChatState state, String secret) => state.items.any(
  (item) => switch (item) {
    UserTurn(:final text) => text,
    AssistantTurn(:final text) => text,
    Notice(:final text) => text,
    ToolCall(:final output) => output ?? '',
    PromptRecord(:final title, :final detail) => '$title $detail',
  }.contains(secret),
);
