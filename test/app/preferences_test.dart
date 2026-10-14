/// The theme and the profile survive a restart, and a remembered profile the
/// server no longer has falls back to the default.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/tokens/palette.dart';

import '../support/fake_chat_backend.dart';

void main() {
  ProviderContainer containerWith(
    Map<PreferenceKey, String> saved, {
    MemoryPreferencesStore? store,
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        initialPreferencesProvider.overrideWithValue(saved),
        preferencesStoreProvider.overrideWithValue(
          store ?? MemoryPreferencesStore(),
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the theme starts from what was saved', () {
    final container = containerWith({
      ('', PreferenceKeys.skin): IrisSkin.mono.name,
      ('', PreferenceKeys.mode): BrightnessMode.dark.name,
      ('', PreferenceKeys.followServerSkin): 'false',
    });
    final theme = container.read(themeControllerProvider);
    expect(theme.skin, IrisSkin.mono);
    expect(theme.mode, BrightnessMode.dark);
    expect(theme.followServerSkin, isFalse);
  });

  test('nothing saved means the defaults', () {
    final theme = containerWith(const {}).read(themeControllerProvider);
    expect(theme, const ThemePreference());
  });

  test('changing the theme writes it through', () async {
    final store = MemoryPreferencesStore();
    final container = containerWith(const {}, store: store);
    container.read(themeControllerProvider.notifier)
      ..setMode(BrightnessMode.light)
      ..setSkin(IrisSkin.slate)
      ..setFollowServerSkin(follow: false);
    await Future<void>.delayed(Duration.zero);
    expect(store.values[('', PreferenceKeys.mode)], 'light');
    expect(store.values[('', PreferenceKeys.skin)], 'slate');
    expect(store.values[('', PreferenceKeys.followServerSkin)], 'false');
  });

  test('the profile is remembered per server', () async {
    final store = MemoryPreferencesStore();
    final container = containerWith({
      ('s1', PreferenceKeys.profile): 'ananta',
    }, store: store);
    container.read(activeServerIdProvider.notifier).select('s1');
    expect(container.read(activeProfileProvider), 'ananta');

    container.read(activeProfileProvider.notifier).select('indra');
    await Future<void>.delayed(Duration.zero);
    expect(store.values[('s1', PreferenceKeys.profile)], 'indra');

    // Choosing the default forgets the key rather than storing "default".
    container.read(activeProfileProvider.notifier).select('default');
    await Future<void>.delayed(Duration.zero);
    expect(store.values.containsKey(('s1', PreferenceKeys.profile)), isFalse);

    // Another server starts at its own default.
    container.read(activeServerIdProvider.notifier).select('s2');
    expect(container.read(activeProfileProvider), 'default');
  });

  test('a remembered profile the server lacks falls back', () async {
    final backend = FakeChatBackend()
      ..profilesResult = const Ok([
        AgentProfile(name: 'default', isDefault: true),
        AgentProfile(name: 'ananta'),
      ]);
    addTearDown(backend.close);
    final store = MemoryPreferencesStore()
      ..values[('s1', PreferenceKeys.profile)] = 'gone';
    final container = containerWith(
      {('s1', PreferenceKeys.profile): 'gone'},
      store: store,
      extra: [
        activeLinkProvider.overrideWith(
          (ref) => Stream.value(const LinkState(LinkPhase.live)),
        ),
        activeChatProvider.overrideWith((ref) async => backend),
      ],
    );
    container.read(activeServerIdProvider.notifier).select('s1');
    container.listen(profilesProvider, (_, _) {});
    container.listen(activeLinkProvider, (_, _) {});
    await container.read(activeLinkProvider.future);
    await container.read(profilesProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(activeProfileProvider), 'default');
    expect(store.values.containsKey(('s1', PreferenceKeys.profile)), isFalse);
  });
}
