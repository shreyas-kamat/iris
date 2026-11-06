/// GenUI plan 2.12: the real `hermes-iris` plugin on the user's Hermes.
/// Needs the plugin installed and enabled. One throwaway conversation, ten
/// turns (up to ~30 minutes), deleted at the end.
///   flutter test --tags live --run-skipped test/live/genui_plugin_live_test.dart
/// Prints counts, ids and error lines only; the programs go to
/// `<system temp>/iris-genui-plugin/`, never into the repo.
// Prompts are long strings.
// ignore_for_file: no_adjacent_strings_in_list
@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

const _base = '/api/plugins/iris';

Json _live() => Json.decode(
  File(
    '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
    '/.iris-live.json',
  ).readAsStringSync(),
);

ServerConnection _connect({required bool login}) {
  final json = _live();
  return ServerConnection.create(
    ServerConfig(
      id: 'live',
      baseUrl: ServerConfig.normaliseBaseUrl(json['base_url'].string()),
      label: 'live',
    ),
    secrets: ServerSecrets(
      username: login ? json['username'].stringOrNull : null,
      password: login ? json['password'].stringOrNull : null,
      accessClientId: json['cf_client_id'].stringOrNull,
      accessClientSecret: json['cf_client_secret'].stringOrNull,
    ),
  );
}

const _prompts = [
  'Show me a status card for my cron jobs.',
  'Show this week\'s server load as numbers: CPU 38%, memory 61%, disk 72%, '
      'up 14 days.',
  'List these three tasks with their owners: ship the beta (Asha), fix the '
      'login bug (Ravi), write release notes (me).',
  'Show migration progress: 340 of 500 rows done.',
  'Compare two hosting plans side by side: Starter costs 12 a month with 1 '
      'vCPU, Pro costs 30 a month with 4 vCPU.',
  'I need to decide whether to restart the sync job now or tomorrow. Ask me, '
      'with buttons I can tap.',
  'Update the server load display from earlier so disk shows 75%.',
  'What does HTTP status 429 mean?',
  'Lay out today\'s plan in two sections: Morning (standup 10:00, review '
      'PRs) and Afternoon (deep work, gym 18:00).',
  'Remove the plan display, I do not need it any more.',
];

void main() {
  test('2.12 auth: no login is refused, login is accepted', () async {
    final anonymous = _connect(login: false);
    addTearDown(anonymous.close);
    final refused = await anonymous.client.get('$_base/capabilities');
    stdout.writeln(
      'anonymous: ${refused.isOk ? 'OK (unexpected)' : refused.failureOrNull?.statusCode}',
    );
    expect(refused.isOk, isFalse);

    final connection = _connect(login: true);
    final session = DashboardSession(http: connection);
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
    await session.start();
    final caps = await connection.client.get('$_base/capabilities');
    stdout.writeln('logged in: ${caps.valueOrNull?.raw}');
    expect(caps.isOk, isTrue);
  });

  test(
    '2.12 ten prompts in a flagged session',
    () async {
      final out = Directory('${Directory.systemTemp.path}/iris-genui-plugin')
        ..createSync(recursive: true);
      final connection = _connect(login: true);
      final session = DashboardSession(http: connection);
      final chat = DashboardChat(session);
      final api = connection.client;
      addTearDown(() async {
        await chat.dispose();
        await session.dispose();
        connection.close();
      });
      await session.start();

      final created = (await chat.create()).valueOrNull!;
      final runtimeId = created.runtimeId;
      final stored = created.storedId;
      addTearDown(() async {
        stdout.writeln('delete: ${await chat.delete(stored)}');
        await api.delete('$_base/sessions/$stored/genui');
      });
      final flag = await api.post('$_base/sessions/$stored/genui');
      stdout.writeln('flag: ${flag.valueOrNull?.raw}');

      final events = <({String type, Json payload})>[];
      Completer<void>? done;
      final sub = session.events.listen((e) {
        if (e.sessionId != null && e.sessionId != runtimeId) return;
        events.add((type: e.type, payload: e.payload));
        if (e.type == 'message.complete' && !(done?.isCompleted ?? true)) {
          done!.complete();
        }
      });
      addTearDown(sub.cancel);

      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < _prompts.length; i++) {
        final from = events.length;
        done = Completer<void>();
        final sent = await chat.submit(runtimeId, _prompts[i]);
        expect(sent.isOk, isTrue, reason: 'prompt ${i + 1}: ${sent.failureOrNull}');
        await done.future.timeout(const Duration(seconds: 480));
        await Future<void>.delayed(const Duration(seconds: 3));
        final turn = events.sublist(from);

        final starts = [
          for (final e in turn)
            if (e.type == 'tool.start') e.payload,
        ];
        final names = [for (final p in starts) p['name'].stringOrNull ?? '?'];
        final completes = [
          for (final e in turn)
            if (e.type == 'tool.complete' &&
                e.payload['name'].stringOrNull == 'iris_ui')
              e.payload,
        ];
        var ok = 0;
        final errorLines = <String>[];
        for (final c in completes) {
          final raw = c['result'].stringOrNull ?? '';
          try {
            final r = Json.decode(raw);
            if (r['ok'].boolOrNull ?? false) {
              ok++;
            } else {
              errorLines.addAll([
                for (final l in r['errors'].list) l.stringOrNull ?? '',
              ]);
            }
          } on Object {
            errorLines.add('unparsed result');
          }
        }
        final text = turn
            .where((e) => e.type == 'message.complete')
            .map((e) => e.payload['text'].stringOrNull ?? '')
            .join();
        final row = <String, Object?>{
          'prompt': i + 1,
          'tools': names,
          'iris_ui_calls': completes.length,
          'ok': ok,
          'failed': completes.length - ok,
          'text_chars': text.length,
        };
        rows.add(row);
        stdout.writeln(jsonEncode(row));
        for (final l in errorLines) {
          stdout.writeln('    error: $l');
        }
      }

      final listed = await api.get('$_base/surfaces/$stored');
      stdout.writeln('surfaces: ${listed.valueOrNull?.raw}');
      for (final s in listed.valueOrNull?['surfaces'].list ?? const <Json>[]) {
        final id = s['surface_id'].stringOrNull!;
        final one = await api.get('$_base/surfaces/$stored/$id');
        File('${out.path}/$stored-$id.json').writeAsStringSync(
          jsonEncode(one.valueOrNull?.raw),
        );
      }
      File('${out.path}/$stored-summary.json').writeAsStringSync(
        jsonEncode(rows),
      );
      final first = rows.where((r) => (r['iris_ui_calls']! as int) > 0);
      stdout.writeln(
        'turns with a display: ${first.length}/${rows.length}; '
        'first-try ok: ${first.where((r) => r['failed'] == 0).length}; '
        'total retries: ${rows.fold<int>(0, (a, r) => a + (r['failed']! as int))}',
      );
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}
