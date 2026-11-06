/// The hermes-iris plugin's routes (`/api/plugins/iris/...`). Every route takes `?profile=`; the default profile is
/// left out, as the other repositories do.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../net/api_client.dart';
import 'genui_models.dart';

abstract interface class GenUiApi {
  Future<Result<GenUiCapabilities>> capabilities();

  /// Turns generated displays on for a session. [sessionId] is the **stored** id: it is the only id the plugin's hooks
  /// see. Idempotent, so it is safe to send again after every reconnect.
  Future<Result<void>> flagSession(String sessionId);
  Future<Result<void>> unflagSession(String sessionId);

  /// A summary of every display in a session (no programs).
  Future<Result<List<UiSurface>>> surfaces(String sessionId);

  /// One display with its program.
  Future<Result<UiSurface>> surface(String sessionId, String surfaceId);
}

final class DashboardGenUiApi implements GenUiApi {
  DashboardGenUiApi(this._client, {this.profile = 'default'});

  final ApiClient _client;
  final String profile;

  static const _base = '/api/plugins/iris';

  Map<String, Object?>? get _query =>
      profile == 'default' ? null : {'profile': profile};

  static String _part(String id) => Uri.encodeComponent(id);

  @override
  Future<Result<GenUiCapabilities>> capabilities() async =>
      (await _client.get('$_base/capabilities', query: _query)).flatMap((body) {
        final capabilities = GenUiCapabilities.fromJsonOrNull(body);
        return capabilities == null
            ? const Err(
                IrisFailure.malformed(
                  message: 'No capabilities in the response',
                ),
              )
            : Ok(capabilities);
      });

  @override
  Future<Result<void>> flagSession(String sessionId) async =>
      (await _client.post(
        '$_base/sessions/${_part(sessionId)}/genui',
        query: _query,
      )).map((_) {});

  @override
  Future<Result<void>> unflagSession(String sessionId) async =>
      (await _client.delete(
        '$_base/sessions/${_part(sessionId)}/genui',
        query: _query,
      )).map((_) {});

  @override
  Future<Result<List<UiSurface>>> surfaces(String sessionId) async =>
      (await _client.get(
        '$_base/surfaces/${_part(sessionId)}',
        query: _query,
      )).map(
        (body) => [
          for (final row in body['surfaces'].list)
            ?UiSurface.fromJsonOrNull(row),
        ],
      );

  @override
  Future<Result<UiSurface>> surface(String sessionId, String surfaceId) async =>
      (await _client.get(
        '$_base/surfaces/${_part(sessionId)}/${_part(surfaceId)}',
        query: _query,
      )).flatMap((body) {
        final surface = UiSurface.fromJsonOrNull(body['surface']);
        return surface == null
            ? const Err(
                IrisFailure.malformed(message: 'No display in the response'),
              )
            : Ok(surface);
      });
}
