/// GenUI Phase 0 (plan 0.2–0.8): what the `iris-probe` plugin on the user's
/// Hermes reveals. Needs the throwaway probe installed and enabled. The second
/// test creates one throwaway conversation, runs three turns (about 10 minutes)
/// and deletes it.
///   flutter test --tags live --run-skipped test/live/genui_probe_live_test.dart
/// Prints ids, event kinds, lengths and timings; the raw (shrunk) events go to
/// `<system temp>/iris-genui-probe/`, never into the repo.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

const _base = '/api/plugins/iris-probe';

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

String _describe(Result<Json> result) => switch (result) {
  Ok(:final value) => 'ok ${_shrink(value.raw)}',
  Err(:final failure) =>
    '${failure.kind.name} ${failure.statusCode ?? ''} '
        '"${failure.message ?? ''}"',
};

/// Long strings become `<str N>` so payloads of x's do not flood the output.
Object? _shrink(Object? value) => switch (value) {
  final String s when s.length > 120 => '<str ${s.length}>',
  final Map<Object?, Object?> m => {
    for (final e in m.entries) '${e.key}': _shrink(e.value),
  },
  final List<Object?> l => [for (final e in l) _shrink(e)],
  _ => value,
};

void main() {
  test(
    '0.2 auth: plugin routes with and without the dashboard login',
    () async {
      final anonymous = _connect(login: false);
      addTearDown(anonymous.close);
      stdout.writeln(
        'hello, Access headers only: '
        '${_describe(await anonymous.client.get('$_base/hello'))}',
      );

      final connection = _connect(login: true);
      final session = DashboardSession(http: connection);
      addTearDown(() async {
        await session.dispose();
        connection.close();
      });
      await session.start();
      expect(session.state.phase, LinkPhase.live);
      stdout.writeln(
        'hello, logged in: '
        '${_describe(await connection.client.get('$_base/hello'))}',
      );
      final events = await connection.client.get('$_base/events');
      for (final row in events.valueOrNull?['events'].list ?? const <Json>[]) {
        if (row['event'].stringOrNull == 'register') {
          stdout.writeln('register row: ${_shrink(row.raw)}');
        }
      }
    },
  );

  test(
    '0.3–0.8: tool events, hook context, flag lifetime, history, rewriting',
    () async {
      final out = Directory('${Directory.systemTemp.path}/iris-genui-probe')
        ..createSync(recursive: true);
      final dump = File(
        '${out.path}/events-${DateTime.now().millisecondsSinceEpoch}.jsonl',
      ).openWrite();
      addTearDown(dump.close);

      final connection = _connect(login: true);
      // Replaced in 0.5 by a fresh WebSocket session (an app restart).
      var session = DashboardSession(http: connection);
      var chat = DashboardChat(session);
      final api = connection.client;
      addTearDown(() async {
        await chat.dispose();
        await session.dispose();
        connection.close();
      });
      await session.start();
      expect(session.state.phase, LinkPhase.live);
      await api.post('$_base/events/clear');

      final created = (await chat.create()).valueOrNull!;
      var runtimeId = created.runtimeId;
      final storedId = created.storedId;
      stdout.writeln('runtime id: $runtimeId, stored id: $storedId');
      addTearDown(() async {
        stdout.writeln('delete: ${await chat.delete(storedId)}');
        await api.delete('$_base/sessions/$runtimeId/flag');
        await api.delete('$_base/sessions/$storedId/flag');
      });
      await api.post('$_base/sessions/$runtimeId/flag');
      await api.post('$_base/sessions/$storedId/flag');

      final clock = Stopwatch()..start();
      final seen = <({int ms, String type, RpcEvent event})>[];
      Completer<void>? turnDone;
      void onEvent(RpcEvent event) {
        if (event.sessionId != null && event.sessionId != runtimeId) return;
        final ms = clock.elapsedMilliseconds;
        seen.add((ms: ms, type: event.type, event: event));
        dump.writeln(
          jsonEncode({
            'ms': ms,
            'type': event.type,
            'session': event.sessionId,
            'params': _shrink(event.raw.raw),
          }),
        );
        if (event.type == 'message.complete' &&
            !(turnDone?.isCompleted ?? true)) {
          turnDone!.complete();
        }
      }

      var subscription = session.events.listen(onEvent);
      addTearDown(() => subscription.cancel());

      Future<List<({int ms, String type, RpcEvent event})>> turn(
        String label,
        String text,
      ) async {
        final from = seen.length;
        final started = clock.elapsedMilliseconds;
        turnDone = Completer<void>();
        final sent = await chat.submit(runtimeId, text);
        expect(sent.isOk, isTrue, reason: '$label: ${sent.failureOrNull}');
        await turnDone!.future.timeout(const Duration(seconds: 480));
        // Let trailing events (session.info, title) land.
        await Future<void>.delayed(const Duration(seconds: 3));
        final rows = seen.sublist(from);
        stdout.writeln('--- $label: ${rows.length} events');
        String? last;
        var repeats = 0;
        void flush() {
          if (last != null) {
            stdout.writeln('  $last${repeats > 1 ? ' x$repeats' : ''}');
          }
        }

        for (final r in rows) {
          final line = switch (r.type) {
            'tool.start' || 'tool.complete' || 'tool.generating' =>
              '+${r.ms - started}ms ${r.type} '
                  'id=${r.event.payload['tool_id'].stringOrNull} '
                  'name=${r.event.payload['name'].stringOrNull} '
                  'args=${_shrink(r.event.payload['args'].raw)} '
                  'keys=${(r.event.payload.raw as Map?)?.keys.toList()}',
            'message.complete' =>
              '+${r.ms - started}ms message.complete '
                  'text="${r.event.payload['text'].stringOrNull}"',
            _ => r.type,
          };
          if (line == last) {
            repeats++;
          } else {
            flush();
            last = line;
            repeats = 1;
          }
        }
        flush();
        final deltas = rows
            .where((r) => r.type == 'message.delta')
            .map((r) => r.event.payload['text'].stringOrNull ?? '')
            .join();
        stdout.writeln('  deltas joined: "$deltas"');
        return rows;
      }

      Future<void> serverEvents(String label) async {
        final body = (await api.get('$_base/events')).valueOrNull;
        stdout.writeln('--- server hooks after $label');
        var registers = 0;
        for (final row in body?['events'].list ?? const <Json>[]) {
          // Some periodic `hermes` process loads plugins about every 9 s.
          if (row['event'].stringOrNull == 'register') {
            registers++;
            continue;
          }
          final map = Map<String, Object?>.from(row.raw! as Map)
            ..remove('home')
            ..remove('kw_keys');
          stdout.writeln('  ${_shrink(map)}');
        }
        stdout.writeln('  (register rows skipped: $registers)');
        stdout.writeln(
          '  kw_keys by event: ${{for (final row in body?['events'].list ?? const <Json>[]) row['event'].stringOrNull: row['kw_keys'].raw}}',
        );
        await api.post('$_base/events/clear');
      }

      // 0.3, 0.4, 0.7: tool payload sizes and timing; hook context; platform.
      await turn(
        'turn 1 (tool payloads)',
        // Repeated single letters made the model stall; number ranges are
        // reliable: 1..300 is ~1.1k chars, 1..1800 ~7.9k, 1..2600 ~11.9k.
        'This is a diagnostic test. Call the iris_probe tool three times, one '
            'call at a time. Each payload is the whole numbers from 1 up to N, '
            'separated by commas with no spaces: first N=300, then N=1800, '
            'then N=2600. After all three, reply with only the three lengths '
            'it returned, comma separated.',
      );
      await serverEvents('turn 1');

      // 0.8: can transform_llm_output rewrite what the client sees?
      await turn(
        'turn 2 (rewrite)',
        'Reply with exactly this text and nothing else: alpha [[iris-strip]]',
      );
      await serverEvents('turn 2');

      // 0.4, 0.6: stored rows and the app's parser.
      final raw = await api.get(
        '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
      );
      stdout.writeln('--- stored rows');
      for (final row in raw.valueOrNull?['messages'].list ?? const <Json>[]) {
        final content = row['content'].stringOrNull ?? '';
        stdout.writeln(
          '  role=${row['role'].stringOrNull} '
          'keys=${(row.raw as Map?)?.keys.toList()} '
          'content="${content.length > 160 ? '${content.substring(0, 160)}…(${content.length})' : content}" '
          'tool_calls=${_shrink(row['tool_calls'].raw)} '
          'tool_name=${row['tool_name'].stringOrNull}',
        );
      }
      final page = await chat.history(storedId);
      stdout.writeln(
        '--- HistoryParser: ${page.isOk ? 'ok' : page.failureOrNull}',
      );
      for (final item in page.valueOrNull?.items ?? const []) {
        final text = '$item';
        stdout.writeln(
          '  ${item.runtimeType}: ${text.length > 160 ? text.substring(0, 160) : text}',
        );
      }

      // 0.5: does the flag survive a new WebSocket and session.resume?
      // (reconnectNow() is a no-op while live, so open a fresh session.)
      await subscription.cancel();
      await chat.dispose();
      await session.dispose();
      session = DashboardSession(http: connection);
      chat = DashboardChat(session);
      await session.start();
      expect(session.state.phase, LinkPhase.live);
      subscription = session.events.listen(onEvent);
      final resumed = (await chat.resume(storedId)).valueOrNull!;
      stdout.writeln(
        '--- after reconnect: runtime id ${resumed.runtimeId} '
        '(was $runtimeId)',
      );
      runtimeId = resumed.runtimeId;
      await turn('turn 3 (after reconnect)', 'Reply with exactly: ok');
      await serverEvents('turn 3');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
