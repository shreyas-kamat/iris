/// A whole conversation screen against a scripted backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/connection_models.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/composer.dart';
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

  testWidgets(
    'in queue mode, sending mid-reply fills the tray, which can be emptied',
    (tester) async {
      final semantics = tester.ensureSemantics();
      backend.busyModeResult = const Ok(BusyMode.queue);
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      await settle(tester);
      backend.emit(const MessageStarted('run-1'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'Also check node-4');
      await tester.pump();
      expect(find.text('QUEUE'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('^Queue')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(backend.submits, isEmpty);
      expect(find.text('Also check node-4'), findsOneWidget);
      expect(
        find.text('Queued messages are held on this phone'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Remove message 1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Queued messages are held on this phone'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      semantics.dispose();
    },
  );

  // With the keyboard up (typing a credential) there is far less room.
  for (final keyboard in [0.0, 260.0]) {
    testWidgets(
      'a connection card with eight rows scrolls and leaves the composer on screen'
      '${keyboard > 0 ? ', keyboard up' : ''}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // The harness pins a larger phone; this one is the smallest supported.
        await tester.pumpWidget(
          themed(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 568),
                viewInsets: EdgeInsets.only(bottom: keyboard),
                disableAnimations: true,
              ),
              child: ChatScreen(backend: backend, conversationId: 'stored-1'),
            ),
          ),
        );
        await settle(tester);
        backend.emit(
          ConnectionAsked(
            ConnectionRequest.parse(
              Json.of({
                'op_id': 'op1',
                'timeout_seconds': 300,
                'targets': [
                  for (var i = 0; i < 8; i++)
                    {
                      'name': 'server-$i',
                      'kind': 'mcp',
                      'action': 'enable',
                      'state': 'pending',
                    },
                ],
              }),
              sessionId: 'run-1',
            )!,
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.text('CONNECT · 8 ITEMS'), findsOneWidget);
        final composer = tester.getRect(find.byType(Composer));
        expect(composer.bottom, lessThanOrEqualTo(568));
        expect(composer.top, lessThan(568));
        // The card goes before the test ends, so its countdown stops.
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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

  testWidgets(
    'a sudo prompt shows its card and the answer reaches the backend',
    (tester) async {
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      await settle(tester);
      backend.emit(
        InputAsked(
          const InputRequest(
            requestId: 'srq-1',
            sessionId: 'run-1',
            kind: InputKind.sudo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run this as root?'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(InputCard),
          matching: find.byType(EditableText),
        ),
        'pw',
      );
      await tester.pump();
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(backend.inputAnswers, [('srq-1', 'pw')]);
      expect(find.byType(InputCard), findsNothing);
    },
  );

  testWidgets('sending in an archived chat asks to unarchive first', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          archived: true,
        ),
      ),
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

  testWidgets('declining to unarchive keeps the text and sends nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          archived: true,
        ),
      ),
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

  Future<void> pumpChat(WidgetTester tester, {BranchRecord? branch}) async {
    backend.historyResult = const Ok([
      UserTurn(id: '1', text: 'Why?'),
      AssistantTurn(id: '2', text: 'Because.'),
      UserTurn(id: '3', text: 'Draft the fix.'),
      AssistantTurn(id: '4', text: 'Done.'),
    ]);
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          title: 'Greetings',
          branch: branch,
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
  }

  testWidgets(
    'long-press on your latest message offers Copy and Undo; older ones Copy only',
    (tester) async {
      await pumpChat(tester);
      await tester.longPress(find.text('Draft the fix.'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Why?'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets(
    'Undo from the menu removes the exchange and refills the composer',
    (tester) async {
      await pumpChat(tester);
      await tester.longPress(find.text('Draft the fix.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(backend.undos, ['run-1']);
      expect(find.text('Done.'), findsNothing);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, 'Draft the fix.');
    },
  );

  testWidgets('Copy puts the whole message on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpChat(tester);
    await tester.longPress(find.text('Done.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Done.');
  });

  testWidgets(
    'long-press on a finished reply offers Branch from here; a streaming one does not',
    (tester) async {
      await pumpChat(tester);
      await tester.longPress(find.text('Done.'));
      await tester.pumpAndSettle();
      expect(find.text('Branch from here'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      backend
        ..emit(const MessageStarted('run-1'))
        ..emit(const TextDelta('run-1', 'typing'));
      await settle(tester);
      await tester.longPress(find.text('typing'));
      await tester.pumpAndSettle();
      expect(find.text('Branch from here'), findsNothing);
    },
  );

  testWidgets(
    'branching from the newest reply copies the whole chat and opens the child',
    (tester) async {
      await pumpChat(tester);
      await tester.longPress(find.text('Done.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Branch from here'));
      await tester.pumpAndSettle();
      expect(backend.branches, ['stored-1']);
      expect(find.textContaining('Branched from'), findsOneWidget);
    },
  );

  testWidgets('branching from an older reply seeds the prefix', (tester) async {
    await pumpChat(tester);
    await tester.longPress(find.text('Because.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Branch from here'));
    await tester.pumpAndSettle();
    expect(
      [for (final m in backend.branchPrefixes.first) m.content],
      ['Why?', 'Because.'],
    );
  });

  testWidgets(
    'a chat opened with a record shows the header line and the divider',
    (tester) async {
      await pumpChat(
        tester,
        branch: BranchRecord(
          parentId: 'p',
          parentTitle: 'Parent chat',
          count: 2,
          at: DateTime(2026, 10, 16, 14, 2).millisecondsSinceEpoch,
        ),
      );
      expect(
        find.textContaining('Parent chat', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('BRANCHED HERE · 14:02'), findsOneWidget);
    },
  );

  testWidgets(
    'at 96% context the strip offers Branch with a summary; at 94% it is absent',
    (tester) async {
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
      backend.emit(const ContextChanged('run-1', ContextUsage(percent: 94)));
      await settle(tester);
      expect(
        find.text('Context is nearly full. Older turns will be summarised.'),
        findsNothing,
      );
      backend.emit(const ContextChanged('run-1', ContextUsage(percent: 96)));
      await settle(tester);
      expect(
        find.text('Context is nearly full. Older turns will be summarised.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Branch'));
      await tester.pumpAndSettle();
      expect(backend.branches, ['stored-1']);
      expect(backend.compressions, ['run-branch']);
    },
  );
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
