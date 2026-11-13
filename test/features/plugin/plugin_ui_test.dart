/// The Settings row that installs and updates the hermes-iris plugin, and the panel it shares with the onboarding
/// screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/plugin/plugin_onboarding_host.dart';
import 'package:iris/features/plugin/plugin_onboarding_screen.dart';
import 'package:iris/features/settings/plugin_settings_section.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';
const _server = ServerConfig(
  id: 's',
  baseUrl: 'https://h.example',
  label: 'Home',
);
const _release = PluginRelease(
  version: '0.4.0',
  tag: 'hermes-iris-v0.4.0',
  sha: _sha,
  repo: 'shreyas-kamat/iris',
  subdir: 'server/hermes-iris',
);

final class _FixedServer extends ActiveServerId {
  @override
  String? build() => 's';
}

/// An install that stays in flight until the test lets it finish, and counts the taps that reached it.
final class _SlowInstall extends PluginInstall {
  int calls = 0;
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> install() async {
    calls++;
    state = const PluginInstalling();
    await gate.future;
    if (!ref.mounted) return;
    state = const PluginInstallDone(
      PluginInstallResult.success(installedVersion: '0.4.0'),
    );
  }
}

void main() {
  late FakeHttp http;

  setUp(() {
    http = FakeHttp();
  });

  Widget section({
    PluginStatus? status = const PluginAbsent(),
    bool demo = false,
    PluginInstall Function()? install,
  }) {
    final connection = ServerConnection.create(_server, adapter: http);
    addTearDown(connection.close);
    return ProviderScope(
      overrides: [
        preferencesStoreProvider.overrideWithValue(MemoryPreferencesStore()),
        demoModeProvider.overrideWithValue(demo),
        activeServerIdProvider.overrideWith(_FixedServer.new),
        pluginReleaseProvider.overrideWithValue(_release),
        pluginStatusProvider.overrideWithValue(AsyncData(status)),
        pluginInstallerProvider.overrideWithValue(
          PluginInstaller(connection.client, release: _release),
        ),
        pluginReprobeProvider.overrideWithValue(() async {}),
        if (install != null) pluginInstallProvider.overrideWith(install),
      ],
      child: themed(
        const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: PluginSettingsSection(),
        ),
      ),
    );
  }

  /// Taps [label] and waits, in real time, until the install has finished one way or the other.
  Future<void> tapInstall(WidgetTester tester, String label) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(IrisButton, label));
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 5)) {
        final state = container.read(pluginInstallProvider);
        if (state is PluginInstallDone || state is PluginInstallFailed) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // A route pushed by the first answer from a provider needs another frame to appear and to finish.
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Settings section', () {
    testWidgets('shows Not installed with an Install button', (tester) async {
      await tester.pumpWidget(section());
      await settle(tester);
      expect(find.text('IRIS PLUGIN'), findsOneWidget);
      expect(find.text('Not installed'), findsOneWidget);
      expect(find.widgetWithText(IrisButton, 'Install'), findsOneWidget);
    });

    testWidgets('shows Version 0.3.0 and Update to 0.4.0', (tester) async {
      await tester.pumpWidget(
        section(status: const PluginInstalled('0.3.0', updateTo: '0.4.0')),
      );
      await settle(tester);
      expect(find.text('0.3.0'), findsOneWidget);
      expect(
        find.widgetWithText(IrisButton, 'Update to 0.4.0'),
        findsOneWidget,
      );
      expect(find.text('Up to date'), findsNothing);
    });

    testWidgets('shows Version 0.4.0 and Up to date, no button', (
      tester,
    ) async {
      await tester.pumpWidget(section(status: const PluginInstalled('0.4.0')));
      await settle(tester);
      expect(find.text('0.4.0'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.byType(IrisButton), findsNothing);
    });

    testWidgets('tapping Install calls the installer once and shows progress', (
      tester,
    ) async {
      final slow = _SlowInstall();
      await tester.pumpWidget(section(install: () => slow));
      await settle(tester);

      await tester.tap(find.widgetWithText(IrisButton, 'Install'));
      await tester.pump();
      expect(slow.calls, 1);
      expect(find.text('Installing…'), findsOneWidget);

      // A second tap while it runs reaches nothing: the button is busy.
      await tester.tap(find.widgetWithText(IrisButton, 'Install'));
      await tester.pump();
      expect(slow.calls, 1);

      slow.gate.complete();
      await settle(tester);
      expect(find.text('Installed version 0.4.0'), findsOneWidget);
    });

    testWidgets('a successful install posts the pinned release', (
      tester,
    ) async {
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
            'openui': '1.0',
            'library_ids': ['v1'],
            'features': ['capabilities'],
          }),
        );
      await tester.pumpWidget(section());
      await settle(tester);

      await tapInstall(tester, 'Install');
      await settle(tester);

      expect(http.to('/api/dashboard/agent-plugins/install'), hasLength(1));
      expect(find.text('Installed version 0.4.0'), findsOneWidget);
    });

    testWidgets(
      'a failure shows the error and the command, and Copy puts the command on the clipboard',
      (tester) async {
        http.on(
          'POST',
          '/api/dashboard/agent-plugins/install',
          (_) => FakeReply.json({'detail': 'gone'}, status: 404),
        );
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(section());
        await settle(tester);

        await tapInstall(tester, 'Install');
        await settle(tester);

        expect(find.text(_release.fallbackCommand), findsOneWidget);
        expect(find.widgetWithText(IrisButton, 'Try again'), findsOneWidget);

        await tester.tap(find.widgetWithText(IrisButton, 'Copy command'));
        await tester.pump();
        expect(copied, _release.fallbackCommand);
      },
    );

    testWidgets('is hidden in the demo', (tester) async {
      await tester.pumpWidget(section(demo: true, status: null));
      await settle(tester);
      expect(find.text('IRIS PLUGIN'), findsNothing);
      expect(find.byType(IrisButton), findsNothing);
    });

    testWidgets('the buttons have semantics labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        section(status: const PluginInstalled('0.3.0', updateTo: '0.4.0')),
      );
      await settle(tester);
      // The button's own label is merged with its text, so match on a pattern.
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Update to 0.4.0')).first,
      );
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('Onboarding', () {
    late MemoryPreferencesStore store;

    setUp(() => store = MemoryPreferencesStore());

    /// The real chain: probed, live, plugin absent, so the offer is due.
    Widget app({
      Widget? home,
      PluginInstall Function()? install,
      double textScale = 1,
      Size size = const Size(390, 844),
    }) {
      final connection = ServerConnection.create(_server, adapter: http);
      addTearDown(connection.close);
      return ProviderScope(
        overrides: [
          preferencesStoreProvider.overrideWithValue(store),
          demoModeProvider.overrideWithValue(false),
          activeServerIdProvider.overrideWith(_FixedServer.new),
          activeServerProvider.overrideWithValue(_server),
          activeLinkProvider.overrideWith(
            (ref) => Stream.value(const LinkState(LinkPhase.live)),
          ),
          activeCapabilitiesProvider.overrideWith(
            (ref) => Stream.value(
              ServerCapabilities(
                available: const {},
                probedAt: DateTime(2026, 11, 13),
              ),
            ),
          ),
          pluginReleaseProvider.overrideWithValue(_release),
          pluginInstallerProvider.overrideWithValue(
            PluginInstaller(connection.client, release: _release),
          ),
          pluginReprobeProvider.overrideWithValue(() async {}),
          if (install != null) pluginInstallProvider.overrideWith(install),
        ],
        child: themed(
          MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child:
                home ??
                const PluginOnboardingHost(child: Scaffold(body: Text('Home'))),
          ),
        ),
      );
    }

    testWidgets(
      'host pushes the screen once when due, and not again after Not now',
      (tester) async {
        await tester.pumpWidget(app());
        await settle(tester);
        expect(find.byType(PluginOnboardingScreen), findsOneWidget);
        expect(find.text('Get more from Iris'), findsOneWidget);

        await tester.tap(find.widgetWithText(IrisButton, 'Not now'));
        await settle(tester);
        expect(find.byType(PluginOnboardingScreen), findsNothing);
        expect(find.text('Home'), findsOneWidget);

        // The offer is not due again, so nothing comes back on later rebuilds.
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(PluginOnboardingScreen), findsNothing);
      },
    );

    testWidgets('Not now marks the server as seen and pops', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.tap(find.widgetWithText(IrisButton, 'Not now'));
      await settle(tester);
      expect(store.values[('s', PreferenceKeys.pluginOnboarded)], 'true');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('names what is missed without the plugin', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      expect(
        find.text('Add the Iris plugin to your Hermes server.'),
        findsOneWidget,
      );
      for (final title in [
        'Generated displays',
        'Alerts',
        'Study and templates',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('Install shows progress, then Installed v0.4.0 and Continue', (
      tester,
    ) async {
      final slow = _SlowInstall();
      await tester.pumpWidget(app(install: () => slow));
      await settle(tester);

      await tester.tap(find.widgetWithText(IrisButton, 'Install on my server'));
      await tester.pump();
      expect(slow.calls, 1);
      expect(find.text('Installing…'), findsOneWidget);

      slow.gate.complete();
      await settle(tester);
      expect(find.text('Installed v0.4.0'), findsOneWidget);
      expect(find.widgetWithText(IrisButton, 'Not now'), findsNothing);

      await tester.tap(find.widgetWithText(IrisButton, 'Continue'));
      await settle(tester);
      expect(find.byType(PluginOnboardingScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('failure shows the error, Try again and Not now', (
      tester,
    ) async {
      http.on(
        'POST',
        '/api/dashboard/agent-plugins/install',
        (_) => FakeReply.json({'detail': 'nope'}, status: 500),
      );
      await tester.pumpWidget(app());
      await settle(tester);

      await tapInstall(tester, 'Install on my server');
      await settle(tester);

      expect(find.widgetWithText(IrisButton, 'Try again'), findsOneWidget);
      expect(find.widgetWithText(IrisButton, 'Not now'), findsOneWidget);
      expect(find.text('Installed v0.4.0'), findsNothing);
    });

    testWidgets('the sheet names the source and version', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.tap(find.text('What does this install?'));
      await settle(tester);
      expect(
        find.textContaining('github.com/shreyas-kamat/iris'),
        findsWidgets,
      );
      expect(find.textContaining('0.4.0'), findsWidgets);
      expect(find.textContaining('unreviewed source'), findsOneWidget);
    });

    testWidgets('200% text does not overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          home: const PluginOnboardingScreen(),
          textScale: 2,
          size: const Size(320, 640),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PluginOnboardingScreen), findsOneWidget);
    });
  });
}
