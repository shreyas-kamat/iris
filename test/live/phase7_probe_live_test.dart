/// What the user's Hermes has for Phase 7. Read-only: writes use ids or names
/// that cannot exist, so a present route answers with an error about the id
/// and a missing route answers a bare 404.
///   flutter test --tags live --run-skipped test/live/phase7_probe_live_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/net/api_client.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

void main() {
  late DashboardSession session;
  late ApiClient api;

  setUp(() async {
    final json = Json.decode(
      File(
        '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
        '/.iris-live.json',
      ).readAsStringSync(),
    );
    final connection = ServerConnection.create(
      ServerConfig(
        id: 'live',
        baseUrl: ServerConfig.normaliseBaseUrl(json['base_url'].string()),
        label: 'live',
      ),
      secrets: ServerSecrets(
        username: json['username'].stringOrNull,
        password: json['password'].stringOrNull,
        accessClientId: json['cf_client_id'].stringOrNull,
        accessClientSecret: json['cf_client_secret'].stringOrNull,
      ),
    );
    session = DashboardSession(http: connection);
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
    await session.start();
    expect(session.state.phase, LinkPhase.live);
    api = connection.client;
  });

  String describe(Result<Json> result) => switch (result) {
    Ok(:final value) => 'ok ${_shape(value)}',
    Err(:final failure) =>
      '${failure.kind.name} ${failure.statusCode ?? ''} '
          '"${failure.message ?? ''}"',
  };

  test('what Phase 7 can use', () async {
    final lines = <String>[];
    Future<Result<Json>> probe(String label, Future<Result<Json>> call) async {
      final result = await call;
      lines.add('$label: ${describe(result)}');
      return result;
    }

    await probe('GET cron jobs', api.get('/api/cron/jobs'));
    await probe('GET delivery targets', api.get('/api/cron/delivery-targets'));
    await probe(
      'PUT cron job (bogus id)',
      api.put('/api/cron/jobs/iris-probe', body: {'enabled': true}),
    );
    await probe(
      'POST cron pause (bogus id)',
      api.post('/api/cron/jobs/iris-probe/pause'),
    );
    await probe(
      'POST cron resume (bogus id)',
      api.post('/api/cron/jobs/iris-probe/resume'),
    );
    await probe(
      'POST cron trigger (bogus id)',
      api.post('/api/cron/jobs/iris-probe/trigger'),
    );
    await probe(
      'GET cron runs (bogus id)',
      api.get('/api/cron/jobs/iris-probe/runs', query: {'limit': 5}),
    );
    await probe(
      'DELETE cron job (bogus id)',
      api.delete('/api/cron/jobs/iris-probe'),
    );

    final board = await probe(
      'GET kanban board',
      api.get('/api/plugins/kanban/board'),
    );
    final firstId = board.valueOrNull == null
        ? null
        : _firstTaskId(board.valueOrNull!);
    if (firstId != null) {
      final detail = await api.get('/api/plugins/kanban/tasks/$firstId');
      lines.add(
        'GET kanban task detail keys: '
        '${detail.valueOrNull == null ? describe(detail) : _keys(detail.valueOrNull!)} '
        'task keys: ${detail.valueOrNull == null ? '' : _keys(detail.valueOrNull!['task'])}',
      );
    } else {
      lines.add('GET kanban task detail: no task on the board to read');
    }
    await probe(
      'PATCH kanban task (bogus id)',
      api.patch(
        '/api/plugins/kanban/tasks/iris-probe',
        body: {'status': 'todo'},
      ),
    );

    await probe('GET profiles', api.get('/api/profiles'));
    await probe(
      'POST profile (invalid name)',
      api.post('/api/profiles', body: {'name': 'Bad Name!'}),
    );
    await probe(
      'POST profile (invalid name, clone_from)',
      api.post(
        '/api/profiles',
        body: {'name': 'Bad Name!', 'clone_from': 'default'},
      ),
    );
    await probe(
      'POST profile (invalid name, clone_all)',
      api.post(
        '/api/profiles',
        body: {'name': 'Bad Name!', 'clone_from': 'default', 'clone_all': true},
      ),
    );
    await probe(
      'POST profile (invalid name, no_skills)',
      api.post('/api/profiles', body: {'name': 'Bad Name!', 'no_skills': true}),
    );
    await probe(
      'PATCH profile (bogus name)',
      api.patch('/api/profiles/iris-probe', body: {'new_name': 'iris-probe-2'}),
    );
    await probe(
      'GET profile soul (default)',
      api.get('/api/profiles/default/soul'),
    );
    await probe(
      'DELETE profile (bogus name)',
      api.delete('/api/profiles/iris-probe'),
    );

    final unscoped = await probe(
      'GET search, no profile',
      api.get('/api/sessions/search', query: {'q': 'the', 'limit': 5}),
    );
    await probe(
      'GET search, profile=default',
      api.get(
        '/api/sessions/search',
        query: {'q': 'the', 'limit': 5, 'profile': 'default'},
      ),
    );
    if (unscoped.valueOrNull != null) {
      final rows = _rows(unscoped.valueOrNull!, 'results');
      lines.add(
        'search hit keys: ${rows.isEmpty ? '(none)' : _keys(rows.first)}; '
        'profiles seen: ${rows.map((r) => r['profile'].stringOrNull).toSet()}',
      );
    }

    // ignore: avoid_print
    print('\n${lines.join('\n')}\n');
  });
}

String _shape(Json value) {
  if (value.isList) return 'list(${value.list.length})';
  return 'object{${_keys(value)}}';
}

String _keys(Json value) {
  final raw = value.raw;
  return raw is Map ? raw.keys.join(',') : '(not an object)';
}

List<Json> _rows(Json body, String key) =>
    body.isList ? body.list : body[key].list;

String? _firstTaskId(Json board) {
  for (final column in board['columns'].list) {
    final tasks = column['tasks'].list;
    if (tasks.isNotEmpty) return tasks.first['id'].stringOrNull;
  }
  return null;
}
