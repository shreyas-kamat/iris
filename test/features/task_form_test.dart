import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/tasks/task_form_screen.dart';

import '../support/fake_automation.dart';
import '../support/harness.dart';

void main() {
  late FakeKanbanRepository kanban;
  setUp(() => kanban = FakeKanbanRepository());

  Widget form({String initialColumn = 'triage'}) => ProviderScope(
    overrides: [
      kanbanRepositoryProvider.overrideWith((ref) async => kanban),
      profilesProvider.overrideWith(
        (ref) async => const [
          AgentProfile(name: 'default', isDefault: true),
          AgentProfile(name: 'homelab'),
        ],
      ),
    ],
    child: themed(TaskFormScreen(initialColumn: initialColumn)),
  );

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is IrisField && w.label == label,
  );

  bool createEnabled(WidgetTester tester) =>
      tester
          .widget<IrisButton>(find.widgetWithText(IrisButton, 'Create'))
          .onPressed !=
      null;

  testWidgets('Create waits for a title', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(createEnabled(tester), isFalse);
    await tester.enterText(field('Title'), '  ');
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    await tester.enterText(field('Title'), 'Rotate the signing secret');
    await tester.pump();
    expect(createEnabled(tester), isTrue);
  });

  testWidgets('starts in the column it was opened from', (tester) async {
    await tester.pumpWidget(form(initialColumn: 'todo'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Title'), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Create'));
    await tester.pumpAndSettle();
    expect(kanban.drafts.single.status, 'todo');
  });

  testWidgets('a column the person cannot create in falls back to Triage', (
    tester,
  ) async {
    await tester.pumpWidget(form(initialColumn: 'review'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Title'), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Create'));
    await tester.pumpAndSettle();
    expect(kanban.drafts.single.status, 'triage');
  });

  testWidgets('sends the column, assignee, priority and body', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.enterText(field('Title'), 'Rotate the secret');
    await tester.enterText(field('Body · optional · Markdown'), 'and verify');
    await tester.tap(find.text('To do'));
    await tester.pump();
    await tester.tap(find.byTooltip('More priority'));
    await tester.tap(find.byTooltip('More priority'));
    await tester.pump();
    await tester.tap(find.text('Assignee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(IrisButton, 'Create'));
    await tester.pumpAndSettle();
    final draft = kanban.drafts.single;
    expect(draft.title, 'Rotate the secret');
    expect(draft.body, 'and verify');
    expect(draft.status, 'todo');
    expect(draft.priority, 2);
    expect(draft.assignee, 'homelab');
  });

  testWidgets('priority is optional, and less than 1 clears it', (
    tester,
  ) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(find.text('Optional'), findsWidgets);
    await tester.tap(find.byTooltip('More priority'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Less priority'));
    await tester.pump();
    expect(find.text('1'), findsNothing);
  });

  testWidgets('a refused create keeps the form and says why', (tester) async {
    kanban.createResult = const Err(
      IrisFailure(FailureKind.rejected, message: 'title too long'),
    );
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.enterText(field('Title'), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('title too long'), findsOneWidget);
    expect(find.byType(TaskFormScreen), findsOneWidget);
  });

  testWidgets('priority buttons are at least 44 pt', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    for (final tip in ['More priority', 'Less priority']) {
      final size = tester.getSize(find.byTooltip(tip));
      expect(size.width, greaterThanOrEqualTo(44), reason: tip);
      expect(size.height, greaterThanOrEqualTo(44), reason: tip);
    }
  });
}
