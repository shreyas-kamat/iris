/// Installs or updates the hermes-iris plugin on a Hermes server through Hermes's own dashboard plugin route.
///
/// Install and update are one call: Hermes pins a plugin installed with a commit and refuses `/update` on it, so the
/// documented way to move is to install again with `force` and the new commit.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../genui/genui_api.dart';
import '../genui/genui_models.dart';
import '../net/api_client.dart';
import 'plugin_release.dart';

sealed class PluginStatus {
  const PluginStatus();
}

final class PluginAbsent extends PluginStatus {
  const PluginAbsent();
}

final class PluginInstalled extends PluginStatus {
  const PluginInstalled(this.version, {this.updateTo});

  final String version;

  /// The release's version when it is newer than [version] (or [version] cannot be read); null when current or ahead.
  final String? updateTo;
}

/// What an install attempt came to.
final class PluginInstallResult {
  const PluginInstallResult.success({
    this.installedVersion,
    this.recheckFailed = false,
    this.staleVersion,
  }) : ok = true,
       error = null,
       showCommand = false,
       inProgress = false;

  const PluginInstallResult.failure(this.error, {this.showCommand = false})
    : ok = false,
      installedVersion = null,
      recheckFailed = false,
      staleVersion = null,
      inProgress = false;

  /// A proxy gave up waiting (Cloudflare cuts a request at 120 s) but Hermes may still be installing: not a failure.
  const PluginInstallResult.stillRunning()
    : ok = false,
      error = null,
      showCommand = false,
      installedVersion = null,
      recheckFailed = false,
      staleVersion = null,
      inProgress = true;

  final bool ok;
  final String? error;

  /// The server cannot be asked from here: show the command to run on it instead.
  final bool showCommand;

  /// The version the server reports after the install; null when it could not be read back.
  final String? installedVersion;

  /// The install went through but the check afterwards got no answer.
  final bool recheckFailed;

  /// The server still reports this older version after the install: the running dashboard has not loaded the new
  /// plugin yet and needs a restart. Null when it reports the release (or something newer), or could not be read.
  final String? staleVersion;

  /// The request timed out at a proxy; the install may still be running on the server.
  final bool inProgress;
}

final class PluginInstaller {
  PluginInstaller(
    this._client, {
    this.release = PluginRelease.current,
    this.pollChecks = 48,
    this.pollEvery = const Duration(seconds: 5),
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  final ApiClient _client;
  final PluginRelease release;

  /// How many times [finishPending] asks the server, and how long it waits between asks (about four minutes).
  final int pollChecks;
  final Duration pollEvery;
  final Future<void> Function(Duration) _wait;

  static const _installPath = '/api/dashboard/agent-plugins/install';

  PluginStatus statusOf(GenUiCapabilities? plugin) {
    if (plugin == null) return const PluginAbsent();
    final behind = compareVersions(plugin.version, release.version) < 0;
    final readable = RegExp(r'^\d+(\.\d+)*').hasMatch(plugin.version);
    return PluginInstalled(
      plugin.version,
      updateTo: behind || !readable ? release.version : null,
    );
  }

  Future<PluginInstallResult> install() async {
    if (!release.released) {
      return const PluginInstallResult.failure(
        'This build of Iris has no released plugin yet.',
        showCommand: true,
      );
    }
    final response = await _client.post(
      _installPath,
      body: {
        'identifier': release.identifier,
        'ref': release.sha,
        'force': true,
        'enable': true,
      },
      receiveTimeout: const Duration(seconds: 180),
    );
    switch (response) {
      case Err(:final failure):
        if (_gatewayTimeout(failure)) {
          return const PluginInstallResult.stillRunning();
        }
        return _fromFailure(failure);
      case Ok(:final value):
        if (value['ok'].boolOrNull == false) {
          return const PluginInstallResult.failure(
            'Hermes did not install the plugin.',
            showCommand: true,
          );
        }
    }
    final version = await _readVersion();
    return _success(version);
  }

  /// Hermes installs for about three minutes (it prepares its whole Python environment when it enables a plugin),
  /// longer than a proxy waits. After a timeout, ask the server until it shows the release or the checks run out.
  Future<PluginInstallResult> finishPending() async {
    String? version;
    for (var i = 0; i < pollChecks; i++) {
      version = await _readVersion();
      if (version != null && compareVersions(version, release.version) >= 0) {
        break;
      }
      if (i < pollChecks - 1) await _wait(pollEvery);
    }
    return _success(version);
  }

  Future<String?> _readVersion() async {
    final read = await DashboardGenUiApi(_client).capabilities();
    return read.valueOrNull?.version;
  }

  PluginInstallResult _success(String? version) {
    final stale =
        version != null && compareVersions(version, release.version) < 0;
    return PluginInstallResult.success(
      installedVersion: version,
      recheckFailed: version == null,
      staleVersion: stale ? version : null,
    );
  }

  static bool _gatewayTimeout(IrisFailure failure) =>
      failure.kind == FailureKind.timeout ||
      failure.statusCode == 504 ||
      failure.statusCode == 524;

  PluginInstallResult _fromFailure(IrisFailure failure) {
    final status = failure.statusCode;
    if (status == 401 || status == 403) {
      return const PluginInstallResult.failure(
        'Your login cannot install plugins.',
        showCommand: true,
      );
    }
    final message = failure.message ?? 'The install failed.';
    // A rejection in a 200 body (`ok: false` with an `error`) arrives as a rejected failure with no status.
    final rejected = failure.kind == FailureKind.rejected && status == null;
    return PluginInstallResult.failure(
      message,
      showCommand: status == 404 || status == 405 || rejected,
    );
  }
}
