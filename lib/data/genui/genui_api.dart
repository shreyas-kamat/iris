/// The hermes-iris plugin's routes (`/api/plugins/iris/...`). Every route takes `?profile=`; the default profile is
/// left out, as the other repositories do.
library;

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/result.dart';
import '../net/api_client.dart';
import 'genui_models.dart';
import 'personal_models.dart';
import 'signals.dart';

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

  /// The work profile: proposed by a study or kept by the person. Ok(null) when there is none yet.
  Future<Result<WorkProfile?>> workProfile();

  /// Changes the profile; only the fields given are sent, and the plugin merges them onto what it holds.
  Future<Result<WorkProfile>> saveWorkProfile({
    String? summary,
    List<String>? chips,
    PersonalStatus? status,
  });

  /// Every template with its program and sample, optionally only those with [status].
  Future<Result<List<UiTemplate>>> templates({PersonalStatus? status});

  /// Changes a template (approve, rename, retire, edit); only the fields given are sent.
  Future<Result<UiTemplate>> saveTemplate(
    String id, {
    String? name,
    String? when,
    PersonalStatus? status,
    TemplateKind? kind,
  });

  /// The person's answer to a change waiting beside a kept template: apply it (or retire, for a retire suggestion) or
  /// discard it. Answers the template as it now stands.
  Future<Result<UiTemplate>> decideProposal(String id, {required bool apply});

  Future<Result<void>> deleteTemplate(String id);

  /// Reports what the person did with displays. Ids and signal names only; best effort.
  Future<Result<void>> sendSignals(List<SignalEvent> signals);
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

  @override
  Future<Result<WorkProfile?>> workProfile() async => (await _client.get(
    '$_base/profile',
    query: _query,
  )).map((body) => WorkProfile.fromJsonOrNull(body['profile']));

  @override
  Future<Result<WorkProfile>> saveWorkProfile({
    String? summary,
    List<String>? chips,
    PersonalStatus? status,
  }) async =>
      (await _client.put(
        '$_base/profile',
        query: _query,
        body: {'summary': ?summary, 'chips': ?chips, 'status': ?status?.wire},
      )).flatMap((body) {
        final profile = WorkProfile.fromJsonOrNull(body['profile']);
        return profile == null
            ? const Err(
                IrisFailure.malformed(message: 'No profile in the response'),
              )
            : Ok(profile);
      });

  @override
  Future<Result<List<UiTemplate>>> templates({PersonalStatus? status}) async =>
      (await _client.get(
        '$_base/templates',
        query: {...?_query, 'status': ?status?.wire},
      )).map(
        (body) => [
          for (final row in body['templates'].list)
            ?UiTemplate.fromJsonOrNull(row),
        ],
      );

  @override
  Future<Result<UiTemplate>> saveTemplate(
    String id, {
    String? name,
    String? when,
    PersonalStatus? status,
    TemplateKind? kind,
  }) async => (await _client.put(
    '$_base/templates/${_part(id)}',
    query: _query,
    body: {
      'name': ?name,
      'when': ?when,
      'status': ?status?.wire,
      'kind': ?kind?.wire,
    },
  )).flatMap(_template);

  @override
  Future<Result<UiTemplate>> decideProposal(
    String id, {
    required bool apply,
  }) async => (await _client.put(
    '$_base/templates/${_part(id)}',
    query: _query,
    body: {'proposal': apply ? 'apply' : 'discard'},
  )).flatMap(_template);

  static Result<UiTemplate> _template(Json body) {
    final template = UiTemplate.fromJsonOrNull(body['template']);
    return template == null
        ? const Err(
            IrisFailure.malformed(message: 'No template in the response'),
          )
        : Ok(template);
  }

  @override
  Future<Result<void>> deleteTemplate(String id) async => (await _client.delete(
    '$_base/templates/${_part(id)}',
    query: _query,
  )).map((_) {});

  @override
  Future<Result<void>> sendSignals(List<SignalEvent> signals) async =>
      (await _client.post(
        '$_base/feedback',
        query: _query,
        body: {
          'signals': [for (final signal in signals) signal.toJson()],
        },
      )).map((_) {});
}
