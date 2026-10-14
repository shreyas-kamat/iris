/// Choosing which providers' usage home shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/usage.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/settings/usage_settings_screen.dart';

import '../support/harness.dart';

const _usage = ProviderUsage(windows: [UsageWindow(label: 'S', usedPercent: 1)]);

const _options = ModelOptions(
  provider: 'openai-codex',
  providers: [
    ModelProvider(slug: 'openai-codex', name: 'OpenAI Codex', models: ['m'], usage: _usage),
    ModelProvider(slug: 'anthropic', name: 'Anthropic', models: ['m'], usage: _usage),
    ModelProvider(slug: 'gemini', name: 'Gemini', models: ['m']),
  ],
);

void main() {
  late ProviderContainer container;

  Widget screen() {
    container = ProviderContainer(
      overrides: [usageOptionsProvider.overrideWith((ref) async => _options)],
    );
    addTearDown(container.dispose);
    container.read(activeServerIdProvider.notifier).select('s1');
    return UncontrolledProviderScope(
      container: container,
      child: themed(const UsageSettingsScreen()),
    );
  }

  testWidgets('main starts as the profile’s provider; secondary as none', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text("Profile's provider"), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('choosing a secondary saves it; only providers with usage are offered', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Secondary'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini'), findsNothing);
    await tester.tap(find.text('Anthropic'));
    await tester.pumpAndSettle();
    expect(container.read(usageSelectionProvider), [usageFollowsProfile, 'anthropic']);
  });

  testWidgets('another provider can be added and removed', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    container.read(usageSelectionProvider.notifier).setAll([usageFollowsProfile, 'anthropic']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI Codex'));
    await tester.pumpAndSettle();
    expect(container.read(usageSelectionProvider), [usageFollowsProfile, 'anthropic', 'openai-codex']);
    await tester.tap(find.bySemanticsLabel('Remove OpenAI Codex'));
    await tester.pumpAndSettle();
    expect(container.read(usageSelectionProvider), [usageFollowsProfile, 'anthropic']);
  });

  test('the settings row summarises the choice', () {
    expect(usageSummary(const [usageFollowsProfile], _options), "Profile's provider");
    expect(usageSummary(const ['anthropic'], _options), 'Anthropic');
    expect(usageSummary(const ['anthropic', 'openai-codex'], _options), 'Anthropic + 1');
  });
}
