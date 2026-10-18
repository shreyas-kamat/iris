/// Fakes for the voice layer: a scripted audio socket, a backend whose
/// answers a test sets, and the mic, playback and audio route seams.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/voice/audio_socket.dart';
import 'package:iris/data/voice/voice_backend.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/data/voice/voice_catalog.dart';
import 'package:iris/features/voice/audio/audio_out.dart';
import 'package:iris/features/voice/audio/audio_route.dart';
import 'package:iris/features/voice/audio/mic_capture.dart';
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

  /// Called with each JSON frame the client sends, so a test can answer it.
  void Function(Map<String, Object?> json)? onJson;

  @override
  Stream<AudioFrame> get frames => _incoming.stream;

  @override
  void sendJson(Map<String, Object?> json) {
    if (closed) throw StateError('socket closed');
    sentJson.add(json);
    onJson?.call(json);
  }

  /// A speak stream that answers `done` as a working server does: a start
  /// frame and some audio.
  static FakeAudioSocket speaking() {
    final socket = FakeAudioSocket();
    socket.onJson = (json) {
      if (json['done'] == true) {
        socket
          ..serverSends({'type': 'start', 'sample_rate': 24000, 'channels': 1})
          ..serverSendsBytes(Uint8List.fromList(List.filled(480, 1)));
      }
    };
    return socket;
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

  /// The transcribed audio itself, in order.
  final List<Uint8List> wavs = [];

  /// Answered first, in order, before [transcribeResult].
  final List<Result<String>> transcribeQueue = [];

  @override
  Future<Result<VoiceCapabilities>> capabilities() async {
    calls.add('capabilities');
    return capabilitiesResult;
  }

  /// Held by a test to keep a transcription in flight.
  Completer<void>? transcribeGate;

  @override
  Future<Result<String>> transcribe(Uint8List wav) async {
    calls.add('transcribe');
    await transcribeGate?.future;
    transcribed.add(wav.length);
    wavs.add(wav);
    if (transcribeQueue.isNotEmpty) return transcribeQueue.removeAt(0);
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

/// A [MicCapture] a test pushes PCM through.
final class FakeMic implements MicCapture {
  FakeMic({this.allowed = true});

  /// What [start] answers.
  bool allowed;
  bool open = false;
  int starts = 0;
  int stops = 0;

  final _pcm = StreamController<Uint8List>.broadcast(sync: true);

  @override
  Stream<Uint8List> get pcm => _pcm.stream;

  @override
  Future<bool> start() async {
    if (open) return true;
    starts++;
    open = allowed;
    return allowed;
  }

  @override
  Future<void> stop() async {
    if (open) stops++;
    open = false;
  }

  /// Delivers a chunk, if the mic is open.
  void push(Uint8List chunk) {
    if (open) _pcm.add(chunk);
  }

  /// A chunk of [samples] samples all at [value] (a square-ish level whose
  /// RMS is `value.abs()`).
  void pushLevel(int value, {int samples = 1600}) {
    final data = ByteData(samples * 2);
    for (var i = 0; i < samples; i++) {
      data.setInt16(i * 2, i.isEven ? value : -value, Endian.little);
    }
    push(data.buffer.asUint8List());
  }
}

/// An [AudioOut] that records what it was asked to play. [endPcm] and
/// [playFile] wait until the test calls [drain] / [finishFile], or [stop].
final class FakeAudioOut implements AudioOut {
  /// Sample rate of each [startPcm], in order.
  final List<int> starts = [];

  /// PCM chunks of the current reply.
  final List<Uint8List> pcm = [];

  /// Files played: (bytes, mime).
  final List<(Uint8List, String)> files = [];
  int stops = 0;
  bool ending = false;

  /// True between [startPcm] and the end or stop of that reply.
  bool playing = false;

  Completer<void>? _drained;
  Completer<void>? _file;
  final _level = StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get level => _level.stream;

  /// Sets the playback level the orb sees.
  void emitLevel(double value) => _level.add(value);

  @override
  Future<void> startPcm(int sampleRate) async {
    starts.add(sampleRate);
    pcm.clear();
    playing = true;
  }

  @override
  void addPcm(Uint8List chunk) => pcm.add(chunk);

  @override
  Future<void> endPcm() {
    ending = true;
    return (_drained ??= Completer<void>()).future;
  }

  /// Everything queued has now been heard.
  void drain() {
    ending = false;
    playing = false;
    _drained?.complete();
    _drained = null;
  }

  @override
  Future<void> playFile(Uint8List bytes, String mime) {
    files.add((bytes, mime));
    playing = true;
    return (_file ??= Completer<void>()).future;
  }

  void finishFile() {
    playing = false;
    _file?.complete();
    _file = null;
  }

  @override
  Future<void> stop() async {
    stops++;
    ending = false;
    playing = false;
    _drained?.complete();
    _drained = null;
    _file?.complete();
    _file = null;
  }
}

/// An [AudioRoute] whose events a test raises.
final class FakeAudioRoute implements AudioRoute {
  FakeAudioRoute({this.speaker = true, this.headset});

  bool speaker;
  String? headset;
  bool active = false;
  int activations = 0;
  int deactivations = 0;

  final _interruptions = StreamController<InterruptionKind>.broadcast(
    sync: true,
  );
  final _noisy = StreamController<void>.broadcast(sync: true);
  final _route = StreamController<RouteInfo>.broadcast(sync: true);

  RouteInfo get current => RouteInfo(speaker: speaker, headset: headset);

  @override
  Stream<InterruptionKind> get interruptions => _interruptions.stream;

  @override
  Stream<void> get becameNoisy => _noisy.stream;

  @override
  Stream<RouteInfo> get route async* {
    if (active) yield current;
    yield* _route.stream;
  }

  @override
  Future<void> activate() async {
    activations++;
    active = true;
    _route.add(current);
  }

  @override
  Future<void> deactivate() async {
    deactivations++;
    active = false;
  }

  @override
  Future<void> setSpeaker({required bool on}) async {
    speaker = on;
    if (active) _route.add(current);
  }

  void interrupt(InterruptionKind kind) => _interruptions.add(kind);

  void unplug() {
    headset = null;
    _noisy.add(null);
    if (active) _route.add(current);
  }

  void plugIn(String name) {
    headset = name;
    if (active) _route.add(current);
  }
}
