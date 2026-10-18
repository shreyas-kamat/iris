import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/automation/kanban_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/design/components/sheet.dart';
import 'package:iris/features/tasks/task_detail_screen.dart';
import 'package:iris/features/tasks/tasks_tab.dart';

import '../support/fake_automation.dart';
import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);
  late FakeKanbanRepository kanban;
  late FakeChatBackend chat;

  setUp(() {
    kanban = FakeKanbanRepository();
    chat = FakeChatBackend();
  });
  tearDown(() => chat.close());

  KanbanBoard board() => KanbanBoard(
    columns: [
      KanbanColumn(
        id: 'triage',
        tasks: [fakeTask('t_29', title: 'Flaky CI')],
      ),
      const KanbanColumn(id: 'todo', tasks: []),
      KanbanColumn(
        id: 'running',
        tasks: [
          fakeTask(
            't_30',
            title: 'Investigate heartbeat gaps',
            status: 'running',
            assignee: 'homelab',
            priority: 2,
            summary: 'Pulled the logs',
            startedAt: now.subtract(const Duration(minutes: 4)),
            progress: const KanbanProgress(2, 5),
            comments: 3,
            warnings: 1,
          ),
          fakeTask('t_28', title: 'Refactor billing', status: 'running'),
        ],
      ),
      KanbanColumn(
        id: 'blocked',
        tasks: [
          fakeTask(
            't_31',
            title: 'Backup failing',
            status: 'blocked',
            blockKind: 'needs_input',
          ),
          fakeTask(
            't_32',
            title: 'Rotate keys',
            status: 'blocked',
            blockKind: 'dependency',
          ),
        ],
      ),
      const KanbanColumn(id: 'review', tasks: []),
      const KanbanColumn(id: 'sprinting', tasks: []),
    ],
  );

  Widget tab({KanbanBoard? shown, Widget child = const TasksTab()}) =>
      ProviderScope(
        overrides: [
          kanbanRepositoryProvider.overrideWith((ref) async => kanban),
          kanbanBoardProvider.overrideWith(
            (ref) => Stream.value(shown ?? board()),
          ),
          activeChatProvider.overrideWith((ref) async => chat),
          clockProvider.overrideWithValue(() => now),
        ],
        child: themed(child),
      );

  testWidgets('chips show every column with its count, unknown ones too', (
    tester,
  ) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    for (final label in [
      'Triage',
      'To do',
      'Running',
      'Blocked',
      'Review',
      'Sprinting',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('opens on the first column that has cards', (tester) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    expect(find.text('Flaky CI'), findsOneWidget);
    expect(find.text('Investigate heartbeat gaps'), findsNothing);
  });

  testWidgets(
    'a running card shows the elapsed clock and subtasks, no percent',
    (tester) async {
      await tester.pumpWidget(tab());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Running').first);
      await tester.pumpAndSettle();
      expect(find.text('Investigate heartbeat gaps'), findsOneWidget);
      expect(find.text('4m'), findsOneWidget);
      expect(find.text('2 of 5 subtasks'), findsOneWidget);
      expect(find.text('Pulled the logs'), findsOneWidget);
      expect(find.text('p2'), findsOneWidget);
      expect(find.text('homelab'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('due'), findsNothing);
    },
  );

  testWidgets('a running card with no optional fields shows only its title', (
    tester,
  ) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running').first);
    await tester.pumpAndSettle();
    expect(find.text('Refactor billing'), findsOneWidget);
    expect(find.text('t_28'), findsOneWidget);
  });

  testWidgets('blocked cards show their kind verbatim', (tester) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocked').first);
    await tester.pumpAndSettle();
    expect(find.text('NEEDS INPUT'), findsOneWidget);
    expect(find.text('DEPENDENCY'), findsOneWidget);
  });

  testWidgets('a system-set empty column says Hermes moves tasks there', (
    tester,
  ) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review').first);
    await tester.pumpAndSettle();
    expect(find.text('Nothing in Review'), findsOneWidget);
    expect(
      find.text('Hermes moves tasks here. You can’t add one yourself.'),
      findsOneWidget,
    );
  });

  testWidgets('a person-movable empty column offers New task', (tester) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.text('To do').first);
    await tester.pumpAndSettle();
    expect(find.text('Nothing in To do'), findsOneWidget);
    expect(find.widgetWithText(IrisButton, 'New task'), findsWidgets);
  });

  testWidgets('an empty board says there are no tasks', (tester) async {
    await tester.pumpWidget(tab(shown: const KanbanBoard(columns: [])));
    await tester.pumpAndSettle();
    expect(find.text('No tasks yet'), findsOneWidget);
  });

  testWidgets('no overflow at 320 pt wide', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('detail', () {
    /// The detail list builds lazily; a tall surface keeps every row built.
    void tall(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(800, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    KanbanTaskDetail detail({String? sessionId}) => KanbanTaskDetail(
      task: fakeTask(
        't_26',
        title: 'Rotate gateway API keys',
        status: 'review',
        assignee: 'homelab',
        priority: 2,
        sessionId: sessionId,
      ),
      result: 'New keys are live.',
      lastFailure: 'webhook-relay: health check timed out',
      comments: const [KanbanComment(author: 'you', body: 'Hold off')],
      runs: const [KanbanRun(outcome: 'completed')],
      parents: const [KanbanLink(id: 't_20', title: 'Q4 hygiene')],
      children: const [
        KanbanLink(id: 't_34', title: 'Update api-edge', status: 'done'),
      ],
    );

    Widget screen({String? sessionId}) {
      kanban.detailResult = Ok(detail(sessionId: sessionId));
      return tab(
        child: TaskDetailScreen(
          taskId: 't_26',
          initial: fakeTask('t_26', title: 'Rotate gateway API keys'),
        ),
      );
    }

    testWidgets('shows the result, failure, links, comments and runs', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('Rotate gateway API keys'), findsWidgets);
      expect(find.text('New keys are live.'), findsOneWidget);
      expect(
        find.text('webhook-relay: health check timed out'),
        findsOneWidget,
      );
      expect(find.textContaining('Q4 hygiene'), findsOneWidget);
      expect(find.text('Update api-edge'), findsOneWidget);
      expect(find.text('Hold off'), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);
    });

    testWidgets('Open session shows only when the task links to one', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.widgetWithText(IrisButton, 'Open session'), findsNothing);
      // Tear the first screen down so its cached detail is not reused.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(sessionId: 'sess-1'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(IrisButton, 'Open session'), findsOneWidget);
    });

    testWidgets('Move sends the new column', (tester) async {
      tall(tester);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IrisButton, 'Move'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(IrisSheet),
          matching: find.text('Done'),
        ),
      );
      await tester.pumpAndSettle();
      expect(kanban.calls, contains('move t_26 done'));
    });

    testWidgets('a refused move says why and changes nothing', (tester) async {
      tall(tester);
      kanban.moveResult = const Err(
        IrisFailure(FailureKind.rejected, message: 'blocked by a parent'),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IrisButton, 'Move'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(IrisSheet),
          matching: find.text('Done'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('blocked by a parent'), findsOneWidget);
      // Rolled back: the header chip still names the column it was in.
      expect(find.text('REVIEW'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);
    });

    testWidgets('a detail that fails to load says so and keeps the title', (
      tester,
    ) async {
      tall(tester);
      kanban.detailResult = const Err(IrisFailure(FailureKind.server));
      await tester.pumpWidget(
        tab(
          child: TaskDetailScreen(
            taskId: 't_26',
            initial: fakeTask('t_26', title: 'Rotate gateway API keys'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rotate gateway API keys'), findsOneWidget);
      expect(find.text('Could not load this task'), findsOneWidget);
    });
  });
}
