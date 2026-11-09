/// The Displays screen: what the person has approved, with a live preview, rename and retire, a way back to the review
/// and to a new study.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/genui_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/genui/personal_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/genui/displays_screen.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';
import 'package:iris/features/genui/study_review_screen.dart';
import 'package:iris/features/genui/study_screen.dart';

import '../../support/fake_chat_backend.dart';
import '../../support/fake_genui_api.dart';
import '../../support/harness.dart';

void main() {
  late FakeGenUiApi api;
  late FakeChatBackend backend;

  setUp(() {
    backend = FakeChatBackend();
    api = FakeGenUiApi()
      ..profile = const WorkProfile(
        summary: 'Backend engineer who ships a few services a week.',
        chips: ['Python'],
        status: PersonalStatus.approved,
        rev: 2,
      )
      ..stored = [
        sampleTemplate('deploy', status: PersonalStatus.approved),
        sampleTemplate(
          'hold',
          name: 'Deploy decision',
          kind: TemplateKind.replyKit,
          status: PersonalStatus.approved,
          program: 'root = ApproveReject("Deploy", "Hold")',
          sample: const {},
        ),
        sampleTemplate('new', name: 'Incident card'),
        sampleTemplate(
          'gone',
          name: 'Retired card',
          status: PersonalStatus.retired,
        ),
      ];
  });

  tearDown(() => backend.close());

  Widget screen() => ProviderScope(
    overrides: [
      genUiApiProvider.overrideWith((ref) async => api),
      activeChatProvider.overrideWith((ref) async => backend),
    ],
    child: themed(const DisplaysScreen()),
  );

  Future<void> settle(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('lists approved displays with a live preview and the profile', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.textContaining('Backend engineer'), findsOneWidget);
    expect(find.text('Deploy status'), findsOneWidget);
    expect(find.text('Deploy decision'), findsOneWidget);
    expect(find.text('Retired card'), findsNothing);
    expect(find.text('Incident card'), findsNothing);
    expect(find.byType(OpenUiView), findsNWidgets(2));
    expect(find.text('api'), findsOneWidget);
  });

  testWidgets('says how many proposals wait, and opens the review', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.text('1 proposal waiting for you'), findsOneWidget);
    await tester.tap(find.text('1 proposal waiting for you'));
    await settle(tester);
    expect(find.byType(StudyReviewScreen), findsOneWidget);
  });

  testWidgets('counts changes to kept displays apart from new proposals', (
    tester,
  ) async {
    api.stored = [
      sampleTemplate('deploy', status: PersonalStatus.approved),
      sampleTemplate(
        'hold',
        status: PersonalStatus.approved,
        proposal: const TemplateProposal(retire: true, reason: 'Unused.'),
      ),
    ];
    await tester.pumpWidget(screen());
    await settle(tester);
    expect(find.text('1 change waiting for you'), findsOneWidget);

    api.stored = [
      ...api.stored,
      sampleTemplate('new1'),
      sampleTemplate('new2'),
    ];
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await settle(tester);
    expect(
      find.text('2 proposals and 1 change waiting for you'),
      findsOneWidget,
    );
  });

  testWidgets('no badge when nothing is waiting', (tester) async {
    api.stored = [sampleTemplate('deploy', status: PersonalStatus.approved)];
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.textContaining('waiting for you'), findsNothing);
  });

  testWidgets('retiring takes a display off the list', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('retire-deploy')));
    await settle(tester);

    expect(api.calls, contains('saveTemplate:deploy:retired'));
    expect(find.text('Deploy status'), findsNothing);
    expect(find.text('Deploy decision'), findsOneWidget);
  });

  testWidgets('renaming saves the new name', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('rename-deploy')));
    await settle(tester);
    await tester.enterText(find.byType(EditableText), 'Release card');
    await tester.tap(find.widgetWithText(IrisButton, 'Save'));
    await settle(tester);

    expect(api.calls, contains('saveTemplate:deploy:Release card'));
    expect(find.text('Release card'), findsOneWidget);
  });

  testWidgets('study again opens the study', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tester.tap(find.widgetWithText(IrisButton, 'Study again'));
    await settle(tester);
    expect(find.byType(StudyScreen), findsOneWidget);
  });

  testWidgets('says so when there is nothing approved yet', (tester) async {
    api
      ..profile = null
      ..stored = [];
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.text('No displays yet'), findsOneWidget);
    expect(find.widgetWithText(IrisButton, 'Study my work'), findsOneWidget);
  });
}
