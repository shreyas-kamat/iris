/// A GPT-Live call: OpenAI's realtime model does the listening and talking
/// over WebRTC, and hands real work to Hermes as delegations, which Iris
/// submits as voice-live turns and reports back as commentary.
library;

import 'dart:async';

import '../../app/voice_providers.dart';
import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_event.dart';
import '../../data/chat/chat_models.dart';
import '../../data/voice/voice_backend.dart';
import '../chat/chat_controller.dart';
import 'live_channel.dart';
import 'preflight.dart';
import 'voice_call.dart';

/// The chat's last [turns] messages in Hermes Desktop's history shape.
List<Map<String, Object?>> liveHistory(
  List<TranscriptItem> items, {
  int turns = 10,
}) {
  final seed = ChatController.seedFrom(items);
  final recent = seed.length > turns ? seed.sublist(seed.length - turns) : seed;
  return [
    for (final message in recent)
      {
        'type': 'message',
        'role': message.role,
        'content': [
          {
            'type': message.role == 'user' ? 'input_text' : 'output_text',
            'text': message.content,
          },
        ],
      },
  ];
}

final _sentenceBreak = RegExp(r'(?<=[.!?])\s+|\n+');

/// [text] in pieces of at most [limit] characters, cut between sentences;
/// a sentence longer than that is cut at a space.
List<String> chunkForCommentary(String text, {int limit = 1400}) {
  final pieces = <String>[];
  for (final raw in text.split(_sentenceBreak)) {
    var sentence = raw.trim();
    while (sentence.length > limit) {
      var cut = sentence.lastIndexOf(' ', limit);
      if (cut <= 0) cut = limit;
      pieces.add(sentence.substring(0, cut).trim());
      sentence = sentence.substring(cut).trim();
    }
    if (sentence.isNotEmpty) pieces.add(sentence);
  }
  final chunks = <String>[];
  var current = '';
  for (final piece in pieces) {
    if (current.isEmpty) {
      current = piece;
    } else if (current.length + 1 + piece.length <= limit) {
      current = '$current $piece';
    } else {
      chunks.add(current);
      current = piece;
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

final class _Line {
  _Line(this.role, this.at);

  final String role;
  DateTime at;
  final text = StringBuffer();
}

final class _LiveFailed implements Exception {
  const _LiveFailed(this.message);
  final String message;
}

enum _Phase { idle, live, paused, ended }

final class GptLiveEngine implements CallEngine {
  GptLiveEngine(
    this._host, {
    required ChatController chat,
    required ChatBackend backend,
    required VoiceBackend voice,
    required LivePeer Function() peer,
    String server = defaultServerName,
    Duration budget = const Duration(seconds: 20),
  }) : _chat = chat,
       _backend = backend,
       _voice = voice,
       _makePeer = peer,
       _server = server,
       _budget = budget;

  /// Spoken words this recent are the context of a delegation.
  static const _window = Duration(minutes: 5);
  static const _contextLimit = 6000;
  static const _speakingAbove = 0.05;
  static const _hearingFor = Duration(milliseconds: 1500);

  final CallHost _host;
  final ChatController _chat;
  final ChatBackend _backend;
  final VoiceBackend _voice;
  final LivePeer Function() _makePeer;
  final String _server;
  final Duration _budget;

  LivePeer? _peer;
  Completer<void>? _started;
  StreamSubscription<Json>? _liveSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<ChatEvent>? _chatSub;
  Timer? _hearingTimer;

  _Phase _phase = _Phase.idle;
  late CallStyle _style = _host.state.style;
  bool _muted = false;
  bool _holding = false;
  bool _linkDown = false;
  bool _hearing = false;
  bool _speaking = false;

  final _lines = <_Line>[];
  final _delegations = <String>{};
  bool _turnActive = false;
  final _reply = StringBuffer();

  // ----------------------------------------------------------- preflight

  @override
  Future<Result<void>> preflight(
    void Function(PreflightStep step) onStep,
  ) async {
    onStep(PreflightStep.agent);
    final live = await _chat.ensureLive().timeout(
      _budget,
      onTimeout: () => false,
    );
    if (!live) return _fail("Iris can't reach the agent on $_server");

    onStep(PreflightStep.gptLive);
    final peer = _peer = _makePeer();
    try {
      final sdp = await peer.offer().timeout(_budget);
      final answered = await _voice.startGptLive(
        sdp,
        liveHistory(_chat.value.items),
      );
      switch (answered) {
        case Err(:final failure):
          await peer.close();
          return _fail(_couldNot(failure.message ?? 'no reason was given.'));
        case Ok(value: final answer):
          final started = _started = Completer<void>();
          // Listening before the answer goes in, so session.started is seen.
          _liveSub = peer.events.listen(_onLive);
          await peer.answer(answer.sdp);
          await started.future.timeout(_budget);
          return const Ok(null);
      }
    } on TimeoutException {
      await peer.close();
      return _fail(_couldNot('it did not answer in time.'));
    } on _LiveFailed catch (failed) {
      await peer.close();
      return _fail(_couldNot(failed.message));
    } on Object {
      await peer.close();
      return _fail(_couldNot('the microphone or the connection failed.'));
    }
  }

  static String _couldNot(String reason) => "GPT-Live couldn't start: $reason";

  static Result<void> _fail(String message) =>
      Err(IrisFailure(FailureKind.server, message: message));

  @override
  Future<void> start() async {
    final peer = _peer;
    if (_phase != _Phase.idle || peer == null) return;
    _phase = _Phase.live;
    _style = _host.state.style;
    _levelSub = peer.remoteLevel.listen(_onLevel);
    _chatSub = _backend.events.listen(_onChat);
    await _applyMic();
    _refresh();
  }

  // ---------------------------------------------------------------- modes

  CallMode get _mode {
    if (_phase == _Phase.ended) return CallMode.ended;
    if (_phase == _Phase.idle) return CallMode.connecting;
    if (_phase == _Phase.paused) return CallMode.paused;
    if (_linkDown) return CallMode.reconnecting;
    if (_speaking) return CallMode.speaking;
    if (_turnActive) {
      return _host.state.tool != null ? CallMode.tool : CallMode.thinking;
    }
    if (_muted) return CallMode.muted;
    if (_hearing || _holding) return CallMode.hearing;
    return CallMode.listening;
  }

  void _refresh() {
    final mode = _mode;
    if (_host.state.mode != mode) {
      _host.update((s) => s.copyWith(mode: mode));
    }
  }

  Future<void> _applyMic() async {
    final on =
        _phase == _Phase.live &&
        !_muted &&
        (_style == CallStyle.handsFree || _holding);
    await _peer?.setMicEnabled(on: on);
  }

  // -------------------------------------------------------- data channel

  void _onLive(Json event) {
    if (_phase == _Phase.ended) return;
    final type = event['type'].stringOrNull;
    final started = _started;
    switch (type) {
      case 'session.started':
        if (started != null && !started.isCompleted) started.complete();
      case 'session.input_transcript.delta':
        _append('user', event.any(['delta', 'text']).stringOrNull);
        _hearing = true;
        _hearingTimer?.cancel();
        _hearingTimer = Timer(_hearingFor, () {
          _hearing = false;
          _refresh();
        });
        _refresh();
      case 'session.output_transcript.delta':
        _append('assistant', event.any(['delta', 'text']).stringOrNull);
        _hearing = false;
        _refresh();
      case 'session.delegation.created':
        final delegation = event['delegation'];
        final id =
            delegation['id'].stringOrNull ?? event['id'].stringOrNull ?? '';
        if (!_delegations.add(id)) return;
        unawaited(_delegate(delegation));
      case 'error':
        final message =
            event['error']['message'].stringOrNull ??
            event['message'].stringOrNull ??
            'GPT-Live stopped.';
        if (started != null && !started.isCompleted) {
          started.completeError(_LiveFailed(message));
        } else if (event['fatal'].boolOrNull ?? true) {
          unawaited(_host.finish(failure: message));
        }
      case 'session.closed':
        if (started != null && !started.isCompleted) {
          started.completeError(const _LiveFailed('the session closed.'));
        } else {
          unawaited(_host.finish());
        }
    }
  }

  void _append(String role, String? text) {
    if (text == null || text.isEmpty) return;
    final now = _host.now;
    if (_lines.isEmpty || _lines.last.role != role) {
      _lines.add(_Line(role, now));
      if (_lines.length > 200) _lines.removeAt(0);
    }
    _lines.last
      ..text.write(text)
      ..at = now;
    _host.update(
      (s) => s.copyWith(
        transcript: [
          for (final line in _lines)
            if (line.text.toString().trim().isNotEmpty)
              Caption(
                you: line.role == 'user',
                text: line.text.toString().trim(),
              ),
        ],
      ),
    );
  }

  /// The spoken words of the last five minutes, newest last, at most 6,000
  /// characters.
  String _context() {
    final since = _host.now.subtract(_window);
    final lines = [
      for (final line in _lines)
        if (!line.at.isBefore(since) && line.text.toString().trim().isNotEmpty)
          '${line.role}: ${line.text.toString().trim()}',
    ];
    while (lines.length > 1 && lines.join('\n').length > _contextLimit) {
      lines.removeAt(0);
    }
    final joined = lines.join('\n');
    return joined.length > _contextLimit
        ? joined.substring(joined.length - _contextLimit)
        : joined;
  }

  Future<void> _delegate(Json delegation) async {
    var text =
        delegation
            .any(['text', 'request', 'prompt', 'task', 'instructions'])
            .stringOrNull
            ?.trim() ??
        '';
    if (text.isEmpty) {
      final said = _lines.lastWhere(
        (line) => line.role == 'user',
        orElse: () => _Line('user', _host.now),
      );
      text = said.text.toString().trim();
    }
    if (text.isEmpty) return;
    final context = _context();
    _turnActive = true;
    _reply.clear();
    _hearing = false;
    _host
      ..update((s) => s.copyWith(clearTool: true, toolTrail: const []))
      ..markWorking(_host.now);
    _refresh();
    final sent = await _chat.sendVoice(
      text,
      VoiceSubmit(surface: 'voice-live', voiceContext: context),
    );
    if (!sent && _turnActive) {
      _commentary("I couldn't pass that to the agent.");
      _endTurn();
    }
  }

  void _onLevel(double level) {
    if (_phase != _Phase.live) return;
    _host.level.value = level;
    final speaking = level > _speakingAbove;
    if (speaking == _speaking) return;
    _speaking = speaking;
    if (speaking) _hearing = false;
    _refresh();
  }

  // --------------------------------------------------------- chat events

  bool _ours(ChatEvent event) =>
      event.sessionId.isNotEmpty &&
      (event.sessionId == _chat.runtimeId ||
          event.sessionId == _chat.conversationId);

  void _onChat(ChatEvent event) {
    if (_phase == _Phase.ended || !_turnActive || !_ours(event)) return;
    switch (event) {
      case TextDelta(:final text):
        _reply.write(text);
      case ToolStarted(:final name, :final input):
        final detail = input?.trim() ?? '';
        _host.update(
          (s) => s.copyWith(tool: detail.isEmpty ? name : '$name · $detail'),
        );
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
      case MessageCompleted(:final content):
        final text = _reply.isEmpty ? (content ?? '') : _reply.toString();
        _commentary(text);
        _endTurn();
      case TurnFailed(:final message):
        _commentary("That didn't work: $message");
        _endTurn();
      case TurnInterrupted():
        _endTurn();
      default:
        break;
    }
  }

  /// The agent's words go to the voice model to say.
  void _commentary(String text) {
    for (final chunk in chunkForCommentary(text)) {
      _peer?.send({'type': 'session.commentary.append', 'text': chunk});
    }
  }

  void _endTurn() {
    _turnActive = false;
    _reply.clear();
    _host
      ..update((s) => s.copyWith(clearTool: true))
      ..markWorking(null);
    _refresh();
  }

  // ------------------------------------------------------------ controls

  @override
  Future<void> setMuted({required bool muted}) async {
    if (_muted == muted || _phase == _Phase.ended) return;
    _muted = muted;
    _host.update((s) => s.copyWith(muted: muted));
    _peer?.send({
      'type': muted ? 'session.input_audio.mute' : 'session.input_audio.unmute',
    });
    await _applyMic();
    _refresh();
  }

  @override
  Future<void> hold({required bool down}) async {
    if (_style != CallStyle.pushToTalk || _phase != _Phase.live) return;
    _holding = down;
    await _applyMic();
    _refresh();
  }

  @override
  Future<void> setStyle(CallStyle style) async {
    _style = style;
    _holding = false;
    await _applyMic();
    _refresh();
  }

  @override
  Future<void> pause(PauseReason reason) async {
    if (_phase != _Phase.live) return;
    _phase = _Phase.paused;
    _host.update((s) => s.copyWith(paused: reason));
    _peer?.send({'type': 'session.input_audio.mute'});
    await _peer?.setMicEnabled(on: false);
    _refresh();
  }

  @override
  Future<void> resume() async {
    if (_phase != _Phase.paused) return;
    _phase = _Phase.live;
    _host.update((s) => s.copyWith(clearPaused: true));
    if (!_muted) _peer?.send({'type': 'session.input_audio.unmute'});
    await _applyMic();
    _refresh();
  }

  /// Nothing is held: the voice model hears everything itself.
  @override
  Future<void> retryHeld() async {}

  @override
  Future<void> linkChanged({required bool live}) async {
    _linkDown = !live;
    _refresh();
  }

  @override
  Future<void> end() async {
    if (_phase == _Phase.ended) return;
    _phase = _Phase.ended;
    _hearingTimer?.cancel();
    unawaited(_liveSub?.cancel());
    unawaited(_levelSub?.cancel());
    unawaited(_chatSub?.cancel());
    final peer = _peer;
    _peer = null;
    if (peer != null) {
      peer.send({'type': 'session.close'});
      await peer.close();
    }
  }
}
