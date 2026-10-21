/// What the user's Hermes has for Phase 8 (voice). Provider keys are never
/// printed. The second test synthesises "Ready.", transcribes 300 ms of
/// silence and submits one throwaway voice turn, which it interrupts.
///   flutter test --tags live --run-skipped test/live/phase8_probe_live_test.dart
@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
    await session.start();
    expect(
      session.state.phase,
      LinkPhase.live,
      reason: 'link failure: ${session.state.failure?.kind.name}',
    );
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

  test('leases, sockets and voice turns', () async {
    final lines = <String>[];

    final own = await api.get(
      '/api/config',
      query: {'include_defaults': 'false'},
    );
    lines.add(
      'GET config?include_defaults=false: ${describe(own)} '
      'tts=${own.valueOrNull?['tts'].raw is Map} '
      'voice=${own.valueOrNull?['voice'].raw is Map}',
    );

    for (final lease in const ['stt-lease', 'tts-lease']) {
      for (final active in const [true, false]) {
        final sent = await api.post(
          '/api/audio/$lease',
          body: {'lease': 'iris-probe', 'active': active},
          query: {'profile': 'default'},
        );
        lines.add(
          'POST $lease active=$active: ${describe(sent)} '
          '${sent.valueOrNull?.raw ?? ''}',
        );
      }
    }

    final silence = _silentWav(const Duration(milliseconds: 300));
    final transcribed = await api.post(
      '/api/audio/transcribe',
      body: {
        'data_url': 'data:audio/wav;base64,${base64Encode(silence)}',
        'mime_type': 'audio/wav',
      },
      query: {'profile': 'default'},
      receiveTimeout: const Duration(seconds: 90),
    );
    lines.add(
      'POST transcribe (300 ms silence): ${describe(transcribed)} '
      'ok=${transcribed.valueOrNull?['ok'].raw} '
      'transcript="${transcribed.valueOrNull?['transcript'].raw}"',
    );

    final spoken = await api.post(
      '/api/audio/speak',
      body: {'text': 'Ready.'},
      query: {'profile': 'default'},
      receiveTimeout: const Duration(seconds: 90),
    );
    lines.add(
      'POST speak (one shot): ${describe(spoken)} '
      'ok=${spoken.valueOrNull?['ok'].raw} '
      'mime=${spoken.valueOrNull?['mime_type'].raw} '
      'data_url_chars=${spoken.valueOrNull?['data_url'].stringOrNull?.length}',
    );

    lines.add(await _speakStream(connection));
    lines.add(await _transcribeStream(connection));
    lines.add(await _voiceTurn(session));

    // ignore: avoid_print
    print('\n${lines.join('\n')}\n');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// A mono 16 kHz 16-bit WAV of [length] zeros.
Uint8List _silentWav(Duration length) {
  final data = 16000 * 2 * length.inMilliseconds ~/ 1000;
  final out = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, 16000, Endian.little);
  out.setUint32(28, 32000, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  out.setUint32(40, data, Endian.little);
  return out.buffer.asUint8List();
}

Future<WebSocket> _openAudio(ServerConnection connection, String route) async {
  final ticket = (await connection.auth.mintTicket()).valueOrNull;
  if (ticket == null) throw StateError('no ticket');
  final base = connection.config.uri;
  final path = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final uri = base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '$path$route',
    queryParameters: {'ticket': ticket, 'profile': 'default'},
  );
  return WebSocket.connect(
    uri.toString(),
    headers: connection.accessHeadersFor(uri),
    customClient: connection.socketHttpClient(),
  ).timeout(const Duration(seconds: 30));
}

Future<String> _speakStream(ServerConnection connection) async {
  try {
    final socket = await _openAudio(connection, '/api/audio/speak-stream');
    var binary = 0;
    var bytes = 0;
    int? rate;
    int? channels;
    var last = '(none)';
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    socket.listen(
      (frame) {
        if (frame is List<int>) {
          binary++;
          bytes += frame.length;
          last = 'binary';
          return;
        }
        final j = jsonDecode(frame as String);
        if (j is Map) {
          last = '${j['type']}';
          if (j['type'] == 'start') {
            rate = (j['sample_rate'] as num?)?.toInt();
            channels = (j['channels'] as num?)?.toInt();
          }
          if (j['type'] == 'end' || j['type'] == 'fallback') finish();
        }
      },
      onDone: finish,
      onError: (_) => finish(),
    );
    socket.add(jsonEncode({'text': 'Ready.'}));
    socket.add(jsonEncode({'done': true}));
    await done.future.timeout(const Duration(seconds: 60));
    await socket.close();
    return 'speak-stream: start sample_rate=$rate channels=$channels '
        'binary_frames=$binary total_bytes=$bytes final=$last';
  } on Object catch (error) {
    return 'speak-stream: FAILED ${error.runtimeType}';
  }
}

Future<String> _transcribeStream(ServerConnection connection) async {
  try {
    final socket = await _openAudio(connection, '/api/audio/transcribe-stream');
    final first = Completer<String>();
    void settle(String text) {
      if (!first.isCompleted) first.complete(text);
    }

    socket.listen(
      (frame) => settle(_describeFrame(frame)),
      onDone: () => settle('closed ${socket.closeCode}'),
      onError: (_) => settle('error'),
    );
    socket.add(jsonEncode({'sample_rate': 16000}));
    final got = await first.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => '(no frame within 10 s)',
    );
    await socket.close();
    return 'transcribe-stream: first frame $got';
  } on Object catch (error) {
    return 'transcribe-stream: FAILED ${error.runtimeType}';
  }
}

String _describeFrame(Object? frame) {
  if (frame is List<int>) return 'binary(${frame.length})';
  try {
    final j = jsonDecode(frame as String);
    if (j is Map) {
      // Never print a transcript: the type and an error message are enough.
      final msg = j['type'] == 'error' ? ' message="${j['message']}"' : '';
      return 'json:${j['type']}$msg';
    }
  } on Object {
    // not JSON
  }
  return 'text';
}

Future<String> _voiceTurn(DashboardSession session) async {
  final created = await session.call(
    'session.create',
    params: {'cols': 96, 'source': 'desktop'},
  );
  final id = created.valueOrNull?['session_id'].stringOrNull;
  if (id == null) return 'prompt.submit voice_turn: no session created';
  final sent = await session.call(
    'prompt.submit',
    params: {
      'session_id': id,
      'text': 'Reply with the word ok',
      'voice_turn': true,
    },
    timeout: const Duration(seconds: 60),
  );
  final outcome = switch (sent) {
    Ok(:final value) => 'accepted status=${value['status'].raw}',
    Err(:final failure) =>
      'error ${failure.kind.name} ${failure.statusCode ?? ''} '
          '"${failure.message ?? ''}"',
  };
  final stopped = await session.call(
    'session.interrupt',
    params: {'session_id': id},
  );
  return 'prompt.submit voice_turn: $outcome; '
      'interrupt: ${stopped is Ok ? 'ok' : 'err'}';
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
