/// Home's usage strip: hidden with nothing to show, one row per provider,
/// expanding to every window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/usage.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/home/usage_strip.dart';

import '../support/harness.dart';

final _now = DateTime(2026, 10, 14, 9);

Widget _strip(AsyncValue<List<UsageRow>> rows) => ProviderScope(
  overrides: [
    providerUsageProvider.overrideWithValue(rows),
    clockProvider.overrideWithValue(() => _now),
  ],
  child: themed(const Align(alignment: Alignment.topCenter, child: UsageStrip())),
);

void main() {
  final codex = UsageRow(
    slug: 'openai-codex',
    name: 'OpenAI Codex',
    usage: ProviderUsage(
      windows: [
        UsageWindow(label: 'Session', usedPercent: 73, resetsAt: _now.add(const Duration(hours: 2, minutes: 36))),
        UsageWindow(label: 'Weekly', usedPercent: 48, resetsAt: _now.add(const Duration(days: 5, hours: 20))),
      ],
    ),
  );

  testWidgets('nothing to show, nothing shown', (tester) async {
    await tester.pumpWidget(_strip(const AsyncData([])));
    expect(find.byType(UsageStrip), findsOneWidget);
    expect(tester.getSize(find.byType(UsageStrip)).height, 0);
    await tester.pumpWidget(_strip(const AsyncLoading()));
    expect(tester.getSize(find.byType(UsageStrip)).height, 0);
  });

  testWidgets('a provider shows its tightest window as what is left', (tester) async {
    await tester.pumpWidget(_strip(AsyncData([codex])));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI Codex'), findsOneWidget);
    // The collapsed caption is rich text: the figure is weighted.
    expect(find.text('27% left · resets in 2h 36m', findRichText: true), findsOneWidget);
    expect(find.text('Weekly'), findsNothing);
  });

  testWidgets('tapping a row shows every window, and again hides them', (tester) async {
    await tester.pumpWidget(_strip(AsyncData([codex])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI Codex'));
    await tester.pumpAndSettle();
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('52% left · resets in 5d 20h'), findsOneWidget);
    await tester.tap(find.text('OpenAI Codex'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly'), findsNothing);
  });

  testWidgets('a pool shows each account and its state', (tester) async {
    const pool = UsageRow(
      slug: 'anthropic',
      name: 'Anthropic',
      usage: ProviderUsage(
        accounts: [
          UsageAccount(label: 'work', state: UsageAccountState.limited, windows: [UsageWindow(label: 'Week', usedPercent: 100)]),
          UsageAccount(label: 'home', state: UsageAccountState.ready, windows: [UsageWindow(label: 'Week', usedPercent: 30)]),
        ],
      ),
    );
    await tester.pumpWidget(_strip(const AsyncData([pool])));
    await tester.pumpAndSettle();
    expect(find.text('70% left', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Anthropic'));
    await tester.pumpAndSettle();
    // Account names are section labels, which are set in capitals.
    expect(find.text('WORK'), findsOneWidget);
    expect(find.text('LIMITED'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
  });
}
