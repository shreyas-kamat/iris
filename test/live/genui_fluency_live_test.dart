/// GenUI Phase 0, step 0.10: can the server's model write OpenUI Lang?
///
/// Sends the generated OpenUI system prompt (12-component sample library) as
/// plain text, asks for five displays one turn at a time, then asks for the
/// same five as A2UI JSON. Creates one throwaway conversation and deletes it.
/// `IRIS_OUI_PROMPT=prompt.txt IRIS_OUI_OUT=replies.json flutter test --tags live
/// --run-skipped test/live/genui_fluency_live_test.dart`
/// The replies go to IRIS_OUI_OUT (outside the repo) for the OpenUI parser;
/// this prints only lengths and timings.
// Each display is one long request; adjacent strings keep the lines short.
// ignore_for_file: no_adjacent_strings_in_list
@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

const _displays = [
  'Show today\'s weather for Pune: 31 °C, humidity 62%, wind 14 km/h, with '
      'a "Hot" tag and a button that asks you for tomorrow\'s forecast.',
  'Compare three phones in a table: Pixel 10 at 79999 rupees rated 4.6, '
      'iPhone 17 at 82900 rated 4.7, Galaxy S26 at 74999 rated 4.5. Also show '
      'the average price, computed from the data.',
  'A form to add a task: a title field, a priority dropdown (low, medium, '
      'high; default medium), a Save button that sends the task to you, and '
      'a Clear button that resets both fields.',
  'My four unread emails as cards (sender and subject): Asha "Rent receipt", '
      'Bank "Statement ready", Ravi "Trip photos", GitHub "PR approved". Each '
      'card has a Summarise button that asks you to summarise that email. '
      'Build the cards from one data array, not one by one.',
  'A monthly spending dashboard: rent 25000, food 9200, travel 4100, fun '
      '3300. Show the total and the largest amount as metrics computed with '
      'built-in functions, a table of the categories, and a red "Over budget" '
      'tag only if the total is above 40000.',
];

void main() {
  test(
    '0.10 OpenUI fluency: five displays, then the same as A2UI',
    () async {
      final env = Platform.environment;
      final prompt = File(env['IRIS_OUI_PROMPT']!).readAsStringSync();
      final outPath = env['IRIS_OUI_OUT']!;
      final json = Json.decode(
        File(
          '${env['USERPROFILE'] ?? env['HOME']}/.iris-live.json',
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
      addTearDown(
        () async =>
            stdout.writeln('delete: ${await chat.delete(created.storedId)}'),
      );

      final deltas = StringBuffer();
      String? completed;
      Completer<void>? done;
      final subscription = chat.events
          .where((event) => event.sessionId == created.runtimeId)
          .listen((event) {
            switch (event) {
              case TextDelta(:final text):
                deltas.write(text);
              case MessageCompleted(:final content):
                completed = content;
                if (!(done?.isCompleted ?? true)) done!.complete();
              case TurnFailed(:final message):
                if (!(done?.isCompleted ?? true)) done!.completeError(message);
              default:
                break;
            }
          });
      addTearDown(subscription.cancel);

      Future<String> turn(String label, String text) async {
        deltas.clear();
        completed = null;
        done = Completer<void>();
        final clock = Stopwatch()..start();
        final sent = await chat.submit(created.runtimeId, text);
        expect(sent.isOk, isTrue, reason: '$label: ${sent.failureOrNull}');
        await done!.future.timeout(const Duration(seconds: 480));
        final reply = (completed?.isNotEmpty ?? false)
            ? completed!
            : deltas.toString();
        stdout.writeln(
          '$label: ${reply.length} chars in ${clock.elapsed.inSeconds} s',
        );
        return reply;
      }

      final ready = await turn(
        'setup',
        'For the rest of this conversation, whenever I ask for a display, '
            'reply following the instructions below exactly. Reply to this '
            'message with only the word: ready\n\n$prompt',
      );
      stdout.writeln('setup reply starts: ${ready.trim().split('\n').first}');

      final oui = <String>[];
      for (var i = 0; i < _displays.length; i++) {
        oui.add(await turn('display ${i + 1}', _displays[i]));
      }
      final a2uiRaw = await turn(
        'a2ui',
        'Now give the same five displays as A2UI v0.8 JSON instead (Google\'s '
            'agent-to-UI protocol: a surfaceUpdate with a flat components '
            'list, a dataModelUpdate, and a beginRendering message). For each '
            'display output one JSON array holding its messages, with no '
            'other text, and put a line containing only ===== between '
            'displays.',
      );
      final a2ui = a2uiRaw
          .split(RegExp(r'^\s*=====\s*$', multiLine: true))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      stdout.writeln('a2ui parts: ${a2ui.length}');
      File(outPath).writeAsStringSync(
        jsonEncode({'oui': oui, 'a2ui': a2ui, 'a2uiRaw': a2uiRaw}),
      );
    },
    timeout: const Timeout(Duration(minutes: 50)),
  );
}
