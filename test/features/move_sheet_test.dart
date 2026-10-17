import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tasks/move_sheet.dart';

import '../support/fake_automation.dart';
import '../support/harness.dart';

void main() {
  const columns = ['triage', 'todo', 'ready', 'running', 'blocked', 'review', 'done'];
  final task = fakeTask('t_31', title: 'Backup failing', status: 'blocked');

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showMoveSheet(
                context,
                task: task,
                columns: columns,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the task and lists the columns', (tester) async {
    await open(tester);
    expect(find.text('Move t_31'), findsOneWidget);
    expect(find.text('Backup failing'), findsOneWidget);
    for (final label in ['Triage', 'To do', 'Ready', 'Blocked', 'Done']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Running and Review say they are set by Hermes', (tester) async {
    await open(tester);
    expect(find.text('Set by Hermes'), findsNWidgets(2));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
  });

  testWidgets('a locked row does not respond to a tap', (tester) async {
    await open(tester);
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    expect(find.text('Move t_31'), findsOneWidget, reason: 'sheet still open');
  });

  testWidgets('tapping a free column returns its id', (tester) async {
    String? result;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await showMoveSheet(
                context,
                task: task,
                columns: columns,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('To do'));
    await tester.pumpAndSettle();
    expect(result, 'todo');
  });

  testWidgets('tapping the current column closes without a move', (
    tester,
  ) async {
    String? result = 'untouched';
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await showMoveSheet(
                context,
                task: task,
                columns: columns,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocked'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('an unknown column shows under its own name', (tester) async {
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showMoveSheet(
                context,
                task: task,
                columns: [...columns, 'sprinting'],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sprinting'), findsOneWidget);
  });
}
