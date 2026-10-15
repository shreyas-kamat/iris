/// A whole conversation screen against a scripted backend.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/decision_cards.dart';
import 'package:iris/features/chat/voice_recorder.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 50));

  testWidgets('opens a stored conversation and shows its transcript', (
    tester,
  ) async {
    backend.historyResult = const Ok([
      UserTurn(id: '1', text: 'hi'),
      AssistantTurn(id: '2', text: 'hello'),
    ]);
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          title: 'Greetings',
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    expect(find.text('Greetings'), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('a streamed reply appears as it arrives', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    backend
      ..emit(const MessageStarted('run-1'))
      ..emit(const TextDelta('run-1', 'Hel'))
      ..emit(const TextDelta('run-1', 'lo'));
    await settle(tester);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.bySemanticsLabel('Stop'), findsOneWidget);
    backend.emit(const MessageCompleted('run-1'));
    await settle(tester);
    // An empty composer offers the mic in Send's place.
    expect(find.bySemanticsLabel('Dictate'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sending puts the message in the transcript and submits it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    await tester.enterText(find.byType(EditableText), 'Run the tests');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await settle(tester);
    expect(backend.submitted.single, ('run-1', 'Run the tests'));
    expect(find.text('Run the tests'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an approval shows above the composer and is answered', (
    tester,
  ) async {
    backend.resumeResult = Ok(
      ResumedConversation(
        runtimeId: 'run-1',
        running: true,
        pending: [
          ApprovalAsked(
            const ApprovalRequest(
              sessionId: 'run-1',
              command: 'git push',
              description: 'Push to origin',
              choices: ['once', 'deny'],
              serverRequestId: 'srq-1',
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    expect(find.text('git push'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await settle(tester);
    expect(backend.approvals, ['once']);
    expect(find.text('git push'), findsNothing);
  });

  testWidgets('a conversation that cannot be read offers a retry', (
    tester,
  ) async {
    backend.historyResult = const Err(
      IrisFailure(FailureKind.notFound, message: 'Session not found'),
    );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    expect(find.text('Could not open this conversation'), findsOneWidget);
    expect(find.text('Session not found'), findsOneWidget);
    backend.historyResult = const Ok([UserTurn(id: '1', text: 'back')]);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    await settle(tester);
    expect(find.text('back'), findsOneWidget);
  });

  testWidgets('a new chat starts empty and is created on send', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(themed(ChatScreen(backend: backend)));
    await settle(tester);
    expect(find.text('What should we\nwork on?'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'hi');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await settle(tester);
    expect(backend.calls, contains('create'));
    expect(backend.submitted.single, ('run-new', 'hi'));
    semantics.dispose();
  });

  testWidgets('replies sit at the left edge and the person at the right', (
    tester,
  ) async {
    // On the emulator, short replies were centred: each entry shrank to its
    // own width inside the centred readable column.
    // A phone-sized surface; the default test surface is 800 wide.
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    backend.historyResult = const Ok([
      UserTurn(id: '1', text: 'hi'),
      AssistantTurn(id: '2', text: 'ok'),
    ]);
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    await settle(tester);
    expect(tester.getTopLeft(find.text('ok')).dx, lessThan(60));
    expect(tester.getTopRight(find.text('hi')).dx, greaterThan(300));
  });

  testWidgets('earlier messages load above when asked', (tester) async {
    backend
      ..historyResult = const Ok([UserTurn(id: '65', text: 'newest')])
      ..historyEarlier = const HistoryCursor(offset: 64, fromNewest: false)
      ..earlierResult = const Ok(
        HistoryPage(
          items: [UserTurn(id: '1', text: 'oldest')],
        ),
      );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    await settle(tester);
    await tester.tap(find.text('Show earlier messages'));
    await settle(tester);
    await settle(tester);
    expect(backend.calls, contains('earlier stored-1 64'));
    expect(find.text('oldest'), findsOneWidget);
    expect(find.text('Show earlier messages'), findsNothing);
  });

  group('the model', () {
    void scriptModels() {
      backend
        ..resumeResult = const Ok(
          ResumedConversation(
            runtimeId: 'run-1',
            model: 'gpt-6.1-sol',
            provider: 'openai-codex',
          ),
        )
        ..modelOptionsResult = const Ok(
          ModelOptions(
            model: 'gpt-6.1-sol',
            providers: [
              ModelProvider(
                slug: 'openai-codex',
                name: 'OpenAI Codex',
                models: ['gpt-6.1-sol', 'gpt-6-luna'],
              ),
            ],
          ),
        );
    }

    Future<void> pickLuna(WidgetTester tester) async {
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Model: gpt-6.1-sol'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      // IrisLabel upper-cases its text.
      expect(find.text('OPENAI CODEX'), findsOneWidget);
      await tester.tap(find.text('gpt-6-luna'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    testWidgets('the header shows it, and the picker switches it', (
      tester,
    ) async {
      scriptModels();
      backend.switchResult = const Ok(ModelSwitch(model: 'gpt-6-luna'));
      await pickLuna(tester);
      expect(backend.switches, ['gpt-6-luna@openai-codex']);
      expect(find.bySemanticsLabel('Model: gpt-6-luna'), findsOneWidget);
      expect(find.text('Now using gpt-6-luna.'), findsOneWidget);
    });

    testWidgets('a switch Hermes wants confirmed asks first', (tester) async {
      scriptModels();
      backend.switchResult = const Ok(
        ModelSwitch(
          model: 'gpt-6-luna',
          confirmRequired: true,
          confirmMessage: 'This model is expensive.',
        ),
      );
      await pickLuna(tester);
      expect(find.text('This model is expensive.'), findsOneWidget);
      expect(backend.switches, ['gpt-6-luna@openai-codex']);
      expect(find.bySemanticsLabel('Model: gpt-6.1-sol'), findsOneWidget);
      backend.switchResult = const Ok(ModelSwitch(model: 'gpt-6-luna'));
      await tester.tap(find.text('Switch'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(backend.switches, [
        'gpt-6-luna@openai-codex',
        'gpt-6-luna@openai-codex confirmed',
      ]);
      expect(find.bySemanticsLabel('Model: gpt-6-luna'), findsOneWidget);
    });
  });

  testWidgets('a slash command is suggested, runs, and its output shows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    backend
      ..commandsResult = const Ok([
        SlashCommand(name: '/usage', description: 'Token usage'),
      ])
      ..slashResult = const Ok(
        SlashOutcome(kind: SlashKind.exec, text: 'Tokens: 12k'),
      );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    await tester.enterText(find.byType(EditableText), '/us');
    await settle(tester);
    expect(backend.calls, contains('commands'));
    expect(find.text('Token usage'), findsOneWidget);
    await tester.tap(find.text('/usage'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await settle(tester);
    expect(backend.slashes, ['/usage']);
    expect(find.text('Tokens: 12k'), findsOneWidget);
    expect(find.bySemanticsLabel('Dictate'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a prefill puts its text in the composer', (tester) async {
    final semantics = tester.ensureSemantics();
    backend.slashResult = const Ok(
      SlashOutcome(kind: SlashKind.prefill, text: 'Write a plan for '),
    );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    await tester.enterText(find.byType(EditableText), '/plan');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await settle(tester);
    expect(find.text('Write a plan for '), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a sudo prompt shows its card and the answer reaches the backend', (tester) async {
    await tester.pumpWidget(themed(ChatScreen(backend: backend, conversationId: 'stored-1')));
    await settle(tester);
    await settle(tester);
    backend.emit(
      InputAsked(
        const InputRequest(requestId: 'srq-1', sessionId: 'run-1', kind: InputKind.sudo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hermes needs your sudo password'), findsOneWidget);
    await tester.enterText(
      find.descendant(of: find.byType(InputCard), matching: find.byType(EditableText)),
      'pw',
    );
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(backend.inputAnswers, [('srq-1', 'pw')]);
    expect(find.byType(InputCard), findsNothing);
  });

  testWidgets('sending in an archived chat asks to unarchive first', (tester) async {
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1', archived: true)),
    );
    await settle(tester);
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'hello');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Unarchive this chat?'), findsOneWidget);
    await tester.tap(find.text('Unarchive and send'));
    await tester.pumpAndSettle();
    expect(backend.archives, [('stored-1', false)]);
    expect(backend.submitted.single.$2, 'hello');
  });

  testWidgets('declining to unarchive keeps the text and sends nothing', (tester) async {
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1', archived: true)),
    );
    await settle(tester);
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'hello');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(backend.submitted, isEmpty);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('picked files show as chips and go with the message', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          pickFiles: () async => [
            Attachment(name: 'n.txt', bytes: Uint8List(1)),
          ],
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Attach'));
    await tester.pump();
    expect(find.text('n.txt'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'read it');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    await settle(tester);
    expect(backend.attached.single.$2, 'n.txt');
    // The draft chip clears once sent; the bubble keeps its own.
    expect(find.bySemanticsLabel('Remove n.txt'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a file over 20 MB is refused before upload', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          pickFiles: () async => [
            Attachment(
              name: 'big.bin',
              bytes: Uint8List(Attachment.maxBytes + 1),
            ),
          ],
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Attach'));
    await tester.pump();
    await tester.pump();
    expect(find.text('big.bin'), findsNothing);
    expect(find.textContaining('20 MB'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('dictation puts the words in the composer', (tester) async {
    final semantics = tester.ensureSemantics();
    final recorder = FakeRecorder();
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, recorder: recorder)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Dictate'));
    await tester.pump();
    expect(recorder.recording, isTrue);
    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await tester.pumpAndSettle();
    expect(find.text('dictated words'), findsOneWidget);
    // Nothing sends until the person does.
    expect(backend.submitted, isEmpty);
    semantics.dispose();
  });

  testWidgets('a refused mic says how to fix it', (tester) async {
    final semantics = tester.ensureSemantics();
    final recorder = FakeRecorder()..allowed = false;
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, recorder: recorder)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Dictate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('microphone'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Hermes without speech-to-text leaves the draft alone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    backend.transcribeResult = const Err(
      IrisFailure(
        FailureKind.server,
        message: 'No speech-to-text provider is configured',
      ),
    );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, recorder: FakeRecorder())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Dictate'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await tester.pumpAndSettle();
    expect(find.textContaining('speech-to-text'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    semantics.dispose();
  });
}

final class FakeRecorder implements VoiceRecorder {
  bool allowed = true;
  bool recording = false;

  @override
  Future<bool> start() async => recording = allowed;

  @override
  Future<Uint8List?> stop() async {
    recording = false;
    return Uint8List.fromList([1]);
  }

  @override
  Future<void> cancel() async => recording = false;
}
