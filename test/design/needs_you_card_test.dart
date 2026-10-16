import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/needs_you_card.dart';

import '../support/harness.dart';

void main() {
  testWidgets('the card shows eyebrow, title, body and actions', (tester) async {
    await tester.pumpWidget(
      themed(
        const NeedsYouCard(
          eyebrow: 'Needs you · unlock',
          title: '1Password is locked',
          subtitle: 'Hermes needs your github.com login to carry on.',
          actions: Text('actions'),
          child: Text('body'),
        ),
      ),
    );
    expect(find.text('NEEDS YOU · UNLOCK'), findsOneWidget);
    expect(find.text('1Password is locked'), findsOneWidget);
    expect(find.text('Hermes needs your github.com login to carry on.'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    expect(find.text('actions'), findsOneWidget);
  });

  testWidgets('a settled line names the outcome, never a value', (tester) async {
    for (final outcome in SettledOutcome.values) {
      await tester.pumpWidget(
        themed(SettledLine(title: 'Unlocked 1Password', detail: 'answered · 14:02', outcome: outcome)),
      );
      expect(find.text('Unlocked 1Password'), findsOneWidget, reason: outcome.name);
      expect(find.text('answered · 14:02'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the card does not overflow at 320pt wide and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      themed(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: const SingleChildScrollView(
            child: NeedsYouCard(
              eyebrow: 'Needs you · one-time code',
              title: 'Code for GitHub',
              child: Text('6 digits from your authenticator app.'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
