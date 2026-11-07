/// Generated displays: whether the person turned them on for this server and profile, whether the server has the
/// plugin, and the controller that flags conversations when both hold.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat/chat_backend.dart';
import '../data/genui/genui_api.dart';
import '../data/genui/genui_models.dart';
import '../data/genui/signals.dart';
import '../data/net/capabilities.dart';
import '../data/prefs/preferences_store.dart';
import 'preferences.dart';
import 'providers.dart';

/// The person's switch for the active server and profile. Off by default; a displays-capable server does nothing
/// different until it is turned on.
final genUiEnabledProvider = NotifierProvider<GenUiEnabled, bool>(
  GenUiEnabled.new,
);

class GenUiEnabled extends Notifier<bool> {
  String? _scope;

  @override
  bool build() {
    final server = ref.watch(activeServerIdProvider);
    final profile = ref.watch(activeProfileProvider);
    _scope = server == null ? null : '$server/$profile';
    if (_scope == null) return false;
    return ref.read(preferencesProvider)[(_scope!, PreferenceKeys.genui)] ==
        'true';
  }

  void set({required bool enabled}) {
    state = enabled;
    final scope = _scope;
    if (scope == null) return;
    // Off is stored as no key at all.
    ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.genui, enabled ? 'true' : null);
  }
}

/// The server has the hermes-iris plugin: confirmed by the probe, not assumed.
final genUiAvailableProvider = Provider<bool>(
  (ref) =>
      ref
          .watch(activeCapabilitiesProvider)
          .value
          ?.confirmed(ServerCapability.irisGenui) ??
      false,
);

/// Conversations get flagged: switched on, and the plugin is there.
final genUiActiveProvider = Provider<bool>(
  (ref) => ref.watch(genUiEnabledProvider) && ref.watch(genUiAvailableProvider),
);

/// What the plugin reports (its version), read when Settings asks. Null when there is no plugin or no answer.
final genUiPluginProvider = FutureProvider.autoDispose<GenUiCapabilities?>((
  ref,
) async {
  if (!ref.watch(genUiAvailableProvider)) return null;
  final chat = await ref.watch(activeChatProvider.future);
  if (chat is! SurfaceBackend) return null;
  return (await (chat as SurfaceBackend).genUiCapabilities()).valueOrNull;
});

/// The plugin's REST routes for the active server and profile: the profile, the templates and their review. Null when
/// there is no live server (the demo has none).
final genUiApiProvider = FutureProvider<GenUiApi?>((ref) async {
  final profile = ref.watch(activeProfileProvider);
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  return DashboardGenUiApi(session.connection.client, profile: profile);
});

/// Collects what the person does with displays and sends it to the plugin in small batches. Null while displays are
/// off, so nothing is recorded or sent unless the person turned them on.
final signalReporterProvider = Provider<SignalReporter?>((ref) {
  if (!ref.watch(genUiActiveProvider)) return null;
  final reporter = SignalReporter(api: () => ref.read(genUiApiProvider.future));
  ref.onDispose(reporter.dispose);
  return reporter;
});
