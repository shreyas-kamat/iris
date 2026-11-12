/// The study review screen in both themes. Meant to be looked at: run with `--update-goldens`, then open the PNGs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/genui_providers.dart';
import 'package:iris/data/genui/personal_models.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/study_review_screen.dart';

import '../../support/fake_genui_api.dart';
import '../../support/fonts.dart';

void main() {
  setUpAll(loadIrisFonts);

  for (final changes in [false, true]) {
    for (final dark in [true, false]) {
      final name = changes ? 'study_changes' : 'study_review';
      testWidgets('$name, ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view
          ..physicalSize = const Size(390, 1100)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final api = FakeGenUiApi();
        if (changes) {
          api.stored = [
            sampleTemplate(
              'deploy',
              status: PersonalStatus.approved,
              program:
                  'root = Card([StatRow([Stat("Service", data.service), Stat("State", "Healthy")])], "Deploy")',
              proposal: const TemplateProposal(
                retire: false,
                reason:
                    'Opened in full 6 of 8 times, so it now starts expanded.',
                name: 'Deploy status',
                when: 'When reporting a deploy',
                kind: TemplateKind.display,
                program:
                    'root = Card([StatRow([Stat("Service", data.service), Stat("State", "Healthy"), Stat("Checks", "12/12")]), Text("Last deploy 4 min ago")], "Deploy")',
                sampleData: {'service': 'api'},
              ),
            ),
            sampleTemplate(
              'old',
              name: 'Incident card',
              status: PersonalStatus.approved,
              program: 'root = Card([Text(data.service)], "Incident")',
              proposal: const TemplateProposal(
                retire: true,
                reason: 'Not opened once in a month.',
              ),
            ),
          ];
        } else {
          api
            ..profile = const WorkProfile(
              summary: 'Backend engineer who ships a few services a week.',
              chips: ['Python', 'Deploys', 'On call'],
              status: PersonalStatus.proposed,
              rev: 1,
            )
            ..stored = [
              sampleTemplate(
                'deploy',
                program:
                    'root = Card([StatRow([Stat("Service", data.service), Stat("State", "Healthy")])], "Deploy")',
              ),
              sampleTemplate(
                'hold',
                name: 'Deploy decision',
                kind: TemplateKind.replyKit,
                program:
                    'root = ApproveReject("Deploy", "Hold", "Ask me first")',
                sample: const {},
              ),
            ];
        }
        final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [genUiApiProvider.overrideWith((ref) async => api)],
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 1100),
                disableAnimations: true,
              ),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.materialTheme,
                builder: (context, navigator) => IrisTheme(
                  data: theme,
                  child: Material(
                    type: MaterialType.transparency,
                    child: navigator,
                  ),
                ),
                home: const StudyReviewScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byType(StudyReviewScreen),
          matchesGoldenFile('goldens/${name}_${dark ? 'dark' : 'light'}.png'),
        );
      });
    }
  }
}
