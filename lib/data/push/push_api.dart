/// The hermes-iris plugin's push routes (`/api/plugins/iris/push/...`). Every route takes `?profile=`; the default
/// profile is left out, as the other repositories do.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../net/api_client.dart';
import 'push_models.dart';

abstract interface class PushApi {
  /// Registers this install, or refreshes it. [apnsToken] is for an iPhone only; Android gets its notices over a
  /// stream it holds open. The server never sends the token back.
  Future<Result<void>> register(
    String deviceId, {
    required String platform,
    String? apnsToken,
    required String appVersion,
    required PushSettings settings,
  });

  /// Replaces the device's settings with [settings].
  Future<Result<void>> updateSettings(String deviceId, PushSettings settings);

  Future<Result<void>> unregister(String deviceId);

  /// Tells the server the person just sent to [storedSessionId]: the next finished turn there is worth a notification.
  /// The **stored** id, the only one the plugin's hooks see.
  Future<Result<void>> markActive(String storedSessionId);

  /// Asks the server to send one test notification to an iPhone. An Err when it could not be delivered.
  Future<Result<void>> sendTest(String deviceId);
}

final class DashboardPushApi implements PushApi {
  DashboardPushApi(this._client, {this.profile = 'default'});

  final ApiClient _client;
  final String profile;

  static const _base = '/api/plugins/iris/push';

  Map<String, Object?>? get _query =>
      profile == 'default' ? null : {'profile': profile};

  static String _part(String id) => Uri.encodeComponent(id);

  @override
  Future<Result<void>> register(
    String deviceId, {
    required String platform,
    String? apnsToken,
    required String appVersion,
    required PushSettings settings,
  }) async => (await _client.put(
    '$_base/devices/${_part(deviceId)}',
    query: _query,
    body: {
      'platform': platform,
      'apns_token': ?apnsToken,
      'app_version': appVersion,
      'settings': settings.toJson(),
    },
  )).map((_) {});

  @override
  Future<Result<void>> updateSettings(
    String deviceId,
    PushSettings settings,
  ) async => (await _client.patch(
    '$_base/devices/${_part(deviceId)}/settings',
    query: _query,
    body: settings.toJson(),
  )).map((_) {});

  @override
  Future<Result<void>> unregister(String deviceId) async =>
      (await _client.delete(
        '$_base/devices/${_part(deviceId)}',
        query: _query,
      )).map((_) {});

  @override
  Future<Result<void>> markActive(String storedSessionId) async =>
      (await _client.post(
        '$_base/active/${_part(storedSessionId)}',
        query: _query,
      )).map((_) {});

  @override
  Future<Result<void>> sendTest(String deviceId) async =>
      (await _client.post(
        '$_base/test/${_part(deviceId)}',
        query: _query,
      )).flatMap(
        (body) => body['ok'].boolOrNull == true
            ? const Ok(null)
            : Err(
                IrisFailure.malformed(
                  message:
                      'The server could not deliver the test notification.',
                  endpoint: '$_base/test',
                ),
              ),
      );
}
