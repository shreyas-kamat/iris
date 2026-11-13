/// The Notifications screen: the master switch, each event's switch, words and mode, and what reaches the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/push_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/push/push_api.dart';
import 'package:iris/data/push/push_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/design/components/segmented.dart';
import 'package:iris/features/settings/notifications_settings_screen.dart';

import '../../support/harness.dart';

final class _FakePushApi implements PushApi {
  final calls = <String>[];
  PushSettings? lastSettings;
  Result<void> registerResult = const Ok(null);

  @override
  Future<Result<void>> register(
    String deviceId, {
    required String platform,
    String? apnsToken,
    required String appVersion,
    required PushSettings settings,
  }) async {
    calls.add('register');
    lastSettings = settings;
    return registerResult;
  }

  @override
  Future<Result<void>> updateSettings(
    String deviceId,
    PushSettings settings,
  ) async {
    calls.add('updateSettings');
    lastSettings = settings;
    return const Ok(null);
  }

  @override
  Future<Result<void>> unregister(String deviceId) async {
    calls.add('unregister');
    return const Ok(null);
  }

  @override
  Future<Result<void>> markActive(String storedSessionId) async =>
      const Ok(null);

  @override
  Future<Result<void>> sendTest(String deviceId) async {
    calls.add('sendTest');
    return const Ok(null);
  }
}

void main() {
  late _FakePushApi api;
  late MemoryPreferencesStore store;

  setUp(() {
    api = _FakePushApi();
    store = MemoryPreferencesStore();
  });

  Widget screen() => ProviderScope(
    overrides: [
      preferencesStoreProvider.overrideWithValue(store),
      activeServerIdProvider.overrideWith(() => _FixedServer('s')),
      pushApiProvider.overrideWith((ref) async => api),
    ],
    child: themed(const NotificationsSettingsScreen()),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(NotificationsSettingsScreen)),
      );

  Finder masterSwitch() => find.byWidgetPredicate(
    (w) => w is IrisSwitch && w.semanticLabel == 'Notify me',
  );

  testWidgets('starts off, with only the master switch', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    expect(tester.widget<IrisSwitch>(masterSwitch()).value, isFalse);
    expect(find.text('A reply'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('turning it on registers the device and shows the events', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);

    expect(api.calls, ['register']);
    expect(store.values[('s/default', PreferenceKeys.push)], 'true');
    expect(find.text('A reply'), findsWidgets);
    expect(find.text('Needs your approval'), findsWidgets);
    expect(find.text('A scheduled job finished'), findsWidgets);
  });

  testWidgets('turning it off unregisters', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);

    expect(api.calls, ['register', 'unregister']);
    expect(
      store.values.containsKey(('s/default', PreferenceKeys.push)),
      isFalse,
    );
  });

  testWidgets('a registration that fails puts the switch back', (tester) async {
    api.registerResult = const Err(IrisFailure(FailureKind.offline));
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);

    expect(tester.widget<IrisSwitch>(masterSwitch()).value, isFalse);
    expect(containerOf(tester).read(pushEnabledProvider), isFalse);
  });

  testWidgets('words typed for an event reach the server', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);
    api.calls.clear();

    await tester.enterText(find.byType(EditableText).first, 'Hey you 🎉');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(api.calls, ['updateSettings']);
    expect(api.lastSettings!.of(PushEvent.reply).text, 'Hey you 🎉');
    expect(
      containerOf(tester).read(pushSettingsProvider).of(PushEvent.reply).text,
      'Hey you 🎉',
    );
  });

  testWidgets('the text field stops at 100 characters', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);

    await tester.enterText(find.byType(EditableText).first, 'x' * 130);
    await tester.pump(const Duration(seconds: 1));

    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.controller.text.runes.length, 100);
    expect(
      containerOf(tester).read(pushSettingsProvider).of(PushEvent.reply).text,
      hasLength(100),
    );
  });

  testWidgets('the mode control changes only that event', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);
    api.calls.clear();

    await tester.tap(find.text("Show what's happening").first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final settings = containerOf(tester).read(pushSettingsProvider);
    expect(settings.of(PushEvent.reply).mode, PushMode.content);
    expect(settings.of(PushEvent.approval).mode, PushMode.content);
    expect(find.byType(IrisSegmented<PushMode>), findsWidgets);
    expect(api.calls, ['updateSettings']);
  });

  testWidgets('an event switched off hides its wording', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(masterSwitch());
    await settle(tester);
    expect(find.byType(EditableText), findsNWidgets(3));

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IrisSwitch && w.semanticLabel == 'A reply',
      ),
    );
    await settle(tester);
    expect(find.byType(EditableText), findsNWidgets(2));
  });

  testWidgets('settings are remembered per profile', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    final container = containerOf(tester);
    container
        .read(pushSettingsProvider.notifier)
        .update(
          PushEvent.job,
          const PushEventSettings(on: false, text: 'Done', mode: PushMode.text),
        );
    expect(container.read(pushSettingsProvider).of(PushEvent.job).on, isFalse);

    container.read(activeProfileProvider.notifier).select('ananta');
    expect(container.read(pushSettingsProvider), PushSettings.defaults);

    container.read(activeProfileProvider.notifier).select('default');
    expect(container.read(pushSettingsProvider).of(PushEvent.job).text, 'Done');
  });

  test('the device id is made once and kept', () {
    final container = ProviderContainer(
      overrides: [preferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final id = container.read(pushDeviceIdProvider);
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(container.read(pushDeviceIdProvider), id);
  });
}

class _FixedServer extends ActiveServerId {
  _FixedServer(this.id);
  final String id;

  @override
  String? build() => id;
}
