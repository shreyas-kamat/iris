import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/scheduled/job_form_screen.dart';

import '../support/fake_automation.dart';
import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeCronRepository cron;
  late FakeChatBackend chat;

  setUp(() {
    cron = FakeCronRepository();
    chat = FakeChatBackend();
  });
  tearDown(() => chat.close());

  Widget form({CronJob? job}) => ProviderScope(
    overrides: [
      cronRepositoryProvider.overrideWith((ref) async => cron),
      activeChatProvider.overrideWith((ref) async => chat),
    ],
    child: themed(JobFormScreen(job: job)),
  );

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is IrisField && w.label == label,
    description: 'IrisField $label',
  );

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<IrisButton>(find.widgetWithText(IrisButton, 'Save')).onPressed !=
      null;

  testWidgets('Save waits for a schedule and a prompt', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(saveEnabled(tester), isFalse);
    await tester.enterText(field('Schedule'), 'every 2h');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);
    await tester.enterText(field('Prompt'), 'Check the logs');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('shows the schedule hint', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(
      find.text('30m · every 2h · every monday 9am · 0 9 * * * · or a date'),
      findsOneWidget,
    );
  });

  testWidgets('creating sends the draft', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.enterText(field('Name · optional'), 'Digest');
    await tester.enterText(field('Schedule'), 'every monday 9am');
    await tester.enterText(field('Prompt'), 'Plan the week');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Save'));
    await tester.pumpAndSettle();
    expect(cron.calls, contains('create'));
    final draft = cron.drafts.single;
    expect(draft.name, 'Digest');
    expect(draft.schedule, 'every monday 9am');
    expect(draft.prompt, 'Plan the week');
    expect(draft.model, isNull);
  });

  testWidgets('a rejected schedule is shown under the field, verbatim', (
    tester,
  ) async {
    cron.writeResult = const Err(
      IrisFailure(
        FailureKind.rejected,
        statusCode: 422,
        message: "Couldn't parse 'every blursday'",
      ),
    );
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.enterText(field('Schedule'), 'every blursday');
    await tester.enterText(field('Prompt'), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't parse 'every blursday'"), findsOneWidget);
    expect(find.byType(JobFormScreen), findsOneWidget);
  });

  testWidgets('Deliver to is hidden when the server has no targets', (
    tester,
  ) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(find.text('Deliver to'), findsNothing);
  });

  testWidgets('Deliver to shows when the server lists targets', (tester) async {
    cron.targetsResult = const Ok([
      DeliveryTarget(id: 'telegram', name: 'telegram-ops'),
    ]);
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(find.text('Deliver to'), findsOneWidget);
    await tester.tap(find.text('Deliver to'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('telegram-ops'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Schedule'), '30m');
    await tester.enterText(field('Prompt'), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Save'));
    await tester.pumpAndSettle();
    expect(cron.drafts.single.deliver, 'telegram');
  });

  testWidgets('editing starts from the job and calls update', (tester) async {
    await tester.pumpWidget(
      form(
        job: fakeJob('j1', name: 'Digest', prompt: 'Summarise'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit job'), findsOneWidget);
    expect(find.text('Digest'), findsWidgets);
    await tester.enterText(field('Prompt'), 'Summarise differently');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Save'));
    await tester.pumpAndSettle();
    expect(cron.calls, contains('update j1'));
  });

  testWidgets('cancelling with edits asks before discarding', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.enterText(field('Prompt'), 'half a thought');
    await tester.pump();
    await tester.tap(find.widgetWithText(IrisButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(JobFormScreen), findsOneWidget);
  });

  testWidgets('cancelling a clean form just closes it', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(IrisButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
  });
}
