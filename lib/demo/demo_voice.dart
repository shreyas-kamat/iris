/// Voice in demo mode: a chained setup with a voice list, and one scripted
/// call that plays through every state. It reads no microphone, plays no
/// audio and reaches no server.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../app/voice_providers.dart';
import '../core/failure.dart';
import '../core/result.dart';
import '../data/chat/chat_models.dart';
import '../data/voice/audio_socket.dart';
import '../data/voice/voice_backend.dart';
import '../data/voice/voice_capabilities.dart';
import '../data/voice/voice_catalog.dart';
import '../features/voice/audio/audio_out.dart';
import '../features/voice/audio/audio_route.dart';
import '../features/voice/audio/mic_capture.dart';
import '../features/voice/screen_awake.dart';
import '../features/voice/voice_call.dart';
import '../features/voice/voice_host.dart';

const _voiceKey = 'tts.edge.voice';
const _startVoice = 'en-US-AriaNeural';

/// The demo's server speaks with Edge. A voice the person picks is kept for
/// this session only.
final class DemoVoiceBackend implements VoiceBackend {
  DemoVoiceBackend({String voice = _startVoice}) : _voice = voice;

  String _voice;

  static IrisFailure _noServer() => IrisFailure(
    FailureKind.server,
    message: "The demo doesn't reach a server's voice.",
  );

  @override
  Future<Result<VoiceCapabilities>> capabilities() async => Ok(
    VoiceCapabilities(
      dictation: true,
      voiceMode: true,
      engine: VoiceEngine.chained,
      voiceKey: _voiceKey,
      currentVoice: _voice,
    ),
  );

  @override
  Future<Result<String>> transcribe(Uint8List wav) async => Err(_noServer());

  @override
  Future<Result<SpokenAudio>> speakOnce(String text) async => Err(_noServer());

  @override
  Future<Result<void>> lease({
    required bool speech,
    required bool active,
  }) async => const Ok(null);

  @override
  Future<Result<List<VoiceChoice>>> serverVoices() async => const Ok([]);

  @override
  Future<Result<void>> setVoice(String key, String voice) async {
    if (key == _voiceKey) _voice = voice;
    return const Ok(null);
  }

  @override
  Future<Result<GptLiveAnswer>> startGptLive(
    String sdp,
    List<Map<String, Object?>> history,
  ) async => Err(_noServer());

  @override
  Future<Result<AudioSocket>> openSocket(String route) async =>
      Err(_noServer());
}

/// A call that plays one exchange: listening, the person speaking, thinking,
/// a tool, a question, Iris speaking, then listening again. Taps during the
/// script are not answered; the script only plays.
final class DemoCallEngine implements CallEngine {
  DemoCallEngine(this._host);

  final CallHost _host;
  final List<Timer> _timers = [];
  bool _over = false;
  int _ticks = 0;

  static const _heard = "What's on my calendar tomorrow?";
  static const _reply =
      'Tomorrow you have a design review at ten, then lunch with Priya.';
  static const _toolRun = 'calendar · tomorrow';

  static const _lunch = ClarifyQuestion(
    id: 'lunch',
    text: 'Add lunch with Priya to the calendar?',
    choices: [
      ClarifyChoice(label: 'Add it', value: 'add'),
      ClarifyChoice(label: 'Leave it', value: 'leave'),
    ],
  );

  static final _question = QuestionDecision(
    ClarifyRequest(
      requestId: 'demo-question',
      sessionId: 'demo',
      questions: const [_lunch],
    ),
    _lunch,
  );

  @override
  Future<Result<void>> preflight(
    void Function(PreflightStep step) onStep,
  ) async {
    for (final step in const [
      PreflightStep.agent,
      PreflightStep.speechToText,
      PreflightStep.textToSpeech,
    ]) {
      onStep(step);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return const Ok(null);
  }

  @override
  Future<void> start() async {
    _timers.add(
      Timer.periodic(const Duration(milliseconds: 100), (_) => _drive()),
    );
    _at(0, () => _set(CallMode.listening));
    _at(1200, () {
      _set(CallMode.hearing);
      _say(you: true, text: _heard);
    });
    _at(2400, () {
      _host.markWorking(_host.now);
      _set(CallMode.thinking);
    });
    _at(3400, () => _set(CallMode.tool, tool: _toolRun));
    _at(4400, () {
      _host.update((s) => s.copyWith(toolTrail: [...s.toolTrail, _toolRun]));
      _set(CallMode.needs, decision: _question);
      _host.markWorking(null);
    });
    _at(6400, () {
      _set(CallMode.speaking);
      _say(you: false, text: _reply);
    });
    _at(9000, () => _set(CallMode.listening));
  }

  void _at(int milliseconds, void Function() action) {
    _timers.add(
      Timer(Duration(milliseconds: milliseconds), () {
        if (!_over) action();
      }),
    );
  }

  void _set(CallMode mode, {String? tool, CallDecision? decision}) {
    _host.update(
      (s) => s.copyWith(
        mode: mode,
        tool: tool,
        clearTool: tool == null,
        decision: decision,
        clearDecision: decision == null,
      ),
    );
  }

  void _say({required bool you, required String text}) {
    _host.update(
      (s) => s.copyWith(
        transcript: [
          ...s.transcript,
          Caption(you: you, text: text),
        ],
      ),
    );
  }

  /// Simulated levels: a small wave while listening, a louder one while the
  /// person speaks, a steadier one while Iris speaks, and none otherwise.
  void _drive() {
    final t = _ticks++ / 3.0;
    _host.level.value = switch (_host.state.mode) {
      CallMode.listening => 0.12 + 0.08 * sin(t),
      CallMode.hearing => 0.5 + 0.3 * sin(t),
      CallMode.speaking => 0.4 + 0.25 * sin(t),
      _ => 0.0,
    };
  }

  @override
  Future<void> end() async {
    _over = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  Future<void> setMuted({required bool muted}) async {}

  @override
  Future<void> hold({required bool down}) async {}

  @override
  Future<void> setStyle(CallStyle style) async {}

  @override
  Future<void> pause(PauseReason reason) async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> retryHeld() async {}

  @override
  Future<void> linkChanged({required bool live}) async {}
}

/// The demo's platform seams. The scripted call never touches them, so the
/// microphone in particular fails loudly if anything tries to open it.
final class _DemoMic implements MicCapture {
  @override
  Future<bool> start() =>
      throw StateError('A demo call never opens the microphone.');

  @override
  Stream<Uint8List> get pcm => const Stream.empty();

  @override
  Future<void> stop() async {}
}

final class _DemoOut implements AudioOut {
  @override
  Future<void> startPcm(int sampleRate) async {}

  @override
  void addPcm(Uint8List pcm) {}

  @override
  Future<void> endPcm() async {}

  @override
  Future<void> playFile(Uint8List bytes, String mime) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<double> get level => const Stream.empty();
}

final class _DemoRoute implements AudioRoute {
  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Stream<InterruptionKind> get interruptions => const Stream.empty();

  @override
  Stream<void> get becameNoisy => const Stream.empty();

  @override
  Stream<RouteInfo> get route => const Stream.empty();

  @override
  Future<void> setSpeaker({required bool on}) async {}
}

final class _DemoAwake implements ScreenAwake {
  @override
  Future<void> hold() async {}

  @override
  Future<void> release() async {}
}

/// The seams for a scripted call in demo mode. [settings] is what a real call
/// reads; the demo's call reads none of them.
CallParts demoCallParts(VoiceSettings settings) => CallParts(
  mic: _DemoMic(),
  out: _DemoOut(),
  route: _DemoRoute(),
  awake: _DemoAwake(),
  scripted: DemoCallEngine.new,
);
