/// Which Phase 6 methods the user's Hermes has. Read-only: every call uses an
/// id that does not exist, so a present method answers with an error about the
/// id and a missing one answers "unknown method".
///   flutter test --tags live --run-skipped test/live/phase6_probe_live_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

void main() {
  late DashboardSession session;

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
  });

  const probes = <String, Map<String, Object?>>{
    'session.undo': {'session_id': 'iris-probe'},
    'session.branch_stored': {'parent_session_id': 'iris-probe'},
    'session.compress': {'session_id': 'iris-probe'},
    'session.active_list': {},
    'connection.respond': {
      'owner': {'type': 'session', 'session_id': 'iris-probe'},
      'op_id': 'iris-probe',
      'result': {},
    },
    'config.set busy': {'key': 'busy', 'value': 'status'},
    'config.set reasoning': {
      'key': 'reasoning',
      'session_id': 'iris-probe',
      'value': 'medium',
    },
    'config.set fast': {
      'key': 'fast',
      'session_id': 'iris-probe',
      'value': 'normal',
    },
  };

  test('which Phase 6 methods exist', () async {
    final lines = <String>[];
    for (final entry in probes.entries) {
      final method = entry.key.split(' ').first;
      final result = await session.call(method, params: entry.value);
      final line = switch (result) {
        _ when result.isOk => '${entry.key}: present (answered)',
        _ when result.failureOrNull?.rpcError?.isMethodNotFound ?? false =>
          '${entry.key}: MISSING',
        _ => '${entry.key}: present '
            '(${result.failureOrNull?.rpcError?.code ?? result.failureOrNull?.kind.name})',
      };
      lines.add(line);
      // ignore: avoid_print
      print(line);
    }
    // The probe's job is the printout; it only fails if nothing answered.
    expect(lines, hasLength(probes.length));
  });
}
