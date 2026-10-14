/// Phase 4's writes against a real dashboard: steer a turn, retry, rename,
/// archive and unarchive, and see which event carries the context window.
///
/// It creates a conversation on the server and runs a real turn, so it runs
/// only when asked for:
///   flutter test --tags live_write --run-skipped test/live/phase4_write_live_test.dart
/// Prints event kinds and result shapes only, never content.
@Tags(['live_write'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

void main() {
  test(
    'steer, retry, rename, archive and context on a throwaway chat',
    () async {
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
      final session = DashboardSession(http: connection);
      final chat = DashboardChat(session);
      addTearDown(() async {
        await chat.dispose();
        await session.dispose();
        connection.close();
      });
      await session.start();
      expect(session.state.phase, LinkPhase.live);

      final created = (await chat.create()).valueOrNull!;
      final runtimeId = created.runtimeId;
      final storedId = created.storedId;

      final firstDelta = Completer<void>();
      var turns = 0;
      var completed = Completer<void>();
      final contextFrom = <String>{};
      final subscription = chat.events
          .where((event) => event.sessionId == runtimeId)
          .listen((event) {
            switch (event) {
              case TextDelta() when !firstDelta.isCompleted:
                firstDelta.complete();
              case ContextChanged(:final usage):
                contextFrom.add('${usage.percent.round()}%');
              case MessageCompleted() || BusyChanged(busy: false):
                if (!completed.isCompleted) completed.complete();
              default:
                break;
            }
            if (event is MessageStarted) turns++;
          });
      addTearDown(subscription.cancel);

      // 1. A turn, steered once text starts arriving.
      final sent = await chat.submit(
        runtimeId,
        'Count slowly from 1 to 30, one number per line, then say done.',
      );
      expect(sent.isOk, isTrue, reason: '${sent.failureOrNull}');
      await firstDelta.future.timeout(const Duration(minutes: 4));
      final steer = await chat.steer(runtimeId, 'Stop at 10.');
      stdout.writeln('steer: ${steer.valueOrNull ?? steer.failureOrNull?.kind}');
      await completed.future.timeout(const Duration(minutes: 4));
      stdout.writeln('context events: $contextFrom, turns started: $turns');

      // 2. Retry: what does slash.exec answer for /retry?
      completed = Completer<void>();
      final retry = await chat.runSlash(runtimeId, '/retry');
      stdout.writeln(
        'retry: ${retry.valueOrNull?.kind} '
        'text empty: ${retry.valueOrNull?.text.isEmpty} '
        'err: ${retry.failureOrNull?.kind}',
      );
      if (retry.valueOrNull != null) {
        await completed.future
            .timeout(const Duration(minutes: 4))
            .catchError((Object _) {});
      }

      // 3. Rename, then archive and unarchive.
      expect((await chat.rename(storedId, 'Iris phase 4 live check')).isOk, isTrue);
      var listed = (await chat.conversations(0)).valueOrNull!;
      stdout.writeln(
        'renamed visible: ${listed.items.any((c) => c.id == storedId && c.title == 'Iris phase 4 live check')}',
      );

      expect((await chat.setArchived(storedId, archived: true)).isOk, isTrue);
      listed = (await chat.conversations(0)).valueOrNull!;
      final archived = (await chat.archivedConversations(0)).valueOrNull!;
      stdout.writeln(
        'archived: hidden from list ${!listed.items.any((c) => c.id == storedId)}, '
        'in archived ${archived.items.any((c) => c.id == storedId)}',
      );

      expect((await chat.setArchived(storedId, archived: false)).isOk, isTrue);
      listed = (await chat.conversations(0)).valueOrNull!;
      stdout.writeln(
        'unarchived: back in list ${listed.items.any((c) => c.id == storedId)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
