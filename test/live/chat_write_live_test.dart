/// Sends one real prompt and watches the reply stream back.
///
/// It creates a conversation on the server, so it runs only when asked for:
///   flutter test --tags live_write --run-skipped test/live/chat_write_live_test.dart
/// Prints event kinds only, never content.
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
    'a prompt streams a reply',
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
      final kinds = <String>{};
      final reply = StringBuffer();
      final done = Completer<void>();
      final subscription = chat.events
          .where((event) => event.sessionId == created.runtimeId)
          .listen((event) {
            kinds.add(event.runtimeType.toString());
            switch (event) {
              case TextDelta(:final text):
                reply.write(text);
              case MessageCompleted(:final content):
                if (reply.isEmpty) reply.write(content ?? '');
                if (!done.isCompleted) done.complete();
              case BusyChanged(busy: false) when reply.isNotEmpty:
                if (!done.isCompleted) done.complete();
              case TurnFailed(:final message):
                if (!done.isCompleted) done.completeError(message);
              default:
                break;
            }
          });
      addTearDown(subscription.cancel);

      final sent = await chat.submit(
        created.runtimeId,
        'Reply with exactly the word: pong',
      );
      expect(sent.isOk, isTrue, reason: '${sent.failureOrNull}');
      // This agent took 158 s to answer "pong" on 2026-10-13, streaming
      // nothing until the end, so the wait is generous.
      await done.future.timeout(const Duration(seconds: 240));
      stdout.writeln('event kinds: $kinds');
      expect(reply.toString().toLowerCase(), contains('pong'));
    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}
