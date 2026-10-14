/// The pieces of a chat screen, one at a time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/composer.dart';
import 'package:iris/features/chat/context_sheet.dart';
import 'package:iris/features/chat/decision_cards.dart';
import 'package:iris/features/chat/transcript_view.dart';

import '../support/harness.dart';

/// The card's input, not the selectable command above it.
final _field = find.descendant(
  of: find.byType(IrisField),
  matching: find.byType(EditableText),
);

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

  group('composer, phase 4', () {
    Widget composer({
      required TextEditingController text,
      bool running = false,
      ContextUsage? usage,
      VoidCallback? onSend,
      VoidCallback? onContext,
    }) => themed(
      Align(
        alignment: Alignment.bottomCenter,
        child: Composer(
          controller: text,
          running: running,
          onSend: onSend ?? () {},
          onStop: () {},
          contextUsage: usage,
          onContext: onContext,
        ),
      ),
    );

    testWidgets('during a run, text offers a steer beside stop', (tester) async {
      final text = TextEditingController();
      var sent = 0;
      await tester.pumpWidget(composer(text: text, running: true, onSend: () => sent++));
      expect(find.bySemanticsLabel('Steer'), findsNothing);
      expect(find.bySemanticsLabel('Stop'), findsOneWidget);

      text.text = 'use staging';
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Steer'), findsOneWidget);
      expect(find.bySemanticsLabel('Stop'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Steer'));
      expect(sent, 1);
    });

    testWidgets('a slash command offers no steer', (tester) async {
      final text = TextEditingController(text: '/model');
      await tester.pumpWidget(composer(text: text, running: true));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Steer'), findsNothing);
    });

    testWidgets('the context ring shows once known and opens its sheet', (tester) async {
      final text = TextEditingController();
      var opened = 0;
      await tester.pumpWidget(composer(text: text));
      expect(find.byType(IrisRing), findsNothing);
      await tester.pumpWidget(
        composer(
          text: text,
          usage: const ContextUsage(percent: 18, used: 48210, max: 272000),
          onContext: () => opened++,
        ),
      );
      expect(find.bySemanticsLabel('Context window, 18 percent'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Context window, 18 percent'));
      expect(opened, 1);
    });

    testWidgets('the context sheet reads the numbers out', (tester) async {
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => Center(
              child: IrisButton(
                label: 'Open',
                onPressed: () => showContextSheet(
                  context,
                  const ContextUsage(percent: 18, used: 48210, max: 272000),
                  model: 'gpt-6.1-sol',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('18%'), findsOneWidget);
      expect(find.text('48,210 of 272,000 tokens'), findsOneWidget);
      expect(find.text('gpt-6.1-sol'), findsOneWidget);
    });

    test('numbers group by thousands', () {
      expect(groupedNumber(0), '0');
      expect(groupedNumber(999), '999');
      expect(groupedNumber(48210), '48,210');
      expect(groupedNumber(1272000), '1,272,000');
    });
  });

  group('input card', () {
    const sudo = InputRequest(
      requestId: 'srq-1',
      sessionId: 'run-1',
      kind: InputKind.sudo,
      command: 'apt install jq',
    );

    testWidgets('submits the masked value and clears the field', (tester) async {
      String? sent;
      await tester.pumpWidget(
        themed(
          Center(
            child: InputCard(
              request: sudo,
              onAnswer: (value) async => sent = value,
            ),
          ),
        ),
      );
      expect(find.text('Hermes needs your sudo password'), findsOneWidget);
      expect(find.text('apt install jq'), findsOneWidget);
      await tester.enterText(_field, 'hunter2');
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(sent, 'hunter2');
      expect(
        tester.widget<EditableText>(_field).controller.text,
        isEmpty,
      );
    });

    testWidgets('cancel sends an empty value', (tester) async {
      String? sent;
      await tester.pumpWidget(
        themed(Center(child: InputCard(request: sudo, onAnswer: (v) async => sent = v))),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(sent, '');
    });

    testWidgets('the eye shows and hides what was typed', (tester) async {
      await tester.pumpWidget(
        themed(Center(child: InputCard(request: sudo, onAnswer: (_) async {}))),
      );
      EditableText field() => tester.widget<EditableText>(_field);
      expect(field().obscureText, isTrue);
      await tester.tap(find.bySemanticsLabel('Show password'));
      await tester.pump();
      expect(field().obscureText, isFalse);
      await tester.tap(find.bySemanticsLabel('Hide password'));
      await tester.pump();
      expect(field().obscureText, isTrue);
    });
  });

  testWidgets('a retryable failure offers Retry; retrying shows it working', (tester) async {
    var retried = 0;
    const failed = Notice(id: 'n', text: 'Gateway timed out', isError: true, retryable: true);
    await tester.pumpWidget(
      themed(Center(child: TranscriptEntry(failed, onRetry: () => retried++))),
    );
    await tester.tap(find.text('Retry'));
    expect(retried, 1);

    await tester.pumpWidget(
      themed(Center(child: TranscriptEntry(failed, onRetry: () {}, retrying: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.byKey(const ValueKey('retrying')), findsOneWidget);
    expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
  });

  testWidgets('a steered turn says so', (tester) async {
    await tester.pumpWidget(
      themed(const Center(child: TranscriptEntry(UserTurn(id: 'u', text: 'go on', steered: true)))),
    );
    expect(find.text('Steered'), findsOneWidget);
  });
}
