/// Which providers' usage home shows: the profile's own by default, or a
/// chosen list, resolved against what the gateway reports.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/usage.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_chat_backend.dart';

const _codex = ProviderUsage(windows: [UsageWindow(label: 'Session', usedPercent: 73)]);
const _claude = ProviderUsage(windows: [UsageWindow(label: 'Current week', usedPercent: 87)]);

const _options = ModelOptions(
  provider: 'openai-codex',
  providers: [
    ModelProvider(slug: 'openai-codex', name: 'OpenAI Codex', models: ['m'], isCurrent: true, usage: _codex),
    ModelProvider(slug: 'anthropic', name: 'Anthropic', models: ['m'], usage: _claude),
    ModelProvider(slug: 'gemini', name: 'Gemini', models: ['m']),
  ],
);

void main() {
  group('resolving', () {
    test('the profile’s provider by default', () {
      final rows = resolveUsageRows(const [usageFollowsProfile], _options, profileProvider: 'anthropic');
      expect(rows.map((r) => r.name), ['Anthropic']);
    });

    test('without a profile provider, the gateway’s', () {
      final rows = resolveUsageRows(const [usageFollowsProfile], _options);
      expect(rows.single.slug, 'openai-codex');
    });

    test('a chosen list keeps its order, drops repeats and silent providers', () {
      final rows = resolveUsageRows(
        const ['anthropic', usageFollowsProfile, 'gemini', 'anthropic', 'missing'],
        _options,
        profileProvider: 'openai-codex',
      );
      expect(rows.map((r) => r.slug), ['anthropic', 'openai-codex']);
    });
  });

  group('the saved selection', () {
    ProviderContainer container(Map<PreferenceKey, String> saved, MemoryPreferencesStore store) {
      final c = ProviderContainer(
        overrides: [
          initialPreferencesProvider.overrideWithValue(saved),
          preferencesStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      c.read(activeServerIdProvider.notifier).select('s1');
      return c;
    }

    test('starts at the profile and remembers a choice per server', () async {
      final store = MemoryPreferencesStore();
      final c = container(const {}, store);
      expect(c.read(usageSelectionProvider), [usageFollowsProfile]);
      c.read(usageSelectionProvider.notifier).setAll(['anthropic', 'openai-codex', 'anthropic']);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(usageSelectionProvider), ['anthropic', 'openai-codex']);
      expect(store.values[('s1', PreferenceKeys.usageProviders)], '["anthropic","openai-codex"]');
      // Back to the default stores nothing.
      c.read(usageSelectionProvider.notifier).setAll([usageFollowsProfile]);
      await Future<void>.delayed(Duration.zero);
      expect(store.values.containsKey(('s1', PreferenceKeys.usageProviders)), isFalse);
    });

    test('a damaged saved value falls back to the profile', () {
      final c = container({('s1', PreferenceKeys.usageProviders): 'not json'}, MemoryPreferencesStore());
      expect(c.read(usageSelectionProvider), [usageFollowsProfile]);
    });
  });

  test('a cold cache is asked again once', () async {
    // First the gateway has no numbers yet; on the second ask it does.
    final backend = FakeChatBackend()
      ..modelOptionsQueue.addAll(const [
        Ok(
          ModelOptions(
            provider: 'openai-codex',
            providers: [ModelProvider(slug: 'openai-codex', name: 'OpenAI Codex', models: ['m'], isCurrent: true)],
          ),
        ),
        Ok(_options),
      ]);
    addTearDown(backend.close);
    final overrides = <Override>[
      activeLinkProvider.overrideWith((ref) => Stream.value(const LinkState(LinkPhase.live))),
      activeChatProvider.overrideWith((ref) async => backend),
      profilesProvider.overrideWith((ref) async => const <AgentProfile>[]),
      usageRetryDelayProvider.overrideWithValue(Duration.zero),
    ];
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    c.listen(usageOptionsProvider, (_, _) {});
    c.listen(activeLinkProvider, (_, _) {});
    await c.read(activeLinkProvider.future);
    await c.read(usageOptionsProvider.future);
    expect(backend.calls.where((call) => call == 'models').length, 2);
    c.listen(providerUsageProvider, (_, _) {});
    expect(c.read(providerUsageProvider).value?.single.slug, 'openai-codex');
  });
}
