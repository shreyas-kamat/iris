/// Settings: the rows show the real values, the brightness sheet drives the
/// theme, and the browser-skin switch drives the follow preference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/settings/settings_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  /// The same overrides the home screen tests use, so the rows read real
  /// values: a server labelled "Home" at h.example, a live link, and two
  /// profiles.
  Widget settings({List<AgentProfile> profiles = const []}) => ProviderScope(
    overrides: [
      activeServerProvider.overrideWithValue(
        const ServerConfig(
          id: 's',
          baseUrl: 'https://h.example',
          label: 'Home',
        ),
      ),
      activeLinkProvider.overrideWith(
        (ref) => Stream.value(const LinkState(LinkPhase.live)),
      ),
      activeChatProvider.overrideWith((ref) async => backend),
      conversationsProvider.overrideWith(
        (ref) async => const ConversationPage(items: [], total: 0),
      ),
      profilesProvider.overrideWith((ref) async => profiles),
    ],
    child: themed(const SettingsScreen()),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

  testWidgets('rows show the real values for the connection, agent and look', (
    tester,
  ) async {
    await tester.pumpWidget(
      settings(
        profiles: const [
          AgentProfile(name: 'default', isDefault: true, model: 'opus-4.5'),
          AgentProfile(name: 'ananta', model: 'gpt-6-luna'),
        ],
      ),
    );
    await settle(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('h.example'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('default'), findsOneWidget);
    expect(find.text('opus-4.5'), findsOneWidget);
    expect(find.text('Aperture'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('About names the licence and opens the open source licences', (
    tester,
  ) async {
    await tester.pumpWidget(settings());
    await settle(tester);
    await tester.ensureVisible(find.text('Open source licences'));
    expect(find.text('About'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.text('Source code'), findsOneWidget);

    await tester.tap(find.text('Open source licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Iris'), findsWidgets);
  });

  testWidgets('a single profile is not tappable', (tester) async {
    await tester.pumpWidget(
      settings(
        profiles: const [AgentProfile(name: 'default', isDefault: true)],
      ),
    );
    await settle(tester);
    // With no choice to offer, the profile row has no chevron and no tap.
    await tester.tap(find.text('default'));
    await settle(tester);
    expect(find.text('Profile'), findsOneWidget);
    expect(
      find.text('Each profile has its own conversations, memory and model.'),
      findsNothing,
    );
  });

  testWidgets('brightness set to Dark calls the theme controller', (
    tester,
  ) async {
    await tester.pumpWidget(settings());
    await settle(tester);
    expect(
      containerOf(tester).read(themeControllerProvider).mode,
      BrightnessMode.system,
    );

    await tester.tap(find.text('Brightness'));
    await settle(tester);
    await tester.tap(find.text('Dark'));
    await settle(tester);

    expect(
      containerOf(tester).read(themeControllerProvider).mode,
      BrightnessMode.dark,
    );
  });

  testWidgets('the browser-skin switch toggles followServerSkin', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(settings());
    await settle(tester);
    expect(
      containerOf(tester).read(themeControllerProvider).followServerSkin,
      isTrue,
    );
    expect(
      tester.getSemantics(find.byType(IrisSwitch)),
      matchesSemantics(
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byType(IrisSwitch));
    await settle(tester);

    expect(
      containerOf(tester).read(themeControllerProvider).followServerSkin,
      isFalse,
    );
    handle.dispose();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(settings());
    await settle(tester);
  }

  testWidgets('"While Hermes is replying" shows the mode and saves a change', (
    tester,
  ) async {
    backend.busyModeResult = const Ok(BusyMode.queue);
    await pumpSettings(tester);
    expect(find.text('While Hermes is replying'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    await tester.tap(find.text('While Hermes is replying'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();
    expect(backend.busyWrites, [BusyMode.interrupt]);
  });

  testWidgets('the row is absent when the server has no such setting', (
    tester,
  ) async {
    backend.busyModeResult = Err(unknownMethod('config.set'));
    await pumpSettings(tester);
    expect(find.text('While Hermes is replying'), findsNothing);
  });

  testWidgets('a failed save keeps the old value and says so', (tester) async {
    backend.busyModeResult = const Ok(BusyMode.queue);
    backend.setBusyResult = const Err(
      IrisFailure(FailureKind.rejected, message: 'nope'),
    );
    await pumpSettings(tester);
    await tester.tap(find.text('While Hermes is replying'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steer'));
    await tester.pumpAndSettle();
    expect(find.text('Queue'), findsOneWidget);
    expect(find.textContaining('Could not change'), findsOneWidget);
  });

  testWidgets('Profiles shows the count and opens the list', (tester) async {
    await tester.pumpWidget(
      settings(
        profiles: const [
          AgentProfile(name: 'default', isDefault: true, model: 'opus-4.5'),
          AgentProfile(name: 'ananta', model: 'gpt-6-luna'),
        ],
      ),
    );
    await settle(tester);
    await tester.ensureVisible(find.text('Profiles'));
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    expect(find.text('New profile'), findsOneWidget);
  });

  testWidgets('no Profiles row when the server has no profiles', (tester) async {
    await tester.pumpWidget(settings());
    await settle(tester);
    expect(find.text('Profiles'), findsNothing);
  });
}
