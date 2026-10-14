/// Settings: the rows show the real values, the brightness sheet drives the
/// theme, and the browser-skin switch drives the follow preference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/settings/settings_screen.dart';

import '../support/fake_chat_backend.dart';
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
        const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'Home'),
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

  ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(SettingsScreen)),
  );

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
    expect(find.text('Each profile has its own conversations, memory and model.'),
        findsNothing);
  });

  testWidgets('brightness set to Dark calls the theme controller', (
    tester,
  ) async {
    await tester.pumpWidget(settings());
    await settle(tester);
    expect(containerOf(tester).read(themeControllerProvider).mode,
        BrightnessMode.system);

    await tester.tap(find.text('Brightness'));
    await settle(tester);
    await tester.tap(find.text('Dark'));
    await settle(tester);

    expect(containerOf(tester).read(themeControllerProvider).mode,
        BrightnessMode.dark);
  });

  testWidgets('the browser-skin switch toggles followServerSkin', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(settings());
    await settle(tester);
    expect(containerOf(tester).read(themeControllerProvider).followServerSkin,
        isTrue);
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

    expect(containerOf(tester).read(themeControllerProvider).followServerSkin,
        isFalse);
    handle.dispose();
  });
}
