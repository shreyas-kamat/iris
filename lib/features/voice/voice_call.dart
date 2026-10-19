/// One live voice call on a chat: the state the screen, the notification and
/// the captions read, and the engine that runs it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/voice_providers.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/voice/voice_backend.dart';
import '../../data/voice/voice_capabilities.dart';
import '../chat/chat_controller.dart';
import 'audio/audio_out.dart';
import 'audio/audio_route.dart';
import 'audio/mic_capture.dart';
import 'call_service.dart';
import 'chained_engine.dart';
import 'gpt_live_engine.dart';
import 'live_channel.dart';
import 'preflight.dart';

enum CallMode {
  connecting,
  listening,
  hearing,
  thinking,
  tool,
  speaking,
  interrupted,
  muted,
  needs,
  reconnecting,
  paused,
  error,
  ended,
}

/// What the call checks before it listens, in order.
enum PreflightStep { agent, speechToText, textToSpeech, gptLive }

enum PauseReason { phoneCall, unplugged }

/// One line of the call's transcript.
@immutable
final class Caption {
  const Caption({required this.you, required this.text, this.spoken = true});

  /// Said by the person, not Iris.
  final bool you;
  final String text;

  /// Iris said it aloud (false for a reply with nothing speakable).
  final bool spoken;

  Caption withText(String text, {bool? spoken}) =>
      Caption(you: you, text: text, spoken: spoken ?? this.spoken);

  @override
  bool operator ==(Object other) =>
      other is Caption &&
      other.you == you &&
      other.text == text &&
      other.spoken == spoken;

  @override
  int get hashCode => Object.hash(you, text, spoken);
}

@immutable
final class VoiceCallState {
  const VoiceCallState({
    required this.mode,
    required this.level,
    required this.style,
    required this.route,
    this.step,
    this.failure,
    this.elapsed = Duration.zero,
    this.workingFor,
    this.muted = false,
    this.captions = false,
    this.tool,
    this.toolTrail = const [],
    this.transcript = const [],
    this.paused,
    this.heldTake = false,
  });

  final CallMode mode;

  /// The check under way while [mode] is connecting.
  final PreflightStep? step;

  /// Why the call stopped, for people, while [mode] is error.
  final String? failure;

  /// 0..1: the microphone while listening, playback while speaking.
  final ValueListenable<double> level;
  final Duration elapsed;

  /// How long the agent has been on this turn.
  final Duration? workingFor;
  final bool muted;
  final CallStyle style;
  final bool captions;

  /// The running tool, "name · input".
  final String? tool;

  /// This turn's finished tools, oldest first.
  final List<String> toolTrail;
  final List<Caption> transcript;
  final RouteInfo route;
  final PauseReason? paused;

  /// A take whose transcription failed is kept for Try again.
  final bool heldTake;

  bool get isOver => mode == CallMode.ended || mode == CallMode.error;

  VoiceCallState copyWith({
    CallMode? mode,
    PreflightStep? step,
    bool clearStep = false,
    String? failure,
    Duration? elapsed,
    Duration? workingFor,
    bool clearWorkingFor = false,
    bool? muted,
    CallStyle? style,
    bool? captions,
    String? tool,
    bool clearTool = false,
    List<String>? toolTrail,
    List<Caption>? transcript,
    RouteInfo? route,
    PauseReason? paused,
    bool clearPaused = false,
    bool? heldTake,
  }) => VoiceCallState(
    mode: mode ?? this.mode,
    level: level,
    step: clearStep ? null : step ?? this.step,
    failure: failure ?? this.failure,
    elapsed: elapsed ?? this.elapsed,
    workingFor: clearWorkingFor ? null : workingFor ?? this.workingFor,
    muted: muted ?? this.muted,
    style: style ?? this.style,
    captions: captions ?? this.captions,
    tool: clearTool ? null : tool ?? this.tool,
    toolTrail: toolTrail ?? this.toolTrail,
    transcript: transcript ?? this.transcript,
    route: route ?? this.route,
    paused: clearPaused ? null : paused ?? this.paused,
    heldTake: heldTake ?? this.heldTake,
  );
}

/// What an engine is given by its call: the state to read and move, the
/// level to drive, and a way to end the call.
abstract interface class CallHost {
  VoiceCallState get state;
  void update(VoiceCallState Function(VoiceCallState state) change);
  ValueNotifier<double> get level;

  DateTime get now;

  /// The agent started on a turn [since] then; null when it is done.
  void markWorking(DateTime? since);

  /// Ends the call from inside (a stop phrase), or fails it with [failure].
  Future<void> finish({String? failure});
}

/// How a call actually talks: the chained loop (Iris records, transcribes,
/// submits and speaks) or GPT-Live (the server's realtime model).
abstract interface class CallEngine {
  Future<Result<void>> preflight(void Function(PreflightStep step) onStep);
  Future<void> start();
  Future<void> setMuted({required bool muted});

  /// Push to talk: the button went [down] or came up.
  Future<void> hold({required bool down});
  Future<void> setStyle(CallStyle style);
  Future<void> pause(PauseReason reason);
  Future<void> resume();
  Future<void> retryHeld();

  /// The live link to the agent dropped ([live] false) or came back.
  Future<void> linkChanged({required bool live});
  Future<void> end();
}

final class VoiceCall extends ValueNotifier<VoiceCallState> {
  VoiceCall({
    required ChatController chat,
    required ChatBackend backend,
    required VoiceBackend voice,
    required VoiceCapabilities capabilities,
    required VoiceSettings settings,
    required MicCapture mic,
    required AudioOut out,
    required AudioRoute route,
    this.server = defaultServerName,
    LivePeer Function()? livePeer,
    CallService? service,
    DateTime Function() clock = DateTime.now,
  }) : _backend = backend,
       engine = capabilities.engine,
       _route = route,
       _service = service,
       _clock = clock,
       super(
         VoiceCallState(
           mode: CallMode.connecting,
           level: ValueNotifier(0),
           style: settings.style,
           captions: settings.captions,
           route: RouteInfo(speaker: settings.speaker),
         ),
       ) {
    _host = _Host(this);
    _engine = capabilities.engine == VoiceEngine.gptLive
        ? GptLiveEngine(
            _host,
            chat: chat,
            backend: backend,
            voice: voice,
            peer: livePeer ?? WebRtcLivePeer.new,
            server: server,
          )
        : ChainedEngine(
            _host,
            chat: chat,
            backend: backend,
            voice: voice,
            capabilities: capabilities,
            mic: mic,
            out: out,
            server: server,
          );
    _speaker = settings.speaker;
    addListener(_syncNotice);
  }

  static const _noticeTitle = 'Talking with Iris';

  /// Which engine runs this call.
  final VoiceEngine engine;

  /// The server's name, for the header.
  final String server;

  /// The call screen's header (B1 to B10b).
  String get title => engine == VoiceEngine.gptLive
      ? 'VOICE · GPT-LIVE · OPENAI'
      : 'VOICE · ${server.toUpperCase()}';

  /// A link down for this long ends the call.
  static const reconnectBudget = Duration(seconds: 30);

  static const _lostCopy = 'The call ended unexpectedly.';

  final ChatBackend _backend;
  final AudioRoute _route;
  final CallService? _service;
  final DateTime Function() _clock;
  late final _Host _host;
  late final CallEngine _engine;
  late bool _speaker;

  Future<void>? _begun;
  Future<void>? _ended;
  bool _over = false;
  bool _routeActive = false;
  DateTime? _startedAt;
  DateTime? _workingSince;
  Timer? _ticker;
  Timer? _lost;
  StreamSubscription<RouteInfo>? _routeSub;
  StreamSubscription<bool>? _linkSub;
  StreamSubscription<InterruptionKind>? _interruptSub;
  StreamSubscription<void>? _noisySub;
  StreamSubscription<CallAction>? _actionSub;
  bool _serviceOn = false;
  CallNotice? _notice;

  ValueNotifier<double> get _level => value.level as ValueNotifier<double>;

  /// Checks the agent and the audio providers, then listens. Calling it
  /// again shares the first call; after the call is over it does nothing.
  Future<void> begin() => _begun ??= _begin();

  Future<void> _begin() async {
    if (_over) return;
    _startedAt = _clock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    _routeSub = _route.route.listen((info) {
      if (!_over) value = value.copyWith(route: info);
    });
    _linkSub = _backend.liveChanges.listen(_onLink);
    // A phone call or the assistant takes the audio: pause, and leave Resume
    // to the person, even when the interruption ends.
    _interruptSub = _route.interruptions.listen((kind) {
      if (kind == InterruptionKind.began) {
        unawaited(pause(PauseReason.phoneCall));
      }
    });
    _noisySub = _route.becameNoisy.listen(
      (_) => unawaited(pause(PauseReason.unplugged)),
    );
    _routeActive = true;
    await _route.activate();
    await _route.setSpeaker(on: _speaker);
    if (_over) return;

    final checked = await _engine.preflight((step) {
      if (!_over) value = value.copyWith(step: step);
    });
    if (_over) return;
    if (checked case Err(:final failure)) {
      await _stop(failure: failure.message ?? _lostCopy);
      return;
    }
    value = value.copyWith(clearStep: true);
    final service = _service;
    if (service != null) {
      _actionSub = service.actions.listen(_onAction);
      final notice = _notice = _currentNotice();
      _serviceOn = true;
      await service.start(notice);
      if (_over) return;
    }
    await _engine.start();
  }

  CallNotice _currentNotice() => CallNotice(
    title: _noticeTitle,
    text: noticeText(value.mode, workingFor: value.workingFor),
    muted: value.muted,
    elapsed: value.elapsed,
  );

  /// The notification follows the call, re-sent only when what it says
  /// changes.
  void _syncNotice() {
    final service = _service;
    if (service == null || !_serviceOn || _over) return;
    final notice = _currentNotice();
    if (notice == _notice) return;
    _notice = notice;
    unawaited(service.update(notice));
  }

  void _onAction(CallAction action) {
    switch (action) {
      case CallAction.mute:
        unawaited(setMuted(muted: true));
      case CallAction.unmute:
        unawaited(setMuted(muted: false));
      case CallAction.end:
        unawaited(end());
    }
  }

  /// Hangs up. Safe to call more than once, and while [begin] is running.
  Future<void> end() => _ended ??= _stop();

  /// Tears everything down once; the mode becomes error with [failure], or
  /// ended.
  Future<void> _stop({String? failure}) async {
    if (_over) {
      if (failure == null && value.mode == CallMode.error) {
        value = value.copyWith(mode: CallMode.ended);
      }
      return;
    }
    _over = true;
    _ticker?.cancel();
    _lost?.cancel();
    value = value.copyWith(
      mode: failure == null ? CallMode.ended : CallMode.error,
      failure: failure,
      clearStep: true,
      clearWorkingFor: true,
      clearTool: true,
    );
    await _engine.end();
    unawaited(_linkSub?.cancel());
    unawaited(_routeSub?.cancel());
    unawaited(_interruptSub?.cancel());
    unawaited(_noisySub?.cancel());
    unawaited(_actionSub?.cancel());
    if (_serviceOn) {
      _serviceOn = false;
      await _service?.stop();
    }
    if (_routeActive) {
      _routeActive = false;
      await _route.deactivate();
    }
    _level.value = 0;
  }

  void _onLink(bool live) {
    if (_over) return;
    if (live) {
      _lost?.cancel();
      _lost = null;
    } else {
      _lost ??= Timer(reconnectBudget, () => _stop(failure: _lostCopy));
    }
    unawaited(_engine.linkChanged(live: live));
  }

  /// Refreshes the clocks; a timer calls it every second.
  void tick() {
    final started = _startedAt;
    if (started == null || _over) return;
    final now = _clock();
    final since = _workingSince;
    value = value.copyWith(
      elapsed: now.difference(started),
      workingFor: since == null ? null : now.difference(since),
      clearWorkingFor: since == null,
    );
  }

  Future<void> setMuted({required bool muted}) async {
    if (_over) return;
    await _engine.setMuted(muted: muted);
  }

  /// Push to talk.
  Future<void> hold({required bool down}) async {
    if (_over) return;
    await _engine.hold(down: down);
  }

  void toggleCaptions() {
    if (_over) return;
    value = value.copyWith(captions: !value.captions);
  }

  Future<void> setStyle(CallStyle style) async {
    if (_over || style == value.style) return;
    value = value.copyWith(style: style);
    await _engine.setStyle(style);
  }

  Future<void> setSpeaker({required bool on}) async {
    _speaker = on;
    if (_over) return;
    await _route.setSpeaker(on: on);
  }

  Future<void> pause(PauseReason reason) async {
    if (_over) return;
    await _engine.pause(reason);
  }

  Future<void> resume() async {
    if (_over) return;
    await _engine.resume();
  }

  Future<void> retryHeld() async {
    if (_over) return;
    await _engine.retryHeld();
  }

  @override
  void dispose() {
    unawaited(end());
    super.dispose();
  }
}

final class _Host implements CallHost {
  _Host(this._call);

  final VoiceCall _call;

  @override
  VoiceCallState get state => _call.value;

  @override
  void update(VoiceCallState Function(VoiceCallState state) change) {
    if (_call._over) return;
    _call.value = change(_call.value);
  }

  @override
  ValueNotifier<double> get level => _call._level;

  @override
  DateTime get now => _call._clock();

  @override
  void markWorking(DateTime? since) {
    _call._workingSince = since;
    _call.tick();
  }

  @override
  Future<void> finish({String? failure}) =>
      failure == null ? _call.end() : _call._stop(failure: failure);
}
