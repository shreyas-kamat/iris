/// Keeps the server's idea of this install in step with the person's switches: registered or not, the settings they
/// chose, and which chat they last sent to.
///
/// Nothing here throws. A notification is a convenience; a failure is logged by kind and the chat carries on.
library;

import '../../core/logging.dart';
import '../../core/result.dart';
import 'push_api.dart';
import 'push_models.dart';

final class PushController {
  PushController(
    this._api, {
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required bool Function() enabled,
    required PushSettings Function() settings,
    Future<String?> Function()? apnsToken,
  }) : _enabled = enabled,
       _settings = settings,
       _apnsToken = apnsToken;

  static const _log = IrisLog('push');

  final PushApi _api;
  final String deviceId;

  /// `android` or `ios`, as the plugin names them.
  final String platform;
  final String appVersion;

  /// Read at every call: the person's master switch for this server and profile.
  final bool Function() _enabled;
  final PushSettings Function() _settings;

  /// The iPhone's APNs token, once the native side has one. Null on Android.
  final Future<String?> Function()? _apnsToken;

  /// Marks [storedId] as the chat the person is waiting on. A no-op while push is off.
  Future<void> markActive(String storedId) async {
    if (!_enabled()) return;
    if (await _api.markActive(storedId) case Err(:final failure)) {
      _log.warn('could not mark a chat active', data: failure.kind.name);
    }
  }

  /// Registers this install ([on]) or removes it. The caller has already stored the switch.
  Future<Result<void>> setEnabled({required bool on}) async {
    final result = on ? await _register() : await _api.unregister(deviceId);
    if (result case Err(:final failure)) {
      _log.warn('could not change push', data: '${failure.kind.name} on=$on');
    }
    return result;
  }

  /// Registers again with the current settings and token; safe to repeat.
  Future<Result<void>> sync() async {
    if (!_enabled()) return const Ok(null);
    return _register();
  }

  /// Sends the current settings. While push is off they are only kept on the phone.
  Future<Result<void>> saveSettings() async {
    if (!_enabled()) return const Ok(null);
    final result = await _api.updateSettings(deviceId, _settings());
    if (result case Err(:final failure)) {
      _log.warn('could not save settings', data: failure.kind.name);
    }
    return result;
  }

  Future<Result<void>> sendTest() async {
    final result = await _api.sendTest(deviceId);
    if (result case Err(:final failure)) {
      _log.warn('test notification failed', data: failure.kind.name);
    }
    return result;
  }

  Future<Result<void>> _register() async {
    final token = await _apnsToken?.call();
    return _api.register(
      deviceId,
      platform: platform,
      apnsToken: token,
      appVersion: appVersion,
      settings: _settings(),
    );
  }
}
