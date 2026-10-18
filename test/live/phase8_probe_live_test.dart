/// What the user's Hermes has for Phase 8 (voice). Read-only: nothing is
/// synthesised or transcribed, and provider keys are never printed.
///   flutter test --tags live --run-skipped test/live/phase8_probe_live_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
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

  String describe(Result<Json> result) => switch (result) {
    Ok(:final value) => 'ok ${_shape(value)}',
    Err(:final failure) =>
      '${failure.kind.name} ${failure.statusCode ?? ''} '
          '"${failure.message ?? ''}"',
  };

  test('what Phase 8 can use', () async {
    final lines = <String>[];

    final config = await api.get('/api/config');
    lines.add('GET config: ${describe(config)}');
    final c = config.valueOrNull;
    if (c != null) {
      lines.add('stt: ${_pick(c['stt'], const ['enabled', 'provider', 'streaming', 'language'])}');
      lines.add('tts: ${_pick(c['tts'], const ['provider'])}');
      lines.add('voice: ${_pick(c['voice'], const ['voice_chat_mode', 'max_recording_seconds', 'auto_tts', 'client_direct', 'silence_threshold', 'silence_duration', 'barge_in', 'barge_in_grace_seconds', 'barge_in_threshold_multiplier', 'stop_phrases', 'thinking_sound'])}');
    }
    lines.add('GET config/defaults: ${describe(await api.get('/api/config/defaults'))}');

    // voice-config carries provider keys: print only the non-secret fields.
    final direct = await api.get('/api/audio/voice-config');
    lines.add('GET voice-config: ${direct is Err ? describe(direct) : 'ok'}');
    final d = direct.valueOrNull;
    if (d != null) {
      lines.add('voice-config stt: ${_pick(d['stt'], const ['mode', 'wire', 'provider', 'streaming', 'reason'])}');
      lines.add('voice-config tts: ${_pick(d['tts'], const ['mode', 'wire', 'provider', 'voice', 'reason'])}');
    }

    final live = await api.get('/api/audio/voice-live/status');
    lines.add('GET voice-live/status: ${describe(live)} ${live.valueOrNull?.raw ?? ''}');

    final voices = await api.get('/api/audio/elevenlabs/voices');
    lines.add(
      'GET elevenlabs/voices: ${describe(voices)} '
      'available=${voices.valueOrNull?['available'].raw} '
      'count=${voices.valueOrNull?['voices'].list.length}',
    );

    // ignore: avoid_print
    print('\n${lines.join('\n')}\n');
  });
}

String _shape(Json value) {
  if (value.isList) return 'list(${value.list.length})';
  final raw = value.raw;
  return raw is Map ? 'object{${raw.keys.join(',')}}' : '(not an object)';
}

String _pick(Json value, List<String> keys) {
  final raw = value.raw;
  if (raw is! Map) return '(absent)';
  return {for (final k in keys) if (raw.containsKey(k)) k: raw[k]}.toString();
}
