import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/scheduled/job_detail_screen.dart';
import 'package:iris/features/scheduled/scheduled_tab.dart';

import '../support/fake_automation.dart';
import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);
  late FakeCronRepository cron;
  late FakeChatBackend chat;

  setUp(() {
    cron = FakeCronRepository();
    chat = FakeChatBackend();
  });
  tearDown(() => chat.close());

  List<CronJob> jobs() => [
    fakeJob(
      'a',
      name: 'Morning inbox digest',
      nextRun: now.add(const Duration(hours: 9, minutes: 12)),
    ),
    fakeJob(
      'b',
      name: 'Nightly backup',
      schedule: '0 2 * * *',
      lastError: 'backup target returned 502',
      lastRun: now.subtract(const Duration(hours: 2)),
    ),
    fakeJob('c', prompt: 'Check the build\nthen post', schedule: 'every 2h'),
    fakeJob('d', name: 'Sync Linear', enabled: false, schedule: '*/15 * * * *'),
    fakeJob('e', name: 'Audit', schedule: 'every 5m', state: CronState.running),
  ];

  Widget tab({List<CronJob>? list, Widget child = const ScheduledTab()}) =>
      ProviderScope(
        overrides: [
          cronRepositoryProvider.overrideWith((ref) async => cron),
          cronJobsProvider.overrideWith((ref) => Stream.value(list ?? jobs())),
          activeChatProvider.overrideWith((ref) async => chat),
          clockProvider.overrideWithValue(() => now),
        ],
        child: themed(child),
      );

  testWidgets('a card shows the name, the schedule verbatim and the status', (
    tester,
  ) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    expect(find.text('Morning inbox digest'), findsOneWidget);
    expect(find.text('0 7 * * *'), findsOneWidget);
    expect(find.text('next in 9h 12m'), findsOneWidget);
    expect(find.text('failed 2h ago'), findsOneWidget);
    expect(find.text('paused'), findsOneWidget);
    expect(find.text('running…'), findsOneWidget);
  });

  testWidgets('a job with no name shows its prompt\'s first line', (
    tester,
  ) async {
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    expect(find.text('Check the build'), findsOneWidget);
  });

  testWidgets(
    'hermes\'s own reading of the schedule wins over the expression',
    (tester) async {
      await tester.pumpWidget(
        tab(
          list: [
            fakeJob(
              'a',
              name: 'x',
              schedule: '0 9 * * 1',
              display: 'every monday 9am',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('every monday 9am'), findsOneWidget);
      expect(find.text('0 9 * * 1'), findsNothing);
    },
  );

  testWidgets('an empty list says so and offers a new job', (tester) async {
    await tester.pumpWidget(tab(list: const []));
    await tester.pumpAndSettle();
    expect(find.text('No scheduled jobs on default'), findsOneWidget);
    expect(find.widgetWithText(IrisButton, 'New job'), findsWidgets);
  });

  testWidgets('the switch pauses a job and shows it paused at once', (
    tester,
  ) async {
    cron.setEnabledGate = Completer<void>();
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    final switches = find.byType(IrisSwitch);
    await tester.tap(switches.first);
    await tester.pump();
    expect(cron.calls, contains('setEnabled a false'));
    expect(
      tester.widget<IrisSwitch>(switches.first).value,
      isFalse,
      reason: 'shown before the server has answered',
    );
    cron.setEnabledGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a refused pause flips the switch back and says why', (
    tester,
  ) async {
    cron.writeResult = const Err(
      IrisFailure(FailureKind.rejected, message: 'job is running'),
    );
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IrisSwitch).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<IrisSwitch>(find.byType(IrisSwitch).first).value,
      isTrue,
    );
    expect(find.text('job is running'), findsOneWidget);
  });

  testWidgets('a server without the route says it is not supported', (
    tester,
  ) async {
    cron.writeResult = const Err(IrisFailure(FailureKind.notFound));
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IrisSwitch).first);
    await tester.pumpAndSettle();
    expect(find.text('Not supported on this server'), findsOneWidget);
  });

  group('detail', () {
    CronJob failing() => fakeJob(
      'b',
      name: 'Nightly backup to cold storage',
      prompt: 'Back up /srv/data.',
      schedule: '0 2 * * *',
      lastError: 'backup target returned 502',
      lastRun: now.subtract(const Duration(hours: 2)),
      model: 'opus-4.5',
      deliver: 'telegram-ops',
    );

    /// The detail list builds lazily; a tall surface keeps every row built.
    void tall(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(800, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget detail() => tab(
      list: [failing()],
      child: JobDetailScreen(initial: failing()),
    );

    testWidgets('shows the error, prompt, model and delivery', (tester) async {
      tall(tester);
      await tester.pumpWidget(detail());
      await tester.pumpAndSettle();
      expect(find.text('Nightly backup to cold storage'), findsWidgets);
      expect(find.text('backup target returned 502'), findsOneWidget);
      expect(find.text('Back up /srv/data.'), findsOneWidget);
      expect(find.text('opus-4.5'), findsOneWidget);
      expect(find.text('telegram-ops'), findsOneWidget);
    });

    testWidgets('a job with no error shows no error block', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        tab(
          list: [fakeJob('a', name: 'Fine', prompt: 'p')],
          child: JobDetailScreen(
            initial: fakeJob('a', name: 'Fine', prompt: 'p'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Last error'), findsNothing);
      expect(find.text('Model'), findsNothing);
    });

    testWidgets('Run now triggers and says Started', (tester) async {
      tall(tester);
      await tester.pumpWidget(detail());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IrisButton, 'Run now'));
      await tester.pumpAndSettle();
      expect(cron.calls, contains('trigger b'));
      expect(find.text('Started'), findsOneWidget);
    });

    testWidgets('Delete asks first, then deletes', (tester) async {
      tall(tester);
      await tester.pumpWidget(detail());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IrisButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chats from past runs stay'), findsOneWidget);
      expect(cron.calls, isNot(contains('delete b')));
      await tester.tap(find.widgetWithText(IrisButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(cron.calls, contains('delete b'));
    });

    testWidgets('past runs list the run chats', (tester) async {
      tall(tester);
      cron.runsResult = const Ok([
        ConversationSummary(id: 'run-1', title: 'Backup run'),
      ]);
      await tester.pumpWidget(detail());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Past runs'), findsOneWidget);
      expect(find.text('Backup run'), findsOneWidget);
    });
  });
}
