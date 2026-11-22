/// When the plugin offer is due, and the install state behind both screens that make it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/plugin_providers.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/plugin/plugin_installer.dart';
import 'package:iris/data/plugin/plugin_release.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/demo/demo_mode.dart';

import '../support/fake_http.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';
const _server = ServerConfig(
  id: 's',
  baseUrl: 'https://h.example',
  label: 'Home',
);

PluginRelease _release({String sha = _sha}) => PluginRelease(
  version: '0.4.0',
  tag: 't',
  sha: sha,
  repo: 'a/b',
  subdir: 'c',
);

final class _FixedServer extends ActiveServerId {
  @override
  String? build() => 's';
}

void main() {
  late FakeHttp http;
  late int reprobes;

  setUp(() {
    http = FakeHttp();
    reprobes = 0;
  });

  ProviderContainer containerOf({
    bool probed = true,
    bool plugin = false,
    bool requiresAuth = false,
    bool live = true,
    bool demo = false,
    PluginRelease? release,
    MemoryPreferencesStore? store,
  }) {
    final connection = ServerConnection.create(_server, adapter: http);
    addTearDown(connection.close);
    final container = ProviderContainer(
      overrides: [
        preferencesStoreProvider.overrideWithValue(
          store ?? MemoryPreferencesStore(),
        ),
        demoModeProvider.overrideWithValue(demo),
        activeServerIdProvider.overrideWith(_FixedServer.new),
        activeServerProvider.overrideWithValue(_server),
        activeLinkProvider.overrideWith(
          (ref) => Stream.value(
            LinkState(live ? LinkPhase.live : LinkPhase.retrying),
          ),
        ),
        activeCapabilitiesProvider.overrideWith(
          (ref) => Stream.value(
            ServerCapabilities(
              available: {if (plugin) ServerCapability.irisGenui},
              probedAt: probed ? DateTime(2026, 11, 13) : null,
              requiresAuth: requiresAuth,
            ),
          ),
        ),
        pluginReleaseProvider.overrideWithValue(release ?? _release()),
        pluginInstallerProvider.overrideWithValue(
          PluginInstaller(
            connection.client,
            release: release ?? _release(),
            pollChecks: 2,
            wait: (_) async {},
          ),
        ),
        pluginReprobeProvider.overrideWithValue(() async => reprobes++),
      ],
    );
    addTearDown(container.dispose);
    // Providers pause without a listener (see the riverpod3-paused-providers memory).
    container
      ..listen(activeLinkProvider, (_, _) {})
      ..listen(activeCapabilitiesProvider, (_, _) {})
      ..listen(pluginOnboardingDueProvider, (_, _) {})
      ..listen(pluginInstallProvider, (_, _) {});
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('pluginOnboardingDueProvider', () {
    test('due when probed absent and not seen', () async {
      final container = containerOf();
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isTrue);
    });

    test('not due while the probe was challenged', () async {
      final container = containerOf(requiresAuth: true);
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
    });

    test('not due before the first probe', () async {
      final container = containerOf(probed: false);
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
    });

    test('not due when the plugin is there', () async {
      final container = containerOf(plugin: true);
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
    });

    test('not due while the link is down', () async {
      final container = containerOf(live: false);
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
    });

    test('not due in the demo', () async {
      final container = containerOf(demo: true);
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
    });

    test('not due when the release has no sha', () async {
      final container = containerOf(release: _release(sha: ''));
      await settle();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
    });

    test('not due after Not now, and that is remembered per server', () async {
      final store = MemoryPreferencesStore();
      final container = containerOf(store: store);
      await settle();
      container.read(pluginOnboardedProvider.notifier).markSeen();
      expect(container.read(pluginOnboardingDueProvider), isFalse);
      expect(store.values[('s', PreferenceKeys.pluginOnboarded)], 'true');
    });
  });

  group('pluginInstallProvider', () {
    test('install is single flight', () async {
      http
        ..on('POST', '/api/dashboard/agent-plugins/install', (_) {
          return FakeReply.json({'ok': true});
        })
        ..on(
          'GET',
          '/api/plugins/iris/capabilities',
          (_) => FakeReply.json({
            'version': '0.4.0',
            'features': <String>[],
            'library_ids': <String>[],
          }),
        );
      final container = containerOf();
      final notifier = container.read(pluginInstallProvider.notifier);

      final first = notifier.install();
      final second = notifier.install();
      await first;
      await second;

      expect(http.to('/api/dashboard/agent-plugins/install'), hasLength(1));
    });

    test('success re-probes the server and marks the offer seen', () async {
      http
        ..on(
          'POST',
          '/api/dashboard/agent-plugins/install',
          (_) => FakeReply.json({'ok': true}),
        )
        ..on(
          'GET',
          '/api/plugins/iris/capabilities',
          (_) => FakeReply.json({
            'version': '0.4.0',
            'features': <String>[],
            'library_ids': <String>[],
          }),
        );
      final container = containerOf();

      await container.read(pluginInstallProvider.notifier).install();

      final state = container.read(pluginInstallProvider);
      expect(state, isA<PluginInstallDone>());
      expect((state as PluginInstallDone).result.installedVersion, '0.4.0');
      expect(reprobes, 1);
      expect(container.read(pluginOnboardedProvider), isTrue);
    });

    test('a gateway timeout keeps installing until the server shows the '
        'version', () async {
      final versions = <String>['0.3.0', '0.4.0'];
      http
        ..on(
          'POST',
          '/api/dashboard/agent-plugins/install',
          (_) => FakeReply.html('timeout', status: 524),
        )
        ..on(
          'GET',
          '/api/plugins/iris/capabilities',
          (_) => FakeReply.json({
            'version': versions.removeAt(0),
            'features': <String>[],
            'library_ids': <String>[],
          }),
        );
      final container = containerOf();

      await container.read(pluginInstallProvider.notifier).install();

      final state = container.read(pluginInstallProvider);
      expect(state, isA<PluginInstallDone>());
      expect((state as PluginInstallDone).result.installedVersion, '0.4.0');
      expect(state.result.staleVersion, isNull);
      expect(http.to('/api/dashboard/agent-plugins/install'), hasLength(1));
      expect(container.read(pluginOnboardedProvider), isTrue);
    });

    test('failure keeps the error and does not mark the offer seen', () async {
      http.on(
        'POST',
        '/api/dashboard/agent-plugins/install',
        (_) => FakeReply.json({'detail': 'git failed'}, status: 500),
      );
      final container = containerOf();

      await container.read(pluginInstallProvider.notifier).install();

      final state = container.read(pluginInstallProvider);
      expect(state, isA<PluginInstallFailed>());
      expect((state as PluginInstallFailed).result.error, 'git failed');
      expect(reprobes, 0);
      expect(container.read(pluginOnboardedProvider), isFalse);
    });

    test('a failed attempt can be tried again', () async {
      http.on(
        'POST',
        '/api/dashboard/agent-plugins/install',
        (_) => FakeReply.json({'detail': 'git failed'}, status: 500),
      );
      final container = containerOf();
      final notifier = container.read(pluginInstallProvider.notifier);

      await notifier.install();
      await notifier.install();

      expect(http.to('/api/dashboard/agent-plugins/install'), hasLength(2));
    });
  });
}
