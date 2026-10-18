import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/automation/cron_repository.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;

  setUp(() => http = FakeHttp());

  DashboardCronRepository repo({String profile = 'default'}) {
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
      adapter: http,
    );
    addTearDown(connection.close);
    return DashboardCronRepository(connection.client, profile: profile);
  }

  group('CronJob.fromJsonOrNull', () {
    test('reads the real shape', () {
      final job = CronJob.fromJsonOrNull(
        Json.of({
          'id': 'j1',
          'name': 'Digest',
          'prompt': 'Summarise\nthe inbox',
          'enabled': true,
          'state': 'scheduled',
          'schedule': {
            'kind': 'cron',
            'expr': '0 7 * * *',
            'display': 'every day 7am',
          },
          'next_run_at': 1760684400,
          'last_error': null,
        }),
      )!;
      expect(job.title, 'Digest');
      expect(job.scheduleText, 'every day 7am');
      expect(job.schedule, '0 7 * * *');
      expect(job.state, CronState.active);
      expect(job.nextRun, isNotNull);
      expect(job.lastError, isNull);
    });

    test('a job with no name shows its prompt\'s first line', () {
      final job = CronJob.fromJsonOrNull(
        Json.of({
          'id': 'j2',
          'prompt': ' Check the logs \nthen post',
          'schedule': '30m',
        }),
      )!;
      expect(job.title, 'Check the logs');
      expect(job.scheduleText, '30m');
    });

    test('a job with neither name nor prompt shows its id', () {
      expect(CronJob.fromJsonOrNull(Json.of({'id': 'j3'}))!.title, 'j3');
    });

    test('a paused job and an unparseable date do not throw', () {
      final job = CronJob.fromJsonOrNull(
        Json.of({'id': 'j4', 'enabled': false, 'next_run_at': 'soon'}),
      )!;
      expect(job.state, CronState.paused);
      expect(job.nextRun, isNull);
    });

    test('a row with no id is dropped', () {
      expect(CronJob.fromJsonOrNull(Json.of({'name': 'x'})), isNull);
    });
  });

  group('JobDraft', () {
    test('create leaves unset optionals out', () {
      const draft = JobDraft(schedule: ' every 2h ', prompt: ' Do it ');
      expect(draft.toCreateBody(), {'schedule': 'every 2h', 'prompt': 'Do it'});
    });

    test('update clears a model that was reset to the default', () {
      const draft = JobDraft(schedule: '30m', prompt: 'x');
      // '' rather than null: ApiClient drops null fields from a body.
      expect(draft.toUpdateBody()['model'], '');
      expect(draft.toUpdateBody()['provider'], '');
    });

    test('update clears a delivery target set to Nowhere', () {
      // Hermes keeps a field the body leaves out, and reads '' as "local".
      const draft = JobDraft(schedule: '30m', prompt: 'x');
      expect(draft.toUpdateBody()['deliver'], '');
      const kept = JobDraft(schedule: '30m', prompt: 'x', deliver: 'telegram');
      expect(kept.toUpdateBody()['deliver'], 'telegram');
    });
  });

  group('DashboardCronRepository', () {
    test(
      'lists jobs for the default profile without a profile query',
      () async {
        http.on(
          'GET',
          '/api/cron/jobs',
          (_) => FakeReply.json({
            'jobs': [
              {'id': 'a', 'name': 'A'},
              {'name': 'no id'},
            ],
          }),
        );
        final jobs = (await repo().jobs()).valueOrNull!;
        expect(jobs.map((j) => j.id), ['a']);
        expect(http.requests.single.uri.queryParameters, isEmpty);
      },
    );

    test('scopes a named profile in the query', () async {
      http.on('GET', '/api/cron/jobs', (_) => FakeReply.json([]));
      await repo(profile: 'research').jobs();
      expect(http.requests.single.uri.queryParameters['profile'], 'research');
    });

    test('pause and resume use their own routes', () async {
      http.on(
        'POST',
        '/api/cron/jobs/a/pause',
        (_) => FakeReply.json({'id': 'a', 'enabled': false}),
      );
      http.on(
        'POST',
        '/api/cron/jobs/a/resume',
        (_) => FakeReply.json({
          'job': {'id': 'a', 'enabled': true},
        }),
      );
      final r = repo();
      expect(
        (await r.setEnabled('a', enabled: false)).valueOrNull!.enabled,
        isFalse,
      );
      expect(
        (await r.setEnabled('a', enabled: true)).valueOrNull!.enabled,
        isTrue,
      );
    });

    test('create posts the draft and returns the job', () async {
      http.on(
        'POST',
        '/api/cron/jobs',
        (_) => FakeReply.json({'id': 'new', 'name': 'N'}),
      );
      final result = await repo().create(
        const JobDraft(schedule: '30m', prompt: 'p', name: 'N'),
      );
      expect(result.valueOrNull!.id, 'new');
      expect(http.requests.single.data, {
        'schedule': '30m',
        'prompt': 'p',
        'name': 'N',
      });
    });

    test('an update sends the cleared model and delivery target', () async {
      http.on('PUT', '/api/cron/jobs/a', (_) => FakeReply.json({'id': 'a'}));
      await repo().update('a', const JobDraft(schedule: '30m', prompt: 'p'));
      expect(http.requests.single.data, {
        'schedule': '30m',
        'prompt': 'p',
        'name': '',
        'model': '',
        'provider': '',
        'deliver': '',
      });
    });

    test('a server rejection keeps its message', () async {
      http.on(
        'POST',
        '/api/cron/jobs',
        (_) => FakeReply.json({'detail': "Couldn't parse 'x'"}, status: 422),
      );
      final result = await repo().create(
        const JobDraft(schedule: 'x', prompt: 'p'),
      );
      expect(result.failureOrNull?.message, contains("Couldn't parse"));
    });

    test('runs reads sessions from a list or a runs key', () async {
      http.on(
        'GET',
        '/api/cron/jobs/a/runs',
        (_) => FakeReply.json({
          'runs': [
            {'id': 's1', 'title': 'Run 1', 'started_at': 1760684400},
          ],
        }),
      );
      final runs = (await repo().runs('a')).valueOrNull!;
      expect(runs.single.id, 's1');
      expect(http.requests.single.uri.queryParameters['limit'], '20');
    });

    test('an id is escaped in the path', () async {
      http.on(
        'DELETE',
        '/api/cron/jobs/a%20b',
        (_) => FakeReply.json({'ok': true}),
      );
      expect((await repo().delete('a b')).isOk, isTrue);
    });

    test('a missing route is a not-found failure', () async {
      expect((await repo().jobs()).failureOrNull?.kind.name, 'notFound');
    });
  });
}
