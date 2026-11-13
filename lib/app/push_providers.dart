/// Notifications: this install's id, the person's switch and wording for the active server and profile, and the
/// controller that keeps the hermes-iris plugin in step with them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/result.dart';
import '../data/prefs/preferences_store.dart';
import '../data/push/push_api.dart';
import '../data/push/push_controller.dart';
import '../data/push/push_models.dart';
import 'genui_providers.dart';
import 'preferences.dart';
import 'providers.dart';

/// The version reported at registration. It tracks `pubspec.yaml`; no package is added only to read it back.
const pushAppVersion = '1.0.0';

/// Random id for this install, made once and kept. The server knows a device by it and nothing else about the phone.
final pushDeviceIdProvider = Provider<String>((ref) {
  final stored = ref.read(
    preferencesProvider,
  )[('', PreferenceKeys.pushDeviceId)];
  if (stored != null && stored.isNotEmpty) return stored;
  final random = Random.secure();
  final id = [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  // Not while this provider builds: writing another provider's state during a build is refused.
  scheduleMicrotask(
    () => ref
        .read(preferencesProvider.notifier)
        .set('', PreferenceKeys.pushDeviceId, id),
  );
  return id;
});

/// `android` or `ios`, the only two platforms the plugin knows.
String get pushPlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

/// The plugin on this server reports push: confirmed by its own capabilities, so an older plugin is told to update.
final pushAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(genUiAvailableProvider) &&
      (ref.watch(genUiPluginProvider).value?.has('push') ?? false),
);

String? _scope(Ref ref) {
  final server = ref.watch(activeServerIdProvider);
  final profile = ref.watch(activeProfileProvider);
  return server == null ? null : '$server/$profile';
}

/// The person's master switch for the active server and profile. Off by default; nothing is registered until it is on.
final pushEnabledProvider = NotifierProvider<PushEnabled, bool>(
  PushEnabled.new,
);

class PushEnabled extends Notifier<bool> {
  String? _scope_;

  @override
  bool build() {
    _scope_ = _scope(ref);
    if (_scope_ == null) return false;
    return ref.read(preferencesProvider)[(_scope_!, PreferenceKeys.push)] ==
        'true';
  }

  /// Turns notifications on or off and tells the server. A registration that fails puts the switch back and returns
  /// the failure.
  Future<Result<void>> set({required bool enabled}) async {
    final scope = _scope_;
    if (scope == null) return const Ok(null);
    state = enabled;
    // Off is stored as no key at all.
    ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.push, enabled ? 'true' : null);
    final controller = await ref.read(pushControllerProvider.future);
    if (controller == null) return const Ok(null);
    final result = await controller.setEnabled(on: enabled);
    if (enabled && result.isErr) {
      state = false;
      ref
          .read(preferencesProvider.notifier)
          .set(scope, PreferenceKeys.push, null);
    }
    return result;
  }
}

/// The wording and switches per event, kept per server and profile and sent to the server when push is on.
final pushSettingsProvider =
    NotifierProvider<PushSettingsController, PushSettings>(
      PushSettingsController.new,
    );

class PushSettingsController extends Notifier<PushSettings> {
  String? _scope_;
  Timer? _debounce;

  @override
  PushSettings build() {
    _scope_ = _scope(ref);
    ref.onDispose(() => _debounce?.cancel());
    if (_scope_ == null) return PushSettings.defaults;
    return PushSettings.decode(
      ref.read(preferencesProvider)[(_scope_!, PreferenceKeys.pushSettings)],
    );
  }

  /// Changes one event's settings. Saved on the phone at once; sent to the server once typing pauses.
  void update(PushEvent event, PushEventSettings settings) {
    final scope = _scope_;
    state = state.withEvent(event, settings);
    if (scope == null) return;
    ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.pushSettings, jsonEncode(state.toJson()));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final controller = await ref.read(pushControllerProvider.future);
      await controller?.saveSettings();
    });
  }
}

/// The plugin's push routes for the active server and profile. Null when there is no live server (the demo has none).
final pushApiProvider = FutureProvider<PushApi?>((ref) async {
  final profile = ref.watch(activeProfileProvider);
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  return DashboardPushApi(session.connection.client, profile: profile);
});

/// Keeps the server in step with this install. Null with no live server.
final pushControllerProvider = FutureProvider<PushController?>((ref) async {
  final api = await ref.watch(pushApiProvider.future);
  if (api == null) return null;
  return PushController(
    api,
    deviceId: ref.read(pushDeviceIdProvider),
    platform: pushPlatform,
    appVersion: pushAppVersion,
    enabled: () => ref.read(pushEnabledProvider),
    settings: () => ref.read(pushSettingsProvider),
  );
});
