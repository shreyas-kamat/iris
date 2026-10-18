/// Writes to the real server: a throwaway profile, a job in it, a task.
///   flutter test --tags live --run-skipped test/live/phase7_write_live_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/automation/cron_repository.dart';
import 'package:iris/data/automation/kanban_models.dart';
import 'package:iris/data/automation/kanban_repository.dart';
import 'package:iris/data/automation/profile_repository.dart';
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

  test(
    'profile, job and task round trip',
    () async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = 'iris-p7-$stamp';
      final renamed = 'iris-p7r-$stamp';
      final profiles = DashboardProfileRepository(api);
      final kanban = DashboardKanbanRepository(api);

      // Profile: create, read the SOUL, rename, write the SOUL.
      expect(
        (await profiles.create(ProfileDraft(name: name, soul: '# Probe'))).isOk,
        isTrue,
      );
      addTearDown(() async {
        // Whatever happened below, the throwaway profile goes.
        await profiles.delete(renamed);
        await profiles.delete(name);
      });
      // The live server ignores `soul` on create (found by this test), so the
      // app writes it afterwards, as here.
      expect((await profiles.setSoul(name, '# Probe')).isOk, isTrue);
      expect((await profiles.soul(name)).valueOrNull, contains('Probe'));
      expect((await profiles.rename(name, renamed)).isOk, isTrue);
      expect((await profiles.setSoul(renamed, '# Probe 2')).isOk, isTrue);

      // A job in that profile: create, pause, resume, run, delete.
      final cron = DashboardCronRepository(api, profile: renamed);
      final job = (await cron.create(
        const JobDraft(
          schedule: 'every 6h',
          prompt: 'Reply with the word: ok',
          name: 'Iris probe',
        ),
      )).valueOrNull;
      expect(job, isNotNull);
      expect(
        (await cron.setEnabled(job!.id, enabled: false)).valueOrNull!.enabled,
        isFalse,
      );
      expect(
        (await cron.setEnabled(job.id, enabled: true)).valueOrNull!.enabled,
        isTrue,
      );
      expect((await cron.trigger(job.id)).isOk, isTrue);
      // Replies are slow (about 2.5 minutes): wait for the run to appear.
      var runs = (await cron.runs(job.id)).valueOrNull ?? const [];
      for (var i = 0; i < 24 && runs.isEmpty; i++) {
        await Future<void>.delayed(const Duration(seconds: 10));
        runs = (await cron.runs(job.id)).valueOrNull ?? const [];
      }
      expect(runs, isNotEmpty, reason: 'the triggered run never appeared');
      expect((await cron.delete(job.id)).isOk, isTrue);

      // A task: create in Triage, move to To do. There is no delete route in
      // scope, so the task stays; it is named so it can be cleared by hand.
      final task = (await kanban.create(
        TaskDraft(title: 'Iris probe $stamp'),
      )).valueOrNull;
      if (task != null) {
        expect((await kanban.move(task.id, 'todo')).isOk, isTrue);
        final board = (await kanban.board()).valueOrNull!;
        expect(board.task(task.id)?.status, 'todo');
      }

      // The teardown deletes the profile; check that it really goes.
      expect((await profiles.delete(renamed)).isOk, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
