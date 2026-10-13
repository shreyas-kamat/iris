/// The pieces of a chat screen, one at a time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/composer.dart';
import 'package:iris/features/chat/decision_cards.dart';
import 'package:iris/features/chat/transcript_view.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a tool card shows its name, state and output', (tester) async {
    await tester.pumpWidget(
      themed(
        const ToolCard(
          ToolCall(
            id: 't',
            name: 'terminal',
            arguments: '{"command":"ls"}',
            output: 'a.txt',
          ),
        ),
      ),
    );
    expect(find.text('terminal'), findsOneWidget);
    // The status is written in lower case, under the tool's name.
    expect(find.text('done'), findsOneWidget);
    // Output is held back until the card is opened, so a long list of tool
    // calls stays scannable.
    expect(find.text('a.txt'), findsNothing);
    await tester.tap(find.text('terminal'));
    await tester.pump();
    expect(find.text('a.txt'), findsOneWidget);
  });

  testWidgets('a live reply with no text yet says it is thinking', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const TranscriptEntry(
          AssistantTurn(id: 'a', text: '', streaming: true),
          live: AgentState.thinking,
        ),
      ),
    );
    // The header meta says what the turn is doing, in the design's words.
    expect(find.text('thinking'), findsOneWidget);
  });

  testWidgets('user and assistant text both render', (tester) async {
    await tester.pumpWidget(
      themed(
        const Column(
          children: [
            TranscriptEntry(UserTurn(id: 'u', text: 'Run the tests')),
            TranscriptEntry(AssistantTurn(id: 'a', text: 'All green.')),
            TranscriptEntry(Notice(id: 'n', text: 'Stopped.')),
          ],
        ),
      ),
    );
    expect(find.text('Run the tests'), findsOneWidget);
    expect(find.text('All green.'), findsOneWidget);
    expect(find.text('Stopped.'), findsOneWidget);
  });

  testWidgets('an approval card offers each choice and reports the pick', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      themed(
        ApprovalCard(
          request: const ApprovalRequest(
            sessionId: 'r',
            command: 'rm -rf build',
            description: 'Delete the build folder',
            choices: ['once', 'session', 'deny'],
          ),
          onChoose: (choice) => picked = choice,
        ),
      ),
    );
    expect(find.text('rm -rf build'), findsOneWidget);
    expect(find.text('Delete the build folder'), findsOneWidget);
    expect(find.text('Allow for this chat'), findsOneWidget);
    await tester.tap(find.text('Deny'));
    expect(picked, 'deny');
  });

  testWidgets('a clarify card answers with a choice or typed text', (
    tester,
  ) async {
    final answers = <String>[];
    await tester.pumpWidget(
      themed(
        ClarifyCard(
          request: const ClarifyRequest(
            requestId: 'srq-1',
            sessionId: 'r',
            questions: [
              ClarifyQuestion(
                id: 'q0',
                text: 'Which branch?',
                choices: [ClarifyChoice(label: 'Main', value: 'main')],
                synthetic: true,
              ),
            ],
          ),
          onAnswer: (question, answer) => answers.add('${question.id}=$answer'),
        ),
      ),
    );
    expect(find.text('Which branch?'), findsOneWidget);
    await tester.tap(find.text('Main'));
    await tester.enterText(find.byType(EditableText), 'dev');
    await tester.tap(find.text('Answer'));
    expect(answers, ['q0=main', 'q0=dev']);
  });

  testWidgets('the composer sends only with text, and stops while running', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final text = TextEditingController();
    addTearDown(text.dispose);
    var sent = 0;
    var stopped = 0;
    Widget composer({required bool running}) => themed(
      Composer(
        controller: text,
        running: running,
        onSend: () => sent++,
        onStop: () => stopped++,
      ),
    );
    await tester.pumpWidget(composer(running: false));
    await tester.tap(find.bySemanticsLabel('Send'));
    expect(sent, 0);
    await tester.enterText(find.byType(EditableText), 'hi');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    expect(sent, 1);
    await tester.pumpWidget(composer(running: true));
    await tester.tap(find.bySemanticsLabel('Stop'));
    expect(stopped, 1);
    semantics.dispose();
  });

  testWidgets(
    'typing a slash suggests commands, and a pick fills the composer',
    (tester) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      await tester.pumpWidget(
        themed(
          Composer(
            controller: text,
            running: false,
            onSend: () {},
            onStop: () {},
            commands: const [
              SlashCommand(name: '/model', description: 'Switch model'),
              SlashCommand(name: '/new', description: 'Start a new session'),
            ],
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), '/mo');
      await tester.pump();
      expect(find.text('/model'), findsOneWidget);
      expect(find.text('/new'), findsNothing);
      await tester.tap(find.text('/model'));
      await tester.pump();
      expect(text.text, '/model ');
      expect(find.text('Switch model'), findsNothing);
    },
  );
}
