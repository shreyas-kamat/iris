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
    expect(api.calls, contains('templates:proposed'));
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
}
