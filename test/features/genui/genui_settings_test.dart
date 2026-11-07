/// The Generated displays group in Settings: plugin status, install help, and the per-server, per-profile switch
/// (off by default).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/genui_providers.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/genui/displays_screen.dart';
import 'package:iris/features/genui/study_screen.dart';
import 'package:iris/features/settings/settings_screen.dart';

import '../../support/fake_chat_backend.dart';
import '../../support/fake_genui_api.dart';
import '../../support/harness.dart';

void main() {
  late FakeChatBackend backend;

  setUp(() {
    backend = FakeChatBackend()
      ..genUiCapabilitiesResult = const Ok(
        GenUiCapabilities(
          version: '0.1.0',
          openui: '1.0',
          libraryIds: ['v1'],
          features: {'capabilities', 'session-flag', 'surfaces'},
        ),
      );
  });
  tearDown(() => backend.close());

  Widget settings({required bool installed, MemoryPreferencesStore? store}) =>
      ProviderScope(
        overrides: [
          if (store != null) preferencesStoreProvider.overrideWithValue(store),
          genUiApiProvider.overrideWith((ref) async => FakeGenUiApi()),
          activeServerIdProvider.overrideWith(() => _FixedServer('s')),
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
          activeCapabilitiesProvider.overrideWith(
            (ref) => Stream.value(
              ServerCapabilities(
                available: {if (installed) ServerCapability.irisGenui},
                probedAt: DateTime(2026, 11, 7),
              ),
            ),
          ),
          activeChatProvider.overrideWith((ref) async => backend),
          conversationsProvider.overrideWith(
            (ref) async => const ConversationPage(items: [], total: 0),
          ),
          profilesProvider.overrideWith((ref) async => const []),
        ],
        child: themed(const SettingsScreen()),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

  testWidgets('without the plugin it says so and explains how to install', (
    tester,
  ) async {
    await tester.pumpWidget(settings(installed: false));
    await settle(tester);
    await tester.ensureVisible(find.text('Not installed'));
    expect(find.text('GENERATED DISPLAYS'), findsOneWidget);
    expect(find.text('Not installed'), findsOneWidget);
    expect(find.textContaining('hermes-iris'), findsOneWidget);
    expect(find.byWidgetPredicate(_isGenUiSwitch), findsNothing);
  });

  testWidgets('with the plugin the switch is off until it is turned on', (
    tester,
  ) async {
    final store = MemoryPreferencesStore();
    await tester.pumpWidget(settings(installed: true, store: store));
    await settle(tester);
    await tester.ensureVisible(find.text('Plugin'));
    expect(find.text('0.1.0'), findsOneWidget);
    expect(containerOf(tester).read(genUiEnabledProvider), isFalse);
    expect(
      tester.widget<IrisSwitch>(find.byWidgetPredicate(_isGenUiSwitch)).value,
      isFalse,
    );

    await tester.tap(find.byWidgetPredicate(_isGenUiSwitch));
    await settle(tester);

    expect(containerOf(tester).read(genUiEnabledProvider), isTrue);
    expect(store.values[('s/default', PreferenceKeys.genui)], 'true');
  });

  testWidgets('the choice is remembered per profile', (tester) async {
    await tester.pumpWidget(settings(installed: true));
    await settle(tester);
    final container = containerOf(tester);
    container.read(genUiEnabledProvider.notifier).set(enabled: true);
    expect(container.read(genUiEnabledProvider), isTrue);

    container.read(activeProfileProvider.notifier).select('ananta');
    expect(container.read(genUiEnabledProvider), isFalse);

    container.read(activeProfileProvider.notifier).select('default');
    expect(container.read(genUiEnabledProvider), isTrue);
  });

  testWidgets('displays are active only when switched on and confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(settings(installed: false));
    await settle(tester);
    final container = containerOf(tester);
    container.read(genUiEnabledProvider.notifier).set(enabled: true);
    expect(container.read(genUiActiveProvider), isFalse);
  });

  group('Study my work', () {
    Future<void> enable(WidgetTester tester) async {
      containerOf(
        tester,
      ).read(genUiEnabledProvider.notifier).set(enabled: true);
      await settle(tester);
      await tester.ensureVisible(find.text('Plugin'));
    }

    testWidgets('is offered once displays are on and the plugin can study', (
      tester,
    ) async {
      backend.genUiCapabilitiesResult = const Ok(
        GenUiCapabilities(
          version: '0.2.0',
          openui: '1.0',
          libraryIds: ['v1'],
          features: {'capabilities', 'profile', 'templates'},
        ),
      );
      await tester.pumpWidget(settings(installed: true));
      await settle(tester);
      expect(find.text('Study my work'), findsNothing, reason: 'switch is off');

      await enable(tester);
      expect(find.text('Study my work'), findsOneWidget);
      await tester.tap(find.text('Study my work'));
      await settle(tester);
      expect(find.byType(StudyScreen), findsOneWidget);
    });

    testWidgets('opens the kept displays when the plugin has templates', (
      tester,
    ) async {
      backend.genUiCapabilitiesResult = const Ok(
        GenUiCapabilities(
          version: '0.2.0',
          openui: '1.0',
          libraryIds: ['v1'],
          features: {'capabilities', 'profile', 'templates'},
        ),
      );
      await tester.pumpWidget(settings(installed: true));
      await settle(tester);
      await enable(tester);

      expect(find.text('Displays'), findsOneWidget);
      await tester.tap(find.text('Displays'));
      await settle(tester);
      expect(find.byType(DisplaysScreen), findsOneWidget);
    });

    testWidgets('asks an older plugin to be updated', (tester) async {
      await tester.pumpWidget(settings(installed: true));
      await settle(tester);
      await enable(tester);

      expect(find.text('Study my work'), findsOneWidget);
      expect(
        find.textContaining('Update the hermes-iris plugin'),
        findsOneWidget,
      );
      await tester.tap(find.text('Study my work'));
      await settle(tester);
      expect(find.byType(StudyScreen), findsNothing);
    });
  });
}

bool _isGenUiSwitch(Widget widget) =>
    widget is IrisSwitch && widget.semanticLabel == 'Generated displays';

final class _FixedServer extends ActiveServerId {
  _FixedServer(this._id);
  final String _id;

  @override
  String? build() => _id;
}
