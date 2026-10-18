/// The chained call loop, as Hermes Desktop and Conduit run it: Iris listens,
/// sends the take to speech-to-text, submits the words as a voice turn, and
/// speaks the reply through the speak stream as it is written.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../app/voice_providers.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_event.dart';
import '../../data/chat/chat_models.dart';
import '../../data/voice/speak_stream.dart';
import '../../data/voice/transcribe_stream.dart';
import '../../data/voice/voice_backend.dart';
import '../../data/voice/voice_capabilities.dart';
import '../chat/chat_controller.dart';
import 'audio/audio_out.dart';
import 'audio/mic_capture.dart';
import 'barge_in.dart';
import 'levels.dart';
import 'preflight.dart';
import 'speech_detector.dart';
import 'spoken.dart';
import 'thinking_sound.dart';
import 'voice_call.dart';

/// 16 kHz mono 16-bit [pcm] as a WAV file, for `POST /api/audio/transcribe`.
Uint8List wavOf(Uint8List pcm) {
  const rate = RecordMicCapture.sampleRate;
  final header = ByteData(44);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per frame
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}

enum _Phase {
  idle,

  /// The mic is open (hands-free) or waiting for the button (push to talk).
  listening,

  /// Push to talk, button down.
  holding,
  transcribing,

  /// A turn is running; nothing is playing yet.
  working,

  /// Iris's reply is playing.
  speaking,
  paused,
  ended,
}

final class ChainedEngine implements CallEngine {
  ChainedEngine(
    this._host, {
    required ChatController chat,
    required ChatBackend backend,
    required VoiceBackend voice,
    required VoiceCapabilities capabilities,
    required MicCapture mic,
    required AudioOut out,
    String server = defaultServerName,
  }) : _server = server,
       _chat = chat,
       _backend = backend,
       _voice = voice,
       _caps = capabilities,
       _mic = mic,
       _out = out,
       _detector = SpeechDetector(capabilities.tuning),
       _thinking = ThinkingSound(out);

  static const _log = IrisLog('voice.call');

  static const _speakRoute = '/api/audio/speak-stream';
  static const _transcribeRoute = '/api/audio/transcribe-stream';
  static const _micFailedCopy = "Iris can't use the microphone.";

  /// A take shorter than this is a tap, not words.
  static const _shortest = Duration(milliseconds: 400);

  /// Chunks kept from before a take starts, so its first syllable is not cut.
  static const _preroll = 3;

  /// The room's floor is measured over this long before playback.
  static const _floorWindow = Duration(milliseconds: 300);

  /// How much of the mic is kept while Iris speaks, to seed a barge-in take.
  static const _recentWindow = Duration(seconds: 1);

  final CallHost _host;
  final String _server;
  final ChatController _chat;
  final ChatBackend _backend;
  final VoiceBackend _voice;
  final VoiceCapabilities _caps;
  final MicCapture _mic;
  final AudioOut _out;
  final SpeechDetector _detector;
  final ThinkingSound _thinking;

  VoiceTuning get _tuning => _caps.tuning;

  _Phase _phase = _Phase.idle;
  late CallStyle _style;
  bool _muted = false;
  bool _linkDown = false;

  /// Bumped whenever what is in flight stops mattering (a barge-in, a pause,
  /// the end), so late answers are dropped.
  int _gen = 0;

  StreamSubscription<ChatEvent>? _events;
  StreamSubscription<double>? _outLevel;

  // The microphone. Time is counted in audio, not wall clock.
  StreamSubscription<Uint8List>? _micSub;
  Duration _micTime = Duration.zero;

  // The take being recorded.
  final _take = BytesBuilder(copy: false);
  final _before = ListQueue<Uint8List>();
  Duration _takeClock = Duration.zero;
  Duration _holdLength = Duration.zero;
  bool _capturing = false;
  bool _speechHeard = false;
  TranscribeStream? _live;
  StreamSubscription<String>? _partials;
  bool _partialShown = false;
  Uint8List? _heldWav;
  bool _interruptNext = false;

  /// The interrupted turn's end events, still to come after a barge-in.
  bool _dropNextEnd = false;

  // The turn and its reply.
  bool _turnActive = false;
  final _reply = StringBuffer();
  bool _replyComplete = false;
  int? _irisCaption;
  SpeakStream? _speak;
  StreamSubscription<SpeakFrame>? _speakSub;
  Future<void> _frames = Future.value();
  bool _speakOpening = false;
  bool _speakFailed = false;
  final _pendingText = <String>[];
  bool _pendingDone = false;
  bool _audioStarted = false;
  int _rate = 24000;
  String _lastSpoken = '';

  // Barge-in.
  BargeInDetector? _barge;
  Duration _playbackStart = Duration.zero;
  final _recent = ListQueue<(Duration, double, Uint8List)>();

  /// The leases were taken, and are given back at the end.
  bool _leased = false;

  @override
  Future<Result<void>> preflight(void Function(PreflightStep step) onStep) {
    _leased = true;
    return chainedPreflight(
      chat: _chat,
      voice: _voice,
      server: _server,
      onStep: onStep,
    );
  }

  @override
  Future<void> start() async {
    if (_phase != _Phase.idle) return;
    _style = _host.state.style;
    _events = _backend.events.listen(_onEvent);
    _outLevel = _out.level.listen((level) {
      if (_phase == _Phase.speaking) _host.level.value = level;
    });
    await _listen();
  }

  // ---------------------------------------------------------------- modes

  CallMode get _phaseMode => switch (_phase) {
    _Phase.idle => CallMode.connecting,
    _Phase.listening =>
      _muted
          ? CallMode.muted
          : _speechHeard
          ? CallMode.hearing
          : CallMode.listening,
    _Phase.holding => CallMode.hearing,
    _Phase.transcribing => CallMode.thinking,
    _Phase.working =>
      _host.state.tool != null ? CallMode.tool : CallMode.thinking,
    _Phase.speaking => CallMode.speaking,
    _Phase.paused => CallMode.paused,
    _Phase.ended => CallMode.ended,
  };

  void _refresh() {
    final mode = _linkDown && _phase != _Phase.paused && _phase != _Phase.ended
        ? CallMode.reconnecting
        : _phaseMode;
    if (_host.state.mode != mode) {
      _host.update((s) => s.copyWith(mode: mode));
    }
  }

  // ------------------------------------------------------------ listening

  Future<void> _listen() async {
    if (_phase == _Phase.ended) return;
    _phase = _Phase.listening;
    _resetTake();
    _host.markWorking(null);
    _host.level.value = 0;
    _refresh();
    if (_muted || _linkDown || _style == CallStyle.pushToTalk) {
      await _closeMic();
    } else {
      await _openMic();
    }
  }

  void _resetTake() {
    _detector.reset();
    _takeClock = Duration.zero;
    _holdLength = Duration.zero;
    _take.clear();
    _before.clear();
    _capturing = false;
    _speechHeard = false;
    final live = _live;
    _live = null;
    if (live != null) unawaited(live.cancel());
    unawaited(_partials?.cancel());
    _partials = null;
  }

  Future<bool> _openMic() async {
    if (_micSub != null) return true;
    _micTime = Duration.zero;
    _micSub = _mic.pcm.listen(_onPcm);
    if (await _mic.start()) return true;
    unawaited(_micSub?.cancel());
    _micSub = null;
    await _host.finish(failure: _micFailedCopy);
    return false;
  }

  Future<void> _closeMic() async {
    final sub = _micSub;
    if (sub == null) return;
    _micSub = null;
    unawaited(sub.cancel());
    await _mic.stop();
  }

  void _onPcm(Uint8List chunk) {
    final length = Duration(
      microseconds:
          (chunk.length ~/ 2) * 1000000 ~/ RecordMicCapture.sampleRate,
    );
    _micTime += length;
    final rms = rmsOf(chunk);
    switch (_phase) {
      case _Phase.listening:
        _host.level.value = orbLevel(rms);
        _feedTake(chunk, rms, length);
      case _Phase.holding:
        _host.level.value = orbLevel(rms);
        _take.add(chunk);
        _live?.add(chunk);
        _holdLength += length;
        if (_holdLength >= _tuning.maxRecording) unawaited(_endTake());
      case _Phase.working:
        _remember(chunk, rms);
      case _Phase.speaking:
        _remember(chunk, rms);
        _checkBargeIn(rms);
      case _Phase.idle || _Phase.transcribing || _Phase.paused || _Phase.ended:
        break;
    }
  }

  void _feedTake(Uint8List chunk, double rms, Duration length) {
    _takeClock += length;
    final event = _detector.feed(rms, _takeClock);
    if (!_capturing && _detector.inTake) {
      _capturing = true;
      _before.forEach(_take.add);
      _before.clear();
    }
    if (_capturing) {
      _take.add(chunk);
      _live?.add(chunk);
    } else {
      _before.add(chunk);
      while (_before.length > _preroll) {
        _before.removeFirst();
      }
    }
    switch (event) {
      case SpeechStarted():
        _speechHeard = true;
        _refresh();
        _startLive();
      case SpeechEnded():
        unawaited(_endTake());
      case null:
        if (_capturing && !_detector.inTake) {
          // Too short to be words: dropped without a word to anyone.
          _resetTake();
          _refresh();
        }
    }
  }

  /// With `stt.streaming`, the take also goes to the transcribe stream as it
  /// is recorded, for the words so far and a quicker final transcript.
  void _startLive() {
    if (!_caps.liveTranscription || _live != null) return;
    final gen = _gen;
    unawaited(() async {
      final opened = await _voice.openSocket(_transcribeRoute);
      final socket = opened.valueOrNull;
      if (socket == null) return;
      final recording = _capturing || _phase == _Phase.holding;
      if (gen != _gen || !recording || _live != null) {
        await socket.close();
        return;
      }
      final live = _live = TranscribeStream(socket);
      final sofar = _take.toBytes();
      if (sofar.isNotEmpty) live.add(sofar);
      _partials = live.partials.listen(_showPartial);
    }());
  }

  void _showPartial(String text) {
    final words = text.trim();
    if (words.isEmpty) return;
    _host.update((s) {
      final list = [...s.transcript];
      if (_partialShown && list.isNotEmpty) {
        list[list.length - 1] = list.last.withText(words);
      } else {
        list.add(Caption(you: true, text: words));
      }
      return s.copyWith(transcript: list);
    });
    _partialShown = true;
  }

  void _dropPartial() {
    if (!_partialShown) return;
    _partialShown = false;
    _host.update(
      (s) => s.copyWith(
        transcript: s.transcript.sublist(0, s.transcript.length - 1),
      ),
    );
  }

  Future<void> _endTake() async {
    if (_phase != _Phase.listening && _phase != _Phase.holding) return;
    final gen = _gen;
    _phase = _Phase.transcribing;
    _capturing = false;
    _speechHeard = false;
    final wav = wavOf(_take.takeBytes());
    final live = _live;
    _live = null;
    _host.level.value = 0;
    _refresh();
    await _closeMic();

    Result<String>? heard;
    if (live != null) {
      heard = await live.finish();
      unawaited(_partials?.cancel());
      _partials = null;
    }
    if (gen != _gen) return;
    if (heard == null || heard is Err) heard = await _transcribe(wav);
    if (gen != _gen) return;
    await _heard(heard, wav);
  }

  /// One retry before giving up on the upload.
  Future<Result<String>> _transcribe(Uint8List wav) async {
    final first = await _voice.transcribe(wav);
    if (first is Ok) return first;
    return _voice.transcribe(wav);
  }

  Future<void> _heard(Result<String> heard, Uint8List wav) async {
    switch (heard) {
      case Err():
        _heldWav = wav;
        _dropPartial();
        _host.update((s) => s.copyWith(heldTake: true));
        await _listen();
      case Ok(value: final transcript):
        _heldWav = null;
        if (_host.state.heldTake) {
          _host.update((s) => s.copyWith(heldTake: false));
        }
        final text = transcript.trim();
        if (text.isEmpty || isEcho(text, _lastSpoken)) {
          _dropPartial();
          await _listen();
        } else if (isStopPhrase(text, _tuning.stopPhrases)) {
          await _host.finish();
        } else {
          await _submit(text);
        }
    }
  }

  @override
  Future<void> retryHeld() async {
    final wav = _heldWav;
    if (wav == null || _phase != _Phase.listening) return;
    _resetTake();
    _phase = _Phase.transcribing;
    _refresh();
    await _closeMic();
    final gen = _gen;
    final heard = await _transcribe(wav);
    if (gen != _gen) return;
    await _heard(heard, wav);
  }

  // ----------------------------------------------------------------- turn

  Future<void> _submit(String text) async {
    _phase = _Phase.working;
    _turnActive = true;
    _resetReply();
    _host.update((s) {
      final list = [...s.transcript];
      if (_partialShown && list.isNotEmpty) {
        list[list.length - 1] = Caption(you: true, text: text);
      } else {
        list.add(Caption(you: true, text: text));
      }
      return s.copyWith(transcript: list, clearTool: true, toolTrail: const []);
    });
    _partialShown = false;
    _host.markWorking(_host.now);
    _refresh();
    if (_tuning.thinkingSound) _thinking.start(_rate);

    final interrupted = _interruptNext;
    _interruptNext = false;
    final sent = await _chat.sendVoice(
      text,
      VoiceSubmit(voiceTurn: true, interrupted: interrupted),
    );
    if (!sent && _turnActive && _phase == _Phase.working && !_audioStarted) {
      _turnActive = false;
      await _thinking.stop();
      await _listen();
    }
  }

  void _resetReply() {
    _reply.clear();
    _replyComplete = false;
    _irisCaption = null;
    _speak = null;
    _speakSub = null;
    _speakOpening = false;
    _speakFailed = false;
    _pendingText.clear();
    _pendingDone = false;
    _audioStarted = false;
    _barge = null;
    _recent.clear();
  }

  bool _ours(ChatEvent event) =>
      event.sessionId.isNotEmpty &&
      (event.sessionId == _chat.runtimeId ||
          event.sessionId == _chat.conversationId);

  void _onEvent(ChatEvent event) {
    if (_phase == _Phase.ended || !_ours(event)) return;
    final ending =
        event is MessageCompleted ||
        event is TurnFailed ||
        event is TurnInterrupted;
    if (_dropNextEnd) {
      // The interrupted turn's own ending, however many events it takes,
      // until the next turn shows signs of life.
      if (ending) return;
      if (event is MessageStarted ||
          event is TextDelta ||
          event is ToolStarted) {
        _dropNextEnd = false;
      }
    }
    if (!_turnActive) return;
    switch (event) {
      case TextDelta(:final text):
        _onText(text);
      case MessageCompleted(:final content):
        unawaited(_onComplete(content));
      case ToolStarted(:final name, :final input):
        final detail = input?.trim() ?? '';
        final label = detail.isEmpty ? name : '$name · $detail';
        _host.update((s) => s.copyWith(tool: label));
        _refresh();
      case ToolCompleted():
        final tool = _host.state.tool;
        if (tool != null) {
          _host.update(
            (s) =>
                s.copyWith(clearTool: true, toolTrail: [...s.toolTrail, tool]),
          );
        }
        _refresh();
      case TurnFailed() || TurnInterrupted():
        unawaited(_onComplete(null));
      default:
        break;
    }
  }

  void _onText(String text) {
    if (text.isEmpty) return;
    _reply.write(text);
    _showReply();
    if (_phase == _Phase.paused) return;
    _queueSpeech(text);
  }

  void _showReply({bool? spoken}) {
    final text = _reply.toString().trim();
    if (text.isEmpty) return;
    _host.update((s) {
      final list = [...s.transcript];
      final at = _irisCaption;
      if (at == null || at >= list.length) {
        _irisCaption = list.length;
        list.add(Caption(you: false, text: text, spoken: spoken ?? true));
      } else {
        list[at] = list[at].withText(text, spoken: spoken);
      }
      return s.copyWith(transcript: list);
    });
  }

  void _queueSpeech(String text) {
    final speak = _speak;
    if (speak != null) {
      speak.add(text);
      return;
    }
    _pendingText.add(text);
    if (!_speakOpening && !_speakFailed && text.trim().isNotEmpty) {
      unawaited(_openSpeak());
    }
  }

  Future<void> _openSpeak() async {
    _speakOpening = true;
    final gen = _gen;
    // The mic opens with the reply: its first 300 ms are the room's floor
    // for barge-in, which only listens once Iris speaks.
    if (_bargeInArmed) unawaited(_openMic());
    final opened = await _voice.openSocket(_speakRoute);
    if (gen != _gen || _phase == _Phase.ended) {
      if (opened case Ok(value: final socket)) await socket.close();
      return;
    }
    _speakOpening = false;
    switch (opened) {
      case Err():
        _speakFailed = true;
        _pendingText.clear();
        if (_replyComplete) await _fallback();
      case Ok(value: final socket):
        final speak = _speak = SpeakStream(socket);
        _pendingText
          ..forEach(speak.add)
          ..clear();
        if (_pendingDone) speak.done();
        _speakSub = speak.frames.listen((frame) {
          // One at a time, in order; a failure is logged, not left to stop
          // every frame after it.
          _frames = _frames.then((_) => _onFrame(frame, speak, gen)).catchError(
            (Object error, StackTrace stack) {
              _log.error('speak frame failed', cause: error, stackTrace: stack);
            },
          );
        });
    }
  }

  bool get _bargeInArmed =>
      _tuning.bargeIn && _style == CallStyle.handsFree && !_muted && !_linkDown;

  Future<void> _onComplete(String? content) async {
    if (_reply.isEmpty && content != null && content.trim().isNotEmpty) {
      _reply.write(content);
      _showReply();
      if (_phase != _Phase.paused) _queueSpeech(content);
    }
    _replyComplete = true;
    if (_phase == _Phase.paused) return;
    final speak = _speak;
    if (speak != null) {
      speak.done();
    } else if (_speakOpening) {
      _pendingDone = true;
    } else if (_speakFailed) {
      await _fallback();
    } else if (!_audioStarted) {
      // Nothing to say: a tool-only turn, or no words at all.
      await _thinking.stop();
      await _finishReply(spoken: false);
    }
  }

  Future<void> _onFrame(SpeakFrame frame, SpeakStream speak, int gen) async {
    if (gen != _gen || !identical(speak, _speak)) return;
    switch (frame) {
      case SpeakStart(:final sampleRate):
        await _thinking.stop();
        if (gen != _gen) return;
        _rate = sampleRate;
        _beginPlayback();
        await _out.startPcm(sampleRate);
      case SpeakPcm(:final pcm):
        if (_audioStarted) _out.addPcm(pcm);
      case SpeakEnd():
        _speak = null;
        _speakSub = null;
        if (_audioStarted) await _out.endPcm();
        if (gen != _gen) return;
        if (_replyComplete) {
          await _finishReply(spoken: _audioStarted);
        } else {
          // The socket closed early; what is left goes in one piece.
          _speakFailed = true;
        }
      case SpeakFallback():
        _speak = null;
        _speakSub = null;
        _speakFailed = true;
        if (_audioStarted) await _out.endPcm();
        if (gen != _gen) return;
        if (_replyComplete) await _fallback();
    }
  }

  void _beginPlayback() {
    _phase = _Phase.speaking;
    _audioStarted = true;
    _host.markWorking(null);
    final barge = BargeInDetector(_tuning);
    final from = _micTime - _floorWindow;
    for (final (at, rms, _) in _recent) {
      if (at > from) barge.calibrate(rms);
    }
    _barge = barge;
    _playbackStart = _micTime;
    _refresh();
  }

  /// The speak stream gave up: the whole reply as one clip, minus code.
  Future<void> _fallback() async {
    final gen = _gen;
    await _thinking.stop();
    final text = speakable(_reply.toString());
    if (text.isEmpty) {
      await _finishReply(spoken: false);
      return;
    }
    final audio = await _voice.speakOnce(text);
    if (gen != _gen) return;
    switch (audio) {
      case Err():
        await _finishReply(spoken: false);
      case Ok(value: final clip):
        _beginPlayback();
        await _out.playFile(clip.bytes, clip.mime);
        if (gen != _gen) return;
        await _finishReply(spoken: true);
    }
  }

  Future<void> _finishReply({required bool spoken}) async {
    _lastSpoken = _reply.toString();
    if (!spoken) _showReply(spoken: false);
    _turnActive = false;
    _barge = null;
    _speak = null;
    await _listen();
  }

  // ------------------------------------------------------------- barge-in

  void _remember(Uint8List chunk, double rms) {
    _recent.add((_micTime, rms, chunk));
    while (_recent.isNotEmpty && _recent.first.$1 <= _micTime - _recentWindow) {
      _recent.removeFirst();
    }
  }

  void _checkBargeIn(double rms) {
    final barge = _barge;
    if (barge == null || !_bargeInArmed) return;
    if (barge.feed(rms, _micTime - _playbackStart)) {
      unawaited(_bargeIn(seed: true));
    }
  }

  /// The person spoke over Iris: silence it, stop the turn if it is still
  /// running, and let what they are saying become the next turn.
  Future<void> _bargeIn({required bool seed}) async {
    _gen++;
    _barge = null;
    final heard = [for (final (_, _, chunk) in _recent) chunk];
    _recent.clear();
    final speak = _speak;
    _speak = null;
    _pendingText.clear();
    _lastSpoken = _reply.toString();
    final running = _turnActive && _chat.value.running;
    _turnActive = false;
    _host.update((s) => s.copyWith(mode: CallMode.interrupted));

    // The take that tripped it carries on.
    _phase = _Phase.listening;
    _resetTake();
    if (seed) {
      _speechHeard = true;
      for (final chunk in heard) {
        _feedTake(
          chunk,
          rmsOf(chunk),
          Duration(
            microseconds:
                (chunk.length ~/ 2) * 1000000 ~/ RecordMicCapture.sampleRate,
          ),
        );
      }
    }

    unawaited(_speakSub?.cancel());
    _speakSub = null;
    await _thinking.stop();
    if (speak != null) unawaited(speak.stop());
    await _out.stop();
    if (running) {
      _dropNextEnd = true;
      await _chat.stop();
    }
    _interruptNext = true;
    if (_phase == _Phase.listening) _refresh();
  }

  // ------------------------------------------------------------- controls

  @override
  Future<void> setMuted({required bool muted}) async {
    if (_muted == muted || _phase == _Phase.ended) return;
    _muted = muted;
    _host.update((s) => s.copyWith(muted: muted));
    switch (_phase) {
      case _Phase.listening || _Phase.holding:
        if (muted) {
          _phase = _Phase.listening;
          _resetTake();
          _refresh();
          await _closeMic();
        } else {
          await _listen();
        }
      case _Phase.working || _Phase.speaking:
        if (muted) {
          await _closeMic();
        } else if (_bargeInArmed && (_speak != null || _audioStarted)) {
          await _openMic();
        }
      case _Phase.idle || _Phase.transcribing || _Phase.paused || _Phase.ended:
        break;
    }
    _refresh();
  }

  @override
  Future<void> hold({required bool down}) async {
    if (_style != CallStyle.pushToTalk || _muted || _linkDown) return;
    if (down) {
      if (_phase == _Phase.speaking) await _bargeIn(seed: false);
      if (_phase != _Phase.listening) return;
      _resetTake();
      _phase = _Phase.holding;
      _refresh();
      if (!await _openMic()) return;
      _startLive();
    } else {
      if (_phase != _Phase.holding) return;
      if (_holdLength < _shortest) {
        await _listen();
      } else {
        await _endTake();
      }
    }
  }

  @override
  Future<void> setStyle(CallStyle style) async {
    if (style == _style) return;
    _style = style;
    switch (_phase) {
      case _Phase.listening || _Phase.holding:
        await _listen();
      case _Phase.working || _Phase.speaking:
        if (!_bargeInArmed) await _closeMic();
      case _Phase.idle || _Phase.transcribing || _Phase.paused || _Phase.ended:
        break;
    }
  }

  @override
  Future<void> pause(PauseReason reason) async {
    if (_phase == _Phase.ended || _phase == _Phase.paused) return;
    _gen++;
    _phase = _Phase.paused;
    _host.update((s) => s.copyWith(paused: reason));
    _host.level.value = 0;
    _refresh();
    final speak = _speak;
    _speak = null;
    _speakOpening = false;
    _speakFailed = false;
    _pendingText.clear();
    _pendingDone = false;
    _audioStarted = false;
    _barge = null;
    _resetTake();
    unawaited(_speakSub?.cancel());
    _speakSub = null;
    await _thinking.stop();
    if (speak != null) unawaited(speak.stop());
    await Future.wait([_out.stop(), _closeMic()]);
  }

  /// Carries on after a pause: a reply that arrived or was cut off meanwhile
  /// is spoken in full, then the call listens.
  @override
  Future<void> resume() async {
    if (_phase != _Phase.paused) return;
    _host.update((s) => s.copyWith(clearPaused: true));
    if (!_turnActive) {
      await _listen();
      return;
    }
    _phase = _Phase.working;
    _refresh();
    final owed = _reply.toString();
    if (owed.trim().isNotEmpty) {
      _pendingText
        ..clear()
        ..add(owed);
      _pendingDone = _replyComplete;
      await _openSpeak();
    } else if (_replyComplete) {
      await _finishReply(spoken: false);
    } else if (_tuning.thinkingSound) {
      _thinking.start(_rate);
    }
  }

  @override
  Future<void> linkChanged({required bool live}) async {
    if (_phase == _Phase.ended || _linkDown == !live) return;
    _linkDown = !live;
    if (!live) {
      if (_phase == _Phase.listening || _phase == _Phase.holding) {
        _phase = _Phase.listening;
        _resetTake();
        await _closeMic();
      }
      _refresh();
    } else if (_phase == _Phase.listening) {
      await _listen();
    } else {
      _refresh();
    }
  }

  @override
  Future<void> end() async {
    if (_phase == _Phase.ended) return;
    _gen++;
    _phase = _Phase.ended;
    if (_leased) {
      _leased = false;
      unawaited(_voice.lease(speech: false, active: false));
      unawaited(_voice.lease(speech: true, active: false));
    }
    _turnActive = false;
    unawaited(_events?.cancel());
    unawaited(_outLevel?.cancel());
    final speak = _speak;
    _speak = null;
    _resetTake();
    unawaited(_speakSub?.cancel());
    _speakSub = null;
    await _thinking.stop();
    if (speak != null) unawaited(speak.stop());
    await Future.wait([_out.stop(), _closeMic()]);
  }
}
