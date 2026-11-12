/// A tap in a generated display becomes a message (plan 4.3): the person sees one sentence, Hermes also gets the hidden
/// `<iris-action>` block, and it all goes through the same busy-mode and queue rules as typing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_parser.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/chat/queue_tray.dart';

import '../support/fake_chat_backend.dart';

const _action = IrisActionEnvelope(
  surface: 'deploy',
  component: 'Submit',
  context: {'note': 'ship it'},
);

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<ChatController> open({BusyMode mode = BusyMode.interrupt}) async {
    backend.busyModeResult = Ok(mode);
    final controller = ChatController(backend, conversationId: 'stored-1');
    addTearDown(controller.dispose);
    await controller.open();
    await settle();
    return controller;
  }

  Future<ChatController> running(BusyMode mode) async {
    final controller = await open(mode: mode);
    backend.emit(const MessageStarted('run-1'));
    await settle();
    expect(controller.value.running, isTrue);
    return controller;
  }

  test(
    'the person sees the sentence; Hermes gets the sentence and the block',
    () async {
      final controller = await open();
      await controller.sendUiAction('Here is my note', _action);
      final turn = controller.value.items.whereType<UserTurn>().single;
      expect(turn.text, 'Here is my note');
      expect(backend.submits, hasLength(1));
      final sent = backend.submits.single.$2;
      expect(sent, startsWith('Here is my note\n<iris-action>'));
      final (text, envelope) = IrisActionEnvelope.split(sent);
      expect(text, 'Here is my note');
      expect(envelope!.surface, 'deploy');
      expect(envelope.component, 'Submit');
      expect(envelope.context, {'note': 'ship it'});
    },
  );

  test('a sentence that starts with a slash is words, not a command', () async {
    final controller = await open();
    await controller.sendUiAction('/undo', _action);
    expect(controller.value.items.whereType<UserTurn>().single.text, '/undo');
    expect(backend.submits, hasLength(1));
  });

  test('queue mode holds it in the tray, block included', () async {
    final controller = await running(BusyMode.queue);
    await controller.sendUiAction('Approve it', _action);
    expect(backend.submits, isEmpty);
    final queued = controller.value.queue.single;
    expect(queued.text, startsWith('Approve it\n<iris-action>'));
    expect(IrisActionEnvelope.strip(queued.text), 'Approve it');

    backend.emit(const MessageCompleted('run-1', content: 'done'));
    await settle();
    await settle();
    expect(backend.submits.single.$2, queued.text);
    expect(
      controller.value.items.whereType<UserTurn>().last.text,
      'Approve it',
    );
  });

  test('steer mode carries the block and shows only the sentence', () async {
    final controller = await running(BusyMode.steer);
    await controller.sendUiAction('Skip staging', _action);
    expect(backend.steers.single.$2, startsWith('Skip staging\n<iris-action>'));
    expect(
      controller.value.items.whereType<UserTurn>().last.text,
      'Skip staging',
    );
  });

  test('interrupt mode carries the block too', () async {
    final controller = await running(BusyMode.interrupt);
    await controller.sendUiAction('Stop that', _action);
    expect(backend.submits.single.$2, startsWith('Stop that\n<iris-action>'));
    expect(controller.value.items.whereType<UserTurn>().last.text, 'Stop that');
  });

  test(
    'a steer that bounces puts only the sentence back in the composer',
    () async {
      final controller = await running(BusyMode.steer);
      final returned = <String>[];
      controller.onSteerReturned = returned.add;
      backend.steerResult = const Ok(SteerOutcome.rejected);
      await controller.sendUiAction('Skip staging', _action);
      expect(returned.single, 'Skip staging');
    },
  );

  testWidgets('the queue tray shows the sentence, not the block', (
    tester,
  ) async {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    await tester.pumpWidget(
      IrisTheme(
        data: theme,
        child: MaterialApp(
          theme: theme.materialTheme,
          home: Material(
            child: QueueTray(
              items: [
                QueuedMessage(id: 'q1', text: _action.attachTo('Approve it')),
              ],
              paused: false,
              onRemove: (_) {},
              onSendNext: () {},
              onClear: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Approve it'), findsOneWidget);
    expect(find.textContaining('iris-action'), findsNothing);
  });
}
