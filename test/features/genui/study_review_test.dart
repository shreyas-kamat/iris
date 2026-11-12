/// The review of a study: each proposal drawn live with its sample, kept, renamed or dropped, nothing used until kept.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/genui_providers.dart';
import 'package:iris/data/genui/personal_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';
import 'package:iris/features/genui/study_review_screen.dart';

import '../../support/fake_genui_api.dart';
import '../../support/harness.dart';

void main() {
  late FakeGenUiApi api;

  setUp(() {
    api = FakeGenUiApi()
      ..profile = const WorkProfile(
        summary: 'Backend engineer who ships a few services a week.',
        chips: ['Python', 'Deploys'],
        status: PersonalStatus.proposed,
        rev: 1,
      )
      ..stored = [
        sampleTemplate('deploy'),
        sampleTemplate(
          'hold',
          name: 'Deploy decision',
          kind: TemplateKind.replyKit,
          program: 'root = ApproveReject("Deploy", "Hold")',
          sample: const {},
        ),
        sampleTemplate(
          'old',
          name: 'Already kept',
          status: PersonalStatus.approved,
        ),
      ];
  });

  Widget screen() => ProviderScope(
    overrides: [genUiApiProvider.overrideWith((ref) async => api)],
    child: themed(const StudyReviewScreen()),
  );

  /// A tall phone, so every card is on screen without scrolling.
  void tall(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    tall(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows the profile and each proposal drawn with its sample', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.textContaining('Backend engineer'), findsOneWidget);
    expect(find.text('PYTHON'), findsOneWidget);
    expect(find.text('Deploy status'), findsOneWidget);
    expect(find.text('Deploy decision'), findsOneWidget);
    expect(
      find.text('Already kept'),
      findsNothing,
      reason: 'only proposals are reviewed',
    );
    // The sample is bound as `data`, so the live card shows it.
    expect(find.byType(OpenUiView), findsNWidgets(2));
    expect(find.text('api'), findsOneWidget);
    expect(find.text('DOCKS ABOVE THE COMPOSER'), findsOneWidget);
    expect(api.calls, contains('templates:all'));
  });

  testWidgets('keeping a template approves it and takes it off the list', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('keep-deploy')));
    await settle(tester);

    expect(api.calls, contains('saveTemplate:deploy:approved'));
    expect(
      api.stored.firstWhere((t) => t.id == 'deploy').status,
      PersonalStatus.approved,
    );
    expect(find.text('Deploy status'), findsNothing);
    expect(find.text('Deploy decision'), findsOneWidget);
  });

  testWidgets('dropping a template retires it', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('drop-hold')));
    await settle(tester);

    expect(api.calls, contains('saveTemplate:hold:retired'));
    expect(find.text('Deploy decision'), findsNothing);
  });

  testWidgets('renaming saves the new name and keeps it proposed', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('rename-deploy')));
    await settle(tester);
    await tester.enterText(find.byType(EditableText), 'Release card');
    await tester.tap(find.widgetWithText(IrisButton, 'Save'));
    await settle(tester);

    expect(api.calls, contains('saveTemplate:deploy:Release card'));
    expect(find.text('Release card'), findsOneWidget);
    expect(find.text('Deploy status'), findsNothing);
  });

  testWidgets('keep all approves the profile and every proposal', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.widgetWithText(IrisButton, 'Keep all'));
    await settle(tester);
    await settle(tester);

    expect(api.calls, contains('saveWorkProfile:approved'));
    expect(api.calls, contains('saveTemplate:deploy:approved'));
    expect(api.calls, contains('saveTemplate:hold:approved'));
    expect(find.text('Nothing left to review'), findsOneWidget);
  });

  testWidgets('dropping the profile retires it', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('drop-profile')));
    await settle(tester);

    expect(api.calls, contains('saveWorkProfile:retired'));
    expect(find.textContaining('Backend engineer'), findsNothing);
  });

  testWidgets('a refused save says why and leaves the proposal there', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    api.refuse = 'The name is too long.';

    await tester.tap(find.byKey(const ValueKey('keep-deploy')));
    await settle(tester);

    expect(find.text('The name is too long.'), findsOneWidget);
    expect(find.text('Deploy status'), findsOneWidget);
  });

  testWidgets('says so when there is nothing to review', (tester) async {
    api
      ..profile = null
      ..stored = [];
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.text('Nothing left to review'), findsOneWidget);
    expect(find.widgetWithText(IrisButton, 'Keep all'), findsNothing);
  });

  group('changes to kept displays', () {
    UiTemplate kept({TemplateProposal? proposal}) => sampleTemplate(
      'deploy',
      status: PersonalStatus.approved,
      proposal: proposal,
    );

    TemplateProposal refine() => const TemplateProposal(
      retire: false,
      reason: 'Opened in full 6 of 8 times.',
      name: 'Deploy status',
      when: 'When reporting a deploy',
      kind: TemplateKind.display,
      program: 'root = Card([Text("Now: " + data.service)], "Deploy")',
      sampleData: {'service': 'web'},
    );

    testWidgets('shows what changes next to what it is now, with why', (
      tester,
    ) async {
      api
        ..profile = null
        ..stored = [kept(proposal: refine())];
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('Opened in full 6 of 8 times.'), findsOneWidget);
      expect(find.text('NOW'), findsOneWidget);
      expect(find.text('PROPOSED'), findsOneWidget);
      // Before and after are both drawn live.
      expect(find.byType(OpenUiView), findsNWidgets(2));
      expect(find.text('api'), findsOneWidget);
      expect(find.text('Now: web'), findsOneWidget);
      expect(api.calls, contains('templates:all'));
      expect(find.text('Nothing left to review'), findsNothing);
    });

    testWidgets('applying makes it the display and takes it off the list', (
      tester,
    ) async {
      api
        ..profile = null
        ..stored = [kept(proposal: refine())];
      await tester.pumpWidget(screen());
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('apply-deploy')));
      await settle(tester);

      expect(api.calls, contains('decideProposal:deploy:apply'));
      expect(api.stored.single.proposal, isNull);
      expect(find.text('Nothing left to review'), findsOneWidget);
    });

    testWidgets('discarding leaves the display as it was', (tester) async {
      api
        ..profile = null
        ..stored = [kept(proposal: refine())];
      await tester.pumpWidget(screen());
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('discard-deploy')));
      await settle(tester);

      expect(api.calls, contains('decideProposal:deploy:discard'));
      expect(api.stored.single.status, PersonalStatus.approved);
      expect(find.text('Nothing left to review'), findsOneWidget);
    });

    testWidgets('a suggestion to retire says so and asks', (tester) async {
      api
        ..profile = null
        ..stored = [
          kept(
            proposal: const TemplateProposal(
              retire: true,
              reason: 'Never opened in a month.',
            ),
          ),
        ];
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('Never opened in a month.'), findsOneWidget);
      expect(find.textContaining('retire'), findsWidgets);
      expect(find.text('PROPOSED'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('apply-deploy')));
      await settle(tester);

      expect(api.calls, contains('decideProposal:deploy:apply'));
      expect(api.stored.single.status, PersonalStatus.retired);
    });

    testWidgets('new proposals and changes are listed together', (
      tester,
    ) async {
      api.stored = [
        sampleTemplate('fresh', name: 'Fresh card'),
        kept(proposal: refine()),
      ];
      await tester.pumpWidget(screen());
      await settle(tester);

      expect(find.text('Fresh card'), findsOneWidget);
      expect(find.byKey(const ValueKey('keep-fresh')), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-deploy')), findsOneWidget);
    });

    testWidgets('a refused apply says why and leaves the change there', (
      tester,
    ) async {
      api
        ..profile = null
        ..stored = [kept(proposal: refine())];
      await tester.pumpWidget(screen());
      await settle(tester);
      api.refuse = 'The program no longer validates.';

      await tester.tap(find.byKey(const ValueKey('apply-deploy')));
      await settle(tester);

      expect(find.text('The program no longer validates.'), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-deploy')), findsOneWidget);
    });
  });

  testWidgets('leaving does not loop: the screen lets Back pop it', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pump();
    final scopes = tester.widgetList<PopScope<Object?>>(
      find.descendant(of: find.byType(StudyReviewScreen), matching: find.byWidgetPredicate((w) => w is PopScope)),
    );
    expect(scopes, isNotEmpty);
    // A screen that sets onBack to maybePop makes canPop false, and maybePop then calls
    // onBack again without end: the app hangs on the UI thread.
    expect(scopes.every((s) => s.canPop), isTrue);
  });
}
