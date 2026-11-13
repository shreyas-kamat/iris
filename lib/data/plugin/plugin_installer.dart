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
  }) : ok = true,
       error = null,
       showCommand = false;

  const PluginInstallResult.failure(this.error, {this.showCommand = false})
    : ok = false,
      installedVersion = null,
      recheckFailed = false;

  final bool ok;
  final String? error;

  /// The server cannot be asked from here: show the command to run on it instead.
  final bool showCommand;

  /// The version the server reports after the install; null when it could not be read back.
  final String? installedVersion;

  /// The install went through but the check afterwards got no answer.
  final bool recheckFailed;
}

final class PluginInstaller {
  PluginInstaller(this._client, {this.release = PluginRelease.current});

  final ApiClient _client;
  final PluginRelease release;

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
        return _fromFailure(failure);
      case Ok(:final value):
        if (value['ok'].boolOrNull == false) {
          return const PluginInstallResult.failure(
            'Hermes did not install the plugin.',
            showCommand: true,
          );
        }
    }
    final read = await DashboardGenUiApi(_client).capabilities();
    final version = read.valueOrNull?.version;
    return PluginInstallResult.success(
      installedVersion: version,
      recheckFailed: version == null,
    );
  }

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
