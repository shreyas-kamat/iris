/// The real voice backend against scripted HTTP and audio sockets.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/voice/audio_socket.dart';
import 'package:iris/data/voice/voice_backend.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/data/voice/voice_catalog.dart';

import '../support/fake_http.dart';
import '../support/fake_voice.dart';
import '../support/fake_wire_socket.dart';

void main() {
  late FakeHttp http;
  late ServerConnection connection;
  late DashboardSession session;
  late List<(Uri, Map<String, String>)> dialled;
  late List<FakeAudioSocket> sockets;
  var tickets = 0;

  DashboardVoice voice({String profile = 'default'}) => DashboardVoice(
    session,
    profile: profile,
    connector: (uri, headers) async {
      dialled.add((uri, headers));
      final socket = FakeAudioSocket();
      sockets.add(socket);
      return socket;
    },
  );

  setUp(() {
    tickets = 0;
    dialled = [];
    sockets = [];
    http = FakeHttp()
      ..on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => FakeReply.json({'ticket': 't${++tickets}'}),
      );
    connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'H'),
      adapter: http,
    );
    session = DashboardSession(
      http: connection,
      backoff: (_) => Duration.zero,
      connector: (uri, headers) async => FakeWireSocket(),
    );
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
  });

  group('capabilities', () {
    test(
      'capabilities reads config and live status with the profile',
      () async {
        http
          ..on(
            'GET',
            '/api/config',
            (_) => FakeReply.json({
              'tts': {'provider': 'edge'},
            }),
          )
          ..on(
            'GET',
            '/api/audio/voice-live/status',
            (_) => FakeReply.json({'mode': 'chained', 'available': true}),
          );

        final result = await voice(profile: 'work').capabilities();

        expect(result.valueOrNull?.voiceMode, isTrue);
        expect(http.to('/api/config').single.uri.queryParameters, {
          'profile': 'work',
        });
        expect(
          http.to('/api/audio/voice-live/status').single.uri.queryParameters,
          {'profile': 'work'},
        );
      },
    );

    test('an older server without live status is chained', () async {
      http.on(
        'GET',
        '/api/config',
        (_) => FakeReply.json({
          'voice': {'voice_chat_mode': 'gpt-live'},
        }),
      );
      // The status route is not scripted, so FakeHttp answers 404.

      final result = await voice().capabilities();

      expect(result.valueOrNull?.engine, VoiceEngine.chained);
    });

    test('a failed config read is an error', () async {
      http.on(
        'GET',
        '/api/config',
        (_) => FakeReply.json({'detail': 'down'}, status: 500),
      );

      final result = await voice().capabilities();

      expect(result.failureOrNull?.kind, FailureKind.server);
    });

    test('a failed status read other than 404 is an error', () async {
      http
        ..on('GET', '/api/config', (_) => FakeReply.json({}))
        ..on(
          'GET',
          '/api/audio/voice-live/status',
          (_) => FakeReply.json({'detail': 'boom'}, status: 500),
        );

      expect((await voice().capabilities()).isErr, isTrue);
    });
  });

  group('speech', () {
    test('transcribe silence is ok empty', () async {
      http.on(
        'POST',
        '/api/audio/transcribe',
        (_) => FakeReply.json({'ok': true, 'transcript': ''}),
      );

      final result = await voice().transcribe(Uint8List.fromList([1, 2, 3]));

      expect(result.valueOrNull, '');
      final request = http.to('/api/audio/transcribe').single;
      expect(request.uri.queryParameters, {'profile': 'default'});
      final body = request.data as Map;
      expect(body['mime_type'], 'audio/wav');
      expect(body['data_url'], 'data:audio/wav;base64,AQID');
    });

    test('a transcribe error body is an error', () async {
      http.on(
        'POST',
        '/api/audio/transcribe',
        (_) => FakeReply.json({'ok': false, 'error': 'no key'}),
      );

      final result = await voice().transcribe(Uint8List(4));

      expect(result.failureOrNull?.message, 'no key');
    });

    test('speakOnce decodes the data url', () async {
      http.on(
        'POST',
        '/api/audio/speak',
        (_) => FakeReply.json({
          'ok': true,
          'data_url': 'data:audio/mpeg;base64,AQID',
          'mime_type': 'audio/mpeg',
        }),
      );

      final result = await voice().speakOnce('Ready.');

      final audio = result.valueOrNull!;
      expect(audio.bytes, [1, 2, 3]);
      expect(audio.mime, 'audio/mpeg');
      expect(http.to('/api/audio/speak').single.data, {'text': 'Ready.'});
    });

    test('speakOnce without audio is an error', () async {
      http.on('POST', '/api/audio/speak', (_) => FakeReply.json({'ok': true}));

      expect((await voice().speakOnce('x')).isErr, isTrue);
    });

    test('leases name the right route and report a refusal', () async {
      http
        ..on(
          'POST',
          '/api/audio/stt-lease',
          (_) => FakeReply.json({'ok': true, 'leases': 1}),
        )
        ..on(
          'POST',
          '/api/audio/tts-lease',
          (_) => FakeReply.json({'ok': false, 'error': 'cold'}),
        );

      expect((await voice().lease(speech: false, active: true)).isOk, isTrue);
      final stt = http.to('/api/audio/stt-lease').single.data as Map;
      expect(stt['active'], isTrue);
      expect(stt['lease'], isNotEmpty);
      expect((await voice().lease(speech: true, active: false)).isErr, isTrue);
    });
  });

  group('voices', () {
    test('ElevenLabs voices come from the server', () async {
      http.on(
        'GET',
        '/api/audio/elevenlabs/voices',
        (_) => FakeReply.json({
          'available': true,
          'voices': [
            {'voice_id': 'a1', 'name': 'Rachel', 'label': 'Rachel · calm'},
            {'voice_id': 'b2', 'name': 'Adam'},
            {'name': 'no id'},
          ],
        }),
      );

      final result = await voice().serverVoices();

      expect(result.valueOrNull, const [
        VoiceChoice('a1', 'Rachel · calm'),
        VoiceChoice('b2', 'Adam'),
      ]);
    });

    test('unavailable or missing means an empty list', () async {
      http.on(
        'GET',
        '/api/audio/elevenlabs/voices',
        (_) => FakeReply.json({'available': false, 'voices': <Object?>[]}),
      );
      expect((await voice().serverVoices()).valueOrNull, isEmpty);

      http.on(
        'GET',
        '/api/audio/elevenlabs/voices',
        (_) => FakeReply.json({'detail': 'nope'}, status: 404),
      );
      expect((await voice().serverVoices()).valueOrNull, isEmpty);
    });

    test('setVoice writes one key', () async {
      Object? put;
      http
        ..on(
          'GET',
          '/api/config',
          (_) => FakeReply.json({
            'tts': {
              'provider': 'edge',
              'edge': {'voice': 'a'},
            },
            'model': {'default': 'x'},
          }),
        )
        ..on('PUT', '/api/config', (request) {
          put = request.data;
          return FakeReply.json({'ok': true});
        });

      final result = await voice().setVoice('tts.edge.voice', 'b');

      expect(result.isOk, isTrue);
      final read = http.to('/api/config').firstWhere((r) => r.method == 'GET');
      expect(read.uri.queryParameters, {
        'include_defaults': 'false',
        'profile': 'default',
      });
      expect(put, {
        'config': {
          'tts': {
            'provider': 'edge',
            'edge': {'voice': 'b'},
          },
          'model': {'default': 'x'},
        },
      });
    });

    test('setVoice creates missing parents', () async {
      Object? put;
      http
        ..on('GET', '/api/config', (_) => FakeReply.json({}))
        ..on('PUT', '/api/config', (request) {
          put = request.data;
          return FakeReply.json({'ok': true});
        });

      await voice().setVoice('voice.gpt_live.voice', 'cedar');

      expect(put, {
        'config': {
          'voice': {
            'gpt_live': {'voice': 'cedar'},
          },
        },
      });
    });

    test('a failed write is an error', () async {
      http
        ..on('GET', '/api/config', (_) => FakeReply.json({}))
        ..on(
          'PUT',
          '/api/config',
          (_) => FakeReply.json({'detail': 'disk'}, status: 500),
        );

      expect((await voice().setVoice('tts.edge.voice', 'b')).isErr, isTrue);
    });

    test('a failed read stops the write', () async {
      http.on(
        'GET',
        '/api/config',
        (_) => FakeReply.json({'detail': 'down'}, status: 500),
      );

      expect((await voice().setVoice('tts.edge.voice', 'b')).isErr, isTrue);
      expect(http.to('/api/config').where((r) => r.method == 'PUT'), isEmpty);
    });
  });

  group('sockets', () {
    test('openSocket mints a ticket per socket', () async {
      final backend = voice();

      expect(
        (await backend.openSocket('/api/audio/speak-stream')).isOk,
        isTrue,
      );
      expect(
        (await backend.openSocket('/api/audio/speak-stream')).isOk,
        isTrue,
      );

      expect(http.to('/api/auth/ws-ticket'), hasLength(2));
      expect(dialled.map((d) => d.$1.toString()), [
        'wss://h.example/api/audio/speak-stream?ticket=t1&profile=default',
        'wss://h.example/api/audio/speak-stream?ticket=t2&profile=default',
      ]);
    });

    test('a failed ticket is an error and dials nothing', () async {
      http.on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => FakeReply.json({'detail': 'no'}, status: 500),
      );

      final result = await voice().openSocket('/api/audio/speak-stream');

      expect(result.isErr, isTrue);
      expect(dialled, isEmpty);
    });

    test('a refused dial is an error without the ticket in it', () async {
      final backend = DashboardVoice(
        session,
        connector: (uri, headers) async =>
            throw const SocketException('refused ?ticket=t1'),
      );

      final result = await backend.openSocket('/api/audio/speak-stream');

      expect(result.failureOrNull?.kind, FailureKind.offline);
      expect('${result.failureOrNull?.message}', isNot(contains('t1')));
    });
  });

  group('GPT-Live', () {
    test('startGptLive sends the sdp byte-exact', () async {
      http.on(
        'POST',
        '/api/audio/voice-live/session',
        (_) => FakeReply.json({
          'ok': true,
          'session': {'id': 's'},
          'transport': {'type': 'webrtc', 'sdp': 'v=0\r\nanswer'},
        }),
      );
      const offer = 'v=0\r\no=- 1 2 IN IP4 0.0.0.0\r\n';

      final result = await voice().startGptLive(offer, const [
        {'role': 'user', 'text': 'hi'},
      ]);

      final answer = result.valueOrNull!;
      expect(answer.sessionId, 's');
      expect(answer.sdp, 'v=0\r\nanswer');
      final body = http.to('/api/audio/voice-live/session').single.data as Map;
      expect(body['sdp'], offer);
      expect(body['history'], [
        {'role': 'user', 'text': 'hi'},
      ]);
    });

    test('a refusal carries the server detail', () async {
      http.on(
        'POST',
        '/api/audio/voice-live/session',
        (_) => FakeReply.json({'detail': 'No OpenAI key'}, status: 503),
      );

      final result = await voice().startGptLive('v=0\r\n', const []);

      expect(result.failureOrNull?.message, 'No OpenAI key');
    });

    test('an answer without an sdp is malformed', () async {
      http.on(
        'POST',
        '/api/audio/voice-live/session',
        (_) => FakeReply.json({
          'ok': true,
          'session': {'id': 's'},
        }),
      );

      final result = await voice().startGptLive('v=0\r\n', const []);

      expect(result.failureOrNull?.kind, FailureKind.malformed);
    });
  });

  group('IoAudioSocket', () {
    test('decodes text and binary frames and sends both', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <Object?>[];
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        addTearDown(ws.close);
        ws
          ..add('{"type":"start","sample_rate":24000}')
          ..add(Uint8List.fromList([9, 8, 7]))
          ..listen(received.add);
      });

      final socket = await IoAudioSocket.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/'),
        const {},
      );
      addTearDown(socket.close);

      final frames = await socket.frames.take(2).toList();
      socket
        ..sendJson({'text': 'hi'})
        ..sendBytes(Uint8List.fromList([1, 2]));
      while (received.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(frames[0], isA<AudioText>());
      expect((frames[0] as AudioText).json['sample_rate'].integer(), 24000);
      expect(frames[1], isA<AudioBytes>());
      expect((frames[1] as AudioBytes).bytes, [9, 8, 7]);
      expect(received[0], '{"text":"hi"}');
      expect(received[1], [1, 2]);
    });
  });
}
