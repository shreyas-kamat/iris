/// What sending does while a reply is running, for each busy mode, and how
/// the queue tray drains.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/rpc/rpc_frame.dart';
import 'package:iris/features/chat/chat_controller.dart';

import '../support/fake_chat_backend.dart';
import '../support/fakes.dart';

void main() {
  late FakeChatBackend backend;
  late List<String> toasts;

  setUp(() {
    backend = FakeChatBackend();
    toasts = [];
  });
  tearDown(() => backend.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// An open conversation with a reply running.
  Future<ChatController> running({BusyMode mode = BusyMode.interrupt}) async {
    backend.busyModeResult = Ok(mode);
    final controller = ChatController(backend, conversationId: 'stored-1')
      ..onToast = (message, {actionLabel, onAction}) => toasts.add(message);
    addTearDown(controller.dispose);
    await controller.open();
    await settle();
    backend.emit(const MessageStarted('run-1'));
    await settle();
    expect(controller.value.running, isTrue);
    return controller;
  }

  Future<void> finish() async {
    backend.emit(const MessageCompleted('run-1', content: 'done'));
    await settle();
  }

  group('by mode', () {
    test('the mode is read when the chat opens', () async {
      final controller = await running(mode: BusyMode.queue);
      expect(controller.value.busyMode, BusyMode.queue);
    });

    test('a server without the setting means interrupt', () async {
      backend.busyModeResult = Err(unknownMethod('config.set'));
      final controller = ChatController(backend, conversationId: 'stored-1');
      addTearDown(controller.dispose);
      await controller.open();
      await settle();
      expect(controller.value.busyMode, BusyMode.interrupt);
    });

    test('queue mode puts text in the tray and sends nothing', () async {
      final controller = await running(mode: BusyMode.queue);
      await controller.send('Also check node-4');
      expect(backend.submits, isEmpty);
      expect(backend.steers, isEmpty);
      expect(controller.value.queue.single.text, 'Also check node-4');
      expect(toasts, ['Queued for after this reply']);
    });

    test('steer mode steers through session.steer', () async {
      final controller = await running(mode: BusyMode.steer);
      await controller.send('Skip staging');
      expect(backend.steers, [('run-1', 'Skip staging')]);
      expect(backend.submits, isEmpty);
      final turn = controller.value.items.whereType<UserTurn>().last;
      expect(turn.steered && turn.steerPending, isTrue);
      expect(toasts, ['Steered']);
    });

    test('interrupt mode submits, and a redirect cuts the reply', () async {
      backend.submitOutcome = const Ok(SubmitOutcome.redirected);
      final controller = await running();
      backend.emit(const TextDelta('run-1', 'Three things broke'));
      await settle();
      await controller.send('Just restart the worker');
      expect(backend.submits, [('run-1', 'Just restart the worker', false)]);
      expect(
        controller.value.items.whereType<AssistantTurn>().single.redirected,
        isTrue,
      );
      expect(toasts, ['Redirected']);
    });

    test(
      'interrupt mode: a gateway that says queued is accepted, not an error',
      () async {
        backend.submitOutcome = const Ok(SubmitOutcome.queued);
        final controller = await running();
        await controller.send('later');
        expect(toasts, ['Queued for after this reply']);
        expect(
          controller.value.items.whereType<Notice>().where((n) => n.isError),
          isEmpty,
        );
      },
    );

    test('a 4009 on an interrupt falls back to the steer path', () async {
      backend.submitResult = const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'session busy',
          cause: RpcError(code: 4009, message: 'session busy'),
        ),
      );
      final controller = await running();
      await controller.send('nudge');
      expect(backend.steers, [('run-1', 'nudge')]);
    });

    test('other slash commands wait while running', () async {
      final controller = await running();
      await controller.send('/model');
      expect(backend.slashes, isEmpty);
      expect(backend.submits, isEmpty);
    });
  });

  group('slash forms', () {
    test('/queue always queues while running, whatever the mode', () async {
      final controller = await running(mode: BusyMode.steer);
      await controller.send('/queue after this');
      expect(controller.value.queue.single.text, 'after this');
      expect(backend.steers, isEmpty);
    });

    test('/steer always steers while running, whatever the mode', () async {
      final controller = await running(mode: BusyMode.queue);
      await controller.send('/steer faster');
      expect(backend.steers, [('run-1', 'faster')]);
      expect(controller.value.queue, isEmpty);
    });

    test(
      'idle, /queue and /steer are ordinary sends of their argument',
      () async {
        final controller = ChatController(backend, conversationId: 'stored-1');
        addTearDown(controller.dispose);
        await controller.open();
        await controller.send('/queue hello');
        expect(backend.submitted.last.$2, 'hello');
        expect(backend.slashes, isEmpty);
      },
    );
  });

  group('the tray', () {
    test('drains oldest first, one per finished turn', () async {
      final controller = await running(mode: BusyMode.queue);
      await controller.send('one');
      await controller.send('two');
      await finish();
      expect(backend.submits.map((s) => s.$2), ['one']);
      expect(controller.value.queue.map((q) => q.text), ['two']);
      final sent = controller.value.items.whereType<UserTurn>().last;
      expect(sent.text, 'one');
      expect(sent.fromQueue, isTrue);
      expect(
        controller.value.running,
        isTrue,
        reason: 'the next turn is under way',
      );

      await finish();
      expect(backend.submits.map((s) => s.$2), ['one', 'two']);
      expect(controller.value.queue, isEmpty);
    });

    test(
      'a failed turn pauses the tray; Send next resumes it; Clear empties it',
      () async {
        final controller = await running(mode: BusyMode.queue);
        await controller.send('one');
        await controller.send('two');
        backend.emit(const TurnFailed('run-1', 'boom'));
        await settle();
        expect(backend.submits, isEmpty);
        expect(controller.value.queuePaused, isTrue);

        await controller.sendNextQueued();
        expect(backend.submits.map((s) => s.$2), ['one']);
        expect(controller.value.queuePaused, isFalse);

        backend.emit(const TurnFailed('run-1', 'boom again'));
        await settle();
        expect(controller.value.queuePaused, isTrue);
        controller.clearQueue();
        expect(controller.value.queue, isEmpty);
        expect(controller.value.queuePaused, isFalse);
      },
    );

    test(
      'Stop pauses the tray rather than sending into a stopped turn',
      () async {
        final controller = await running(mode: BusyMode.queue);
        await controller.send('one');
        backend.emit(const TurnInterrupted('run-1'));
        await settle();
        expect(backend.submits, isEmpty);
        expect(controller.value.queuePaused, isTrue);
      },
    );

    test(
      'Send next while a new turn runs waits for it instead of sending into it',
      () async {
        final controller = await running(mode: BusyMode.queue);
        await controller.send('one');
        backend.emit(const TurnFailed('run-1', 'boom'));
        await settle();
        expect(controller.value.queuePaused, isTrue);
        // The person starts a fresh turn; the paused tray still shows.
        await controller.send('something else');
        backend.emit(const MessageStarted('run-1'));
        await settle();
        expect(controller.value.running, isTrue);

        await controller.sendNextQueued();
        expect(
          backend.submits.map((s) => s.$2),
          ['something else'],
          reason: 'a submit on a busy session would apply its busy policy',
        );
        expect(controller.value.queuePaused, isFalse);

        await finish();
        expect(backend.submits.map((s) => s.$2), ['something else', 'one']);
      },
    );

    test('a queued message that fails to send pauses the tray', () async {
      final controller = await running(mode: BusyMode.queue);
      await controller.send('one');
      await controller.send('two');
      backend.submitResult = Err(
        const IrisFailure(FailureKind.offline, message: 'gone'),
      );
      await finish();
      expect(backend.submits.map((s) => s.$2), ['one']);
      expect(controller.value.running, isFalse);
      expect(
        controller.value.queuePaused,
        isTrue,
        reason: 'otherwise "two" waits with no Send next and no turn to end',
      );
    });

    test('one message can be removed', () async {
      final controller = await running(mode: BusyMode.queue);
      await controller.send('one');
      await controller.send('two');
      controller.removeQueued(controller.value.queue.first.id);
      expect(controller.value.queue.map((q) => q.text), ['two']);
    });

    test(
      'a reconnect that finds the turn finished sends exactly one message',
      () async {
        final controller = await running(mode: BusyMode.queue);
        await controller.send('one');
        await controller.send('two');
        backend.resumeResult = const Ok(
          ResumedConversation(runtimeId: 'run-2'),
        );
        backend.reconnect();
        await settle();
        await settle();
        expect(backend.submits.map((s) => s.$2), ['one']);
        expect(controller.value.queue.map((q) => q.text), ['two']);
      },
    );

    test('a reconnect with the turn still running sends nothing', () async {
      final controller = await running(mode: BusyMode.queue);
      await controller.send('one');
      backend.resumeResult = const Ok(
        ResumedConversation(runtimeId: 'run-2', running: true),
      );
      backend.reconnect();
      await settle();
      await settle();
      expect(backend.submits, isEmpty);
    });
  });
}
