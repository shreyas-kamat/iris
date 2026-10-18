/// Scheduled jobs: list, pause and resume, run now, past runs, create, edit,
/// delete.
library;

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/result.dart';
import '../chat/chat_models.dart';
import '../chat/history_parser.dart';
import '../net/api_client.dart';
import 'cron_models.dart';

abstract interface class CronRepository {
  Future<Result<List<CronJob>>> jobs();
  Future<Result<CronJob>> job(String id);

  /// Past runs, newest first. Each run is a stored chat.
  Future<Result<List<ConversationSummary>>> runs(String id, {int limit = 20});
  Future<Result<List<DeliveryTarget>>> deliveryTargets();
  Future<Result<CronJob>> create(JobDraft draft);
  Future<Result<CronJob>> update(String id, JobDraft draft);

  /// Pauses (`enabled: false`) or resumes a job.
  Future<Result<CronJob>> setEnabled(String id, {required bool enabled});

  /// Runs the job now. The run shows up in [runs] on the next refresh.
  Future<Result<void>> trigger(String id);
  Future<Result<void>> delete(String id);
}

final class DashboardCronRepository implements CronRepository {
  DashboardCronRepository(this._client, {this.profile = 'default'});

  final ApiClient _client;
  final String profile;

  /// A trigger can hold the connection while the server starts the run.
  static const triggerTimeout = Duration(seconds: 120);

  Map<String, Object?>? get _query =>
      profile == 'default' ? null : {'profile': profile};

  static String _path(String id, [String suffix = '']) =>
      '/api/cron/jobs/${Uri.encodeComponent(id)}$suffix';

  /// A write answers with the job, or `{job: {...}}`.
  static CronJob? _jobFrom(Json body) {
    final inner = body['job'];
    return CronJob.fromJsonOrNull(inner.isMap ? inner : body);
  }

  Result<CronJob> _asJob(Result<Json> result) => result.flatMap((body) {
    final job = _jobFrom(body);
    return job == null
        ? const Err(IrisFailure.malformed(message: 'No job in the response'))
        : Ok(job);
  });

  @override
  Future<Result<List<CronJob>>> jobs() async =>
      (await _client.get('/api/cron/jobs', query: _query)).map((body) {
        final rows = body.isList ? body.list : body['jobs'].list;
        return [for (final row in rows) ?CronJob.fromJsonOrNull(row)];
      });

  @override
  Future<Result<CronJob>> job(String id) async =>
      _asJob(await _client.get(_path(id), query: _query));

  @override
  Future<Result<List<ConversationSummary>>> runs(
    String id, {
    int limit = 20,
  }) async => (await _client.get(
    _path(id, '/runs'),
    query: {...?_query, 'limit': limit},
  )).map((body) {
    final rows = body.isList ? body : body['runs'];
    return HistoryParser.conversations(rows);
  });

  @override
  Future<Result<List<DeliveryTarget>>> deliveryTargets() async =>
      (await _client.get('/api/cron/delivery-targets')).map((body) {
        final rows = body.isList ? body.list : body['targets'].list;
        return [for (final row in rows) ?DeliveryTarget.fromJsonOrNull(row)];
      });

  @override
  Future<Result<CronJob>> create(JobDraft draft) async => _asJob(
    await _client.post(
      '/api/cron/jobs',
      body: draft.toCreateBody(),
      query: _query,
    ),
  );

  @override
  Future<Result<CronJob>> update(String id, JobDraft draft) async => _asJob(
    await _client.put(_path(id), body: draft.toUpdateBody(), query: _query),
  );

  @override
  Future<Result<CronJob>> setEnabled(
    String id, {
    required bool enabled,
  }) async => _asJob(
    await _client.post(_path(id, enabled ? '/resume' : '/pause'), query: _query),
  );

  @override
  Future<Result<void>> trigger(String id) async => (await _client.post(
    _path(id, '/trigger'),
    query: _query,
    receiveTimeout: triggerTimeout,
  )).map((_) {});

  @override
  Future<Result<void>> delete(String id) async =>
      (await _client.delete(_path(id), query: _query)).map((_) {});
}
