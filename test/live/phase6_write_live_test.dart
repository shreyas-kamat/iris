/// Phase 6's write calls against a real dashboard: busy mode, a queued
/// submit, undo, branch, active sessions and delete, all on a throwaway chat.
///
/// It creates conversations on the server, so it runs only when asked for:
///   flutter test --tags live_write --run-skipped test/live/phase6_write_live_test.dart
/// Replies are slow (about 95-160 s), so each turn waits up to 300 s.
/// Prints result shapes only, never content.
@Tags(['live_write'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

void main() {
  late DashboardSession session;
  late DashboardChat chat;
  late ServerConnection connection;

  setUp(() async {
    final json = Json.decode(
      File(
        '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
        '/.iris-live.json',
      ).readAsStringSync(),
    );
    connection = ServerConnection.create(
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
    chat = DashboardChat(session);
    addTearDown(() async {
      try {
        await chat.dispose();
        await session.dispose();
      } on Object {
        // already disposed by the cleanup step
      }
      connection.close();
    });
    await session.start();
    expect(session.state.phase, LinkPhase.live);
  });

  test(
    'busy mode, queue, undo, branch and delete on a throwaway chat',
    () async {
      final made = <String>[];
      final done = <String, int>{};
      final sub = chat.events.listen((e) {
        if (e is MessageCompleted || e is TurnFailed) {
          done[e.sessionId] = (done[e.sessionId] ?? 0) + 1;
        }
      });
      addTearDown(sub.cancel);

      Future<void> turns(String runtimeId, int count) async {
        final stop = DateTime.now().add(const Duration(seconds: 300));
        while ((done[runtimeId] ?? 0) < count) {
          if (DateTime.now().isAfter(stop)) {
            fail('timed out waiting for turn $count');
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      void log(String line) => print(line); // ignore: avoid_print

      // 1. create + a first turn
      final created = (await chat.create()).valueOrNull!;
      made.add(created.storedId);
      unawaited(
        chat.submit(created.runtimeId, 'Reply with exactly the word: pong'),
      );
      await turns(created.runtimeId, 1);
      log('first turn -> done');

      // 2. busy mode round trip (restores the original value)
      final original = (await chat.busyMode()).valueOrNull;
      log('busy mode -> ${original?.wire ?? 'unsupported'}');
      if (original != null) {
        expect((await chat.setBusyMode(BusyMode.queue)).isOk, isTrue);
        expect((await chat.busyMode()).valueOrNull, BusyMode.queue);
        await chat.setBusyMode(original);
      }

      // 3. queued submit while a turn runs: held by Hermes
      unawaited(
        chat.submit(created.runtimeId, 'Reply with exactly the word: ping'),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      final queued = await chat.submit(
        created.runtimeId,
        'Reply with exactly the word: again',
        queued: true,
      );
      log(
        'queued submit -> ${queued.valueOrNull?.name ?? 'failed: ${queued.failureOrNull?.message}'}',
      );
      await turns(created.runtimeId, queued.isOk ? 3 : 2);

      // 4. undo removes the last exchange
      final undone = await chat.undo(created.runtimeId);
      log(
        'undo -> ${undone.isOk ? 'removed ${undone.valueOrNull}' : 'failed: ${undone.failureOrNull?.message}'}',
      );
      if (undone.isOk) expect(undone.valueOrNull, greaterThan(0));

      // 5. branch the whole chat
      final branched = await chat.branchWhole(created.storedId);
      log(
        'branchWhole -> ${branched.isOk ? 'ok' : 'failed: ${branched.failureOrNull?.message}'}',
      );
      if (branched.isOk) {
        final child = branched.valueOrNull!;
        made.add(child.storedId);
        expect(child.storedId, isNot(created.storedId));
        final live = await chat.activeSessions();
        log('active sessions -> ${live.valueOrNull?.length ?? 'unsupported'}');
      }

      // 6. delete is refused while live
      final refused = await chat.delete(created.storedId);
      log(
        'delete while live -> ${refused.isOk ? 'accepted' : 'refused: ${refused.failureOrNull?.statusCode}'}',
      );

      // 7. cleanup: drop the socket so nothing is live, then delete everything
      await chat.dispose();
      await session.dispose();
      await Future<void>.delayed(const Duration(seconds: 3));
      for (final id in made) {
        final gone = await chat.delete(id);
        log(
          'cleanup -> ${gone.isOk ? 'deleted' : 'LEFTOVER: ${gone.failureOrNull?.message}'}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
