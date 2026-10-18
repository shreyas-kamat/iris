/// Fakes for the voice layer: a scripted audio socket and a backend whose
/// answers a test sets. Later tasks add the mic, playback and route fakes.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/voice/audio_socket.dart';
import 'package:iris/data/voice/voice_backend.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/data/voice/voice_catalog.dart';
import 'package:iris/features/voice/mic_permission.dart';

/// An [AudioSocket] a test drives: it records what the client sends and lets
/// the test push frames back.
final class FakeAudioSocket implements AudioSocket {
  final _incoming = StreamController<AudioFrame>();

  /// Every JSON frame the client sent, in order.
  final List<Map<String, Object?>> sentJson = [];

  /// Every binary frame the client sent, in order.
  final List<Uint8List> sentBytes = [];

  bool closed = false;

  @override
  Stream<AudioFrame> get frames => _incoming.stream;

  @override
  void sendJson(Map<String, Object?> json) {
    if (closed) throw StateError('socket closed');
    sentJson.add(json);
  }

  @override
  void sendBytes(Uint8List bytes) {
    if (closed) throw StateError('socket closed');
    sentBytes.add(bytes);
  }

  @override
  Future<void> close() async {
    closed = true;
    // Not awaited: once the client has cancelled its subscription the done
    // future of a single-subscription controller may never complete.
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  /// Delivers a text frame, e.g. `{'type': 'start', 'sample_rate': 24000}`.
  void serverSends(Map<String, Object?> frame) {
    if (!_incoming.isClosed) _incoming.add(AudioText(Json.of(frame)));
  }

  /// Delivers a binary frame (PCM).
  void serverSendsBytes(Uint8List bytes) {
    if (!_incoming.isClosed) _incoming.add(AudioBytes(bytes));
  }

  /// The server or the network dropping the connection.
  Future<void> serverCloses() => close();
}

/// A [VoiceBackend] with scripted answers; records what it was asked.
final class FakeVoiceBackend implements VoiceBackend {
  Result<VoiceCapabilities> capabilitiesResult = const Ok(
    VoiceCapabilities(
      dictation: true,
      voiceMode: true,
      engine: VoiceEngine.chained,
    ),
  );
  Result<String> transcribeResult = const Ok('');
  Result<SpokenAudio> speakResult = Ok(
    SpokenAudio(Uint8List.fromList(const [0]), 'audio/mpeg'),
  );
  Result<void> leaseResult = const Ok(null);
  Result<List<VoiceChoice>> voicesResult = const Ok([]);
  Result<void> setVoiceResult = const Ok(null);
  Result<GptLiveAnswer> gptLiveResult = const Ok(
    GptLiveAnswer(sessionId: 'live-1', sdp: 'v=0\r\n'),
  );

  /// The sockets [openSocket] hands out, oldest first; when empty a new
  /// [FakeAudioSocket] is made.
  final List<FakeAudioSocket> sockets = [];
  Result<AudioSocket>? socketFailure;

  /// What was asked: `capabilities`, `transcribe`, `speak <text>`,
  /// `lease stt|tts on|off`, `voices`, `setVoice <key>=<voice>`, `gptLive`,
  /// `socket <route>`.
  final List<String> calls = [];

  /// Transcribed audio sizes, in bytes.
  final List<int> transcribed = [];

  @override
  Future<Result<VoiceCapabilities>> capabilities() async {
    calls.add('capabilities');
    return capabilitiesResult;
  }

  @override
  Future<Result<String>> transcribe(Uint8List wav) async {
    calls.add('transcribe');
    transcribed.add(wav.length);
    return transcribeResult;
  }

  @override
  Future<Result<SpokenAudio>> speakOnce(String text) async {
    calls.add('speak $text');
    return speakResult;
  }

  @override
  Future<Result<void>> lease({
    required bool speech,
    required bool active,
  }) async {
    calls.add('lease ${speech ? 'tts' : 'stt'} ${active ? 'on' : 'off'}');
    return leaseResult;
  }

  @override
  Future<Result<List<VoiceChoice>>> serverVoices() async {
    calls.add('voices');
    return voicesResult;
  }

  @override
  Future<Result<void>> setVoice(String key, String voice) async {
    calls.add('setVoice $key=$voice');
    return setVoiceResult;
  }

  @override
  Future<Result<GptLiveAnswer>> startGptLive(
    String sdp,
    List<Map<String, Object?>> history,
  ) async {
    calls.add('gptLive');
    return gptLiveResult;
  }

  @override
  Future<Result<AudioSocket>> openSocket(String route) async {
    calls.add('socket $route');
    final failure = socketFailure;
    if (failure != null) return failure;
    final socket = sockets.isEmpty ? FakeAudioSocket() : sockets.removeAt(0);
    opened.add(socket);
    return Ok(socket);
  }

  /// Every socket handed out, in order.
  final List<FakeAudioSocket> opened = [];
}

/// A [MicPermission] a test sets: what the system says now, what asking
/// would answer, and a record of what was done.
final class FakeMicPermission implements MicPermission {
  FakeMicPermission({
    this.current = MicStatus.granted,
    this.onRequest = MicStatus.granted,
  });

  MicStatus current;

  /// The answer to the system prompt.
  MicStatus onRequest;

  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<MicStatus> status() async => current;

  @override
  Future<MicStatus> request() async {
    requests++;
    return current = onRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}
