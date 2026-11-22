/// The Iris plugin on the active server: whether it is there, whether the offer to install it is due, and the install
/// itself. Both screens that offer it (the one after login and the Settings row) read these.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/net/capabilities.dart';
import '../data/plugin/plugin_installer.dart';
import '../data/plugin/plugin_release.dart';
import '../data/prefs/preferences_store.dart';
import '../data/rpc/dashboard_session.dart';
import '../demo/demo_mode.dart';
import 'genui_providers.dart';
import 'preferences.dart';
import 'providers.dart';

/// The release this build installs. A provider so tests can pin another.
final pluginReleaseProvider = Provider<PluginRelease>(
  (ref) => PluginRelease.current,
);

/// The installer for the active server. Null with no live server (the demo has none).
final pluginInstallerProvider = Provider<PluginInstaller?>((ref) {
  final session = ref.watch(activeSessionProvider).value;
  if (session == null) return null;
  return PluginInstaller(
    session.connection.client,
    release: ref.watch(pluginReleaseProvider),
  );
});

/// Asks the active server what it supports again, after an install.
final pluginReprobeProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final config = ref.read(activeServerProvider);
    if (config == null) return;
    await ref.read(serverRepositoryProvider).refreshCapabilities(config);
    ref.invalidate(genUiPluginProvider);
  };
});

/// Whether the plugin is there and how it compares with the release. Null in the demo or with no server; loading until
/// the first probe has answered.
final pluginStatusProvider = Provider<AsyncValue<PluginStatus?>>((ref) {
  if (ref.watch(demoModeProvider)) return const AsyncData(null);
  final installer = ref.watch(pluginInstallerProvider);
  final capabilities = ref.watch(activeCapabilitiesProvider).value;
  if (installer == null || capabilities == null || !capabilities.hasProbed) {
    return const AsyncLoading();
  }
  if (!capabilities.confirmed(ServerCapability.irisGenui)) {
    return const AsyncData(PluginAbsent());
  }
  final plugin = ref.watch(genUiPluginProvider);
  return switch (plugin) {
    AsyncData(:final value) => AsyncData(
      value == null
          // The probe found the plugin but its version did not come back: treat it as old enough to offer the update.
          ? PluginInstalled('unknown', updateTo: installer.release.version)
          : installer.statusOf(value),
    ),
    AsyncError(:final error, :final stackTrace) => AsyncError(
      error,
      stackTrace,
    ),
    _ => const AsyncLoading(),
  };
});

/// Whether the offer was already shown and left on the active server.
final pluginOnboardedProvider = NotifierProvider<PluginOnboarded, bool>(
  PluginOnboarded.new,
);

class PluginOnboarded extends Notifier<bool> {
  String? _scope;

  @override
  bool build() {
    _scope = ref.watch(activeServerIdProvider);
    final scope = _scope;
    if (scope == null) return false;
    return ref.read(preferencesProvider)[(
          scope,
          PreferenceKeys.pluginOnboarded,
        )] ==
        'true';
  }

  void markSeen() {
    final scope = _scope;
    state = true;
    if (scope == null) return;
    ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.pluginOnboarded, 'true');
  }
}

/// The offer is due: the server answered the probe with a login, the link is up, and the plugin is confirmed missing.
/// An unauthenticated probe also reports the plugin missing, so a challenged probe never counts.
final pluginOnboardingDueProvider = Provider<bool>((ref) {
  if (ref.watch(demoModeProvider)) return false;
  if (ref.watch(activeServerProvider) == null) return false;
  if (!ref.watch(pluginReleaseProvider).released) return false;
  if (ref.watch(pluginOnboardedProvider)) return false;
  final live = ref.watch(
    activeLinkProvider.select((link) => link.value?.phase == LinkPhase.live),
  );
  if (!live) return false;
  final capabilities = ref.watch(activeCapabilitiesProvider).value;
  return capabilities != null &&
      capabilities.hasProbed &&
      !capabilities.requiresAuth &&
      !capabilities.confirmed(ServerCapability.irisGenui);
});

sealed class PluginInstallState {
  const PluginInstallState();
}

final class PluginInstallIdle extends PluginInstallState {
  const PluginInstallIdle();
}

final class PluginInstalling extends PluginInstallState {
  const PluginInstalling({this.stillRunning = false});

  /// A proxy timed out; the server is still installing and the app is waiting for it.
  final bool stillRunning;
}

final class PluginInstallFailed extends PluginInstallState {
  const PluginInstallFailed(this.result);

  final PluginInstallResult result;
}

final class PluginInstallDone extends PluginInstallState {
  const PluginInstallDone(this.result);

  final PluginInstallResult result;
}

final pluginInstallProvider =
    NotifierProvider<PluginInstall, PluginInstallState>(PluginInstall.new);

class PluginInstall extends Notifier<PluginInstallState> {
  @override
  PluginInstallState build() => const PluginInstallIdle();

  /// Installs or updates the plugin. A second call while one runs does nothing.
  Future<void> install() async {
    if (state is PluginInstalling) return;
    final installer = ref.read(pluginInstallerProvider);
    if (installer == null) return;
    state = const PluginInstalling();
    var result = await installer.install();
    if (!ref.mounted) return;
    if (result.inProgress) {
      state = const PluginInstalling(stillRunning: true);
      result = await installer.finishPending();
      if (!ref.mounted) return;
    }
    if (!result.ok) {
      state = PluginInstallFailed(result);
      return;
    }
    await ref.read(pluginReprobeProvider)();
    if (!ref.mounted) return;
    ref.read(pluginOnboardedProvider.notifier).markSeen();
    state = PluginInstallDone(result);
  }
}
