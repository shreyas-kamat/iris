/// The transport against a real dashboard.
///
/// Reads its target and secrets from `~/.iris-live.json`, outside the
/// repository, so nothing secret can be committed. Prints only shapes — event
/// types, response keys, the version — never content: the server holds real
/// conversations.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/dashboard_auth.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

File get _configFile => File(
  '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
  '/.iris-live.json',
);

void main() {
  late ServerConfig config;
  late ServerSecrets secrets;

  setUpAll(() {
    final json = Json.decode(_configFile.readAsStringSync());
    config = ServerConfig(
      id: 'live',
      baseUrl: ServerConfig.normaliseBaseUrl(json['base_url'].string()),
      label: 'live',
    );
    secrets = ServerSecrets(
      username: json['username'].stringOrNull,
      password: json['password'].stringOrNull,
      accessClientId: json['cf_client_id'].stringOrNull,
      accessClientSecret: json['cf_client_secret'].stringOrNull,
    );
  });

  test('the dashboard is found behind its access proxy', () async {
    final connection = ServerConnection.create(config, secrets: secrets);
    addTearDown(connection.close);
    final probe = await connection.auth.probe();
    stdout.writeln('probe: ${probe.access.name}, version ${probe.version}');
    expect(
      probe.access,
      anyOf(DashboardAccess.password, DashboardAccess.open),
      reason: '${probe.failure}',
    );
  });

  test(
    'a live link opens, answers ping, and streams',
    () async {
      final connection = ServerConnection.create(config, secrets: secrets);
      final session = DashboardSession(http: connection);
      final types = <String>{};
      final subscription = session.events.listen((e) => types.add(e.type));
      addTearDown(() async {
        await subscription.cancel();
        await session.dispose();
        connection.close();
      });

      await session.start();
      expect(session.state.phase, LinkPhase.live, reason: '${session.state}');

      final ping = await session.call(
        'ping',
        timeout: const Duration(seconds: 10),
      );
      expect(
        ping.isOk || (ping.failureOrNull?.rpcError?.isMethodNotFound ?? false),
        isTrue,
        reason: '$ping',
      );

      final catalog = await session.call('commands.catalog');
      stdout.writeln(
        'commands.catalog: ${catalog.valueOrNull?.keys ?? catalog.failureOrNull}',
      );

      await Future<void>.delayed(const Duration(seconds: 3));
      stdout.writeln('event types seen: $types');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'conversations and a stored transcript read cleanly',
    () async {
      final connection = ServerConnection.create(config, secrets: secrets);
      final session = DashboardSession(http: connection);
      final chat = DashboardChat(session);
      addTearDown(() async {
        await chat.dispose();
        await session.dispose();
        connection.close();
      });
      await session.start();
      final conversations = await chat.conversations();
      expect(
        conversations.isOk,
        isTrue,
        reason: '${conversations.failureOrNull}',
      );
      final list = conversations.valueOrNull!;
      stdout.writeln('conversations: ${list.length}');
      if (list.isEmpty) return;
      final history = await chat.history(list.first.id);
      expect(history.isOk, isTrue, reason: '${history.failureOrNull}');
      final counts = <String, int>{};
      for (final item in history.valueOrNull!) {
        counts.update(
          item.runtimeType.toString(),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      stdout.writeln('newest transcript, by kind: $counts');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
