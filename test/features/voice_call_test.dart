import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/rpc/rpc_frame.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/voice/spoken.dart';
import 'package:iris/features/voice/thinking_sound.dart';
import 'package:iris/features/voice/voice_call.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';

const _run = 'run-1';

/// A call on a conversation that is already live as [_run].
final class _Rig {
  _Rig({
    VoiceTuning tuning = const VoiceTuning(thinkingSound: false),
    VoiceSettings settings = const VoiceSettings(),
    bool liveTranscription = false,
  }) {
    chat = ChatController(chatBackend, conversationId: 'stored-1');
    call = VoiceCall(
      chat: chat,
      backend: chatBackend,
      voice: voice,
      capabilities: VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: VoiceEngine.chained,
        liveTranscription: liveTranscription,
        tuning: tuning,
      ),
      settings: settings,
      mic: mic,
      out: out,
      route: route,
      clock: () => now,
    );
    call.addListener(() {
      final mode = call.value.mode;
      if (modes.isEmpty || modes.last != mode) modes.add(mode);
    });
  }

  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  final mic = FakeMic();
  final out = FakeAudioOut();
  final route = FakeAudioRoute();
  late final ChatController chat;
  late final VoiceCall call;
  final modes = <CallMode>[];
  DateTime now = DateTime(2026, 10, 19, 9);

  CallMode get mode => call.value.mode;

  /// Opens the chat and starts the call; the preflight passes, and what it
  /// asked of the voice backend is forgotten so tests see only the call.
  Future<void> begin() async {
    await chat.open();
    voice.sockets.add(FakeAudioSocket.speaking());
    await call.begin();
    await pumpEventQueue();
    forgetPreflight();
  }

  void forgetPreflight() {
    voice.calls.clear();
    voice.opened.clear();
    voice.wavs.clear();
    voice.transcribed.clear();
  }

  /// [ms] of microphone audio at [rms], in 100 ms chunks.
  void talk(int ms, {int rms = 1000}) {
    for (var t = 0; t < ms; t += 100) {
      mic.pushLevel(rms);
    }
  }

  void quiet(int ms) => talk(ms, rms: 50);

  /// One whole take: a second of speech, then the silence that ends it.
  Future<void> say(String transcript) async {
    voice.transcribeResult = Ok(transcript);
    talk(1000);
    quiet(3000);
    await pumpEventQueue();
  }

  void emit(ChatEvent event) => chatBackend.emit(event);

  FakeAudioSocket get speakSocket => voice.opened.last;

  Future<void> serverSpeaks({int rate = 24000, Uint8List? pcm}) async {
    speakSocket
      ..serverSends({'type': 'start', 'sample_rate': rate, 'channels': 1})
      ..serverSendsBytes(pcm ?? Uint8List.fromList(List.filled(480, 1)));
    await pumpEventQueue();
  }

  Future<void> serverEnds() async {
    speakSocket.serverSends({'type': 'end'});
    await pumpEventQueue();
    out.drain();
    await pumpEventQueue();
  }

  /// Iris speaks [text] in full and the call is listening again.
  Future<void> reply(String text) async {
    emit(const MessageStarted(_run));
    emit(TextDelta(_run, text));
    emit(MessageCompleted(_run, content: text));
    await pumpEventQueue();
    await serverSpeaks();
    await serverEnds();
  }
}

int _u32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);

int _u16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);

void main() {
  group('spoken', () {
    test('a stop phrase is matched without case or punctuation', () {
      expect(isStopPhrase('Stop.', const ['stop']), isTrue);
      expect(isStopPhrase('  STOP!  ', const ['stop']), isTrue);
      expect(
        isStopPhrase('Okay, goodbye', const ['stop', 'okay goodbye']),
        isTrue,
      );
      expect(isStopPhrase('stop the deploy', const ['stop']), isFalse);
      expect(isStopPhrase('stop', const []), isFalse);
    });

    test('an echo is a run of what Iris just said', () {
      expect(isEcho('pushed the branch', 'Pushed the branch.'), isTrue);
      expect(
        isEcho('the branch to main', 'Pushed the branch to main.'),
        isTrue,
      );
      expect(isEcho('Done.', 'Done.'), isTrue);
      // Too short to tell from a real answer, unless it is all Iris said.
      expect(isEcho('yes', 'Yes, I can do that.'), isFalse);
      expect(isEcho('push it to main', 'Pushed the branch.'), isFalse);
      expect(isEcho('anything', ''), isFalse);
      expect(isEcho('', 'Done.'), isFalse);
    });

    test('code is not speakable', () {
      expect(speakable('```dart\nvoid main() {}\n```'), isEmpty);
      expect(speakable('Here:\n```\nx\n```\nDone.'), 'Here:\n\nDone.');
      expect(speakable('Fine.'), 'Fine.');
    });
  });

  group('thinking sound', () {
    test('a bubble then silence, soft, at the playback rate', () {
      final pcm = thinkingBubble(24000);
      // 120 ms on, 900 ms off.
      expect(pcm.length, (24000 * 1.02).round() * 2);
      final data = ByteData.sublistView(pcm);
      var peak = 0;
      for (var i = 0; i < pcm.length ~/ 2; i++) {
        final v = data.getInt16(i * 2, Endian.little).abs();
        if (v > peak) peak = v;
      }
      // -30 dBFS is about 1036.
      expect(peak, inInclusiveRange(800, 1100));
      // Silent after 120 ms.
      for (var i = (24000 * 0.121).round(); i < pcm.length ~/ 2; i++) {
        expect(data.getInt16(i * 2, Endian.little), 0);
      }
    });
  });

  group('voice call', () {
    test('listening to hearing to thinking', () async {
      final rig = _Rig();
      await rig.begin();
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
      expect(rig.route.activations, 1);

      rig.voice.transcribeResult = const Ok('check the deploy');
      rig.talk(1000);
      expect(rig.mode, CallMode.hearing);
      rig.quiet(2900);
      await pumpEventQueue();
      expect(rig.voice.calls.where((c) => c == 'transcribe'), isEmpty);
      rig.quiet(100);
      await pumpEventQueue();

      final wav = rig.voice.wavs.single;
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(_u16(wav, 20), 1); // PCM
      expect(_u16(wav, 22), 1); // mono
      expect(_u32(wav, 24), 16000);
      expect(_u16(wav, 34), 16);
      expect(_u32(wav, 40), wav.length - 44);
      expect(wav.length - 44, greaterThanOrEqualTo(32000));

      expect(rig.chatBackend.submits.single.$2, 'check the deploy');
      expect(rig.chatBackend.voiceSubmits.single?.voiceTurn, isTrue);
      expect(rig.chatBackend.voiceSubmits.single?.interrupted, isFalse);
      expect(rig.mode, CallMode.thinking);
      expect(rig.mic.open, isFalse);
      expect(rig.modes, [
        CallMode.connecting,
        CallMode.listening,
        CallMode.hearing,
        CallMode.thinking,
      ]);
      expect(rig.call.value.transcript.last.you, isTrue);
      expect(rig.call.value.transcript.last.text, 'check the deploy');
    });

    test('a live transcription supplies the words', () async {
      final rig = _Rig(liveTranscription: true);
      await rig.begin();
      rig.talk(1000);
      await pumpEventQueue();
      final socket = rig.voice.opened.single;
      expect(rig.voice.calls, contains('socket /api/audio/transcribe-stream'));
      expect(socket.sentJson.first, {'sample_rate': 16000});
      expect(socket.sentBytes, isNotEmpty);

      rig.quiet(3000);
      await pumpEventQueue();
      expect(socket.sentJson.last, {'eos': true});
      socket.serverSends({'type': 'final', 'text': 'ship it'});
      await pumpEventQueue();
      expect(rig.voice.calls, isNot(contains('transcribe')));
      expect(rig.chatBackend.submits.single.$2, 'ship it');
    });

    test('a failed live transcription falls back to the upload', () async {
      final rig = _Rig(liveTranscription: true);
      await rig.begin();
      rig.voice.transcribeResult = const Ok('ship it');
      rig.talk(1000);
      rig.quiet(3000);
      await pumpEventQueue();
      rig.voice.opened.single.serverSends({
        'type': 'error',
        'message': 'no live STT',
      });
      await pumpEventQueue();
      expect(rig.voice.calls, contains('transcribe'));
      expect(rig.chatBackend.submits.single.$2, 'ship it');
    });

    test('tool shows the name and trail', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('search for it');
      rig.emit(
        const ToolStarted(
          _run,
          name: 'web.search',
          input: 'flutter riverpod 3',
        ),
      );
      await pumpEventQueue();
      expect(rig.mode, CallMode.tool);
      expect(rig.call.value.tool, 'web.search · flutter riverpod 3');
      rig.emit(const ToolCompleted(_run, name: 'web.search'));
      await pumpEventQueue();
      expect(rig.mode, CallMode.thinking);
      expect(rig.call.value.tool, isNull);
      expect(rig.call.value.toolTrail, ['web.search · flutter riverpod 3']);
    });

    test('reply streams into speak-stream', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      rig.emit(const MessageStarted(_run));
      rig.emit(const TextDelta(_run, 'Done. '));
      rig.emit(const TextDelta(_run, 'Pushed.'));
      await pumpEventQueue();
      expect(rig.voice.calls, contains('socket /api/audio/speak-stream'));
      expect(rig.speakSocket.sentJson, [
        {'text': 'Done. '},
        {'text': 'Pushed.'},
      ]);
      rig.emit(const MessageCompleted(_run, content: 'Done. Pushed.'));
      await pumpEventQueue();
      expect(rig.speakSocket.sentJson.last, {'done': true});

      final pcm = Uint8List.fromList(List.filled(960, 3));
      await rig.serverSpeaks(pcm: pcm);
      expect(rig.mode, CallMode.speaking);
      expect(rig.out.starts.last, 24000);
      expect(rig.out.pcm, [pcm]);

      rig.speakSocket.serverSends({'type': 'end'});
      await pumpEventQueue();
      expect(rig.mode, CallMode.speaking, reason: 'still draining');
      rig.out.drain();
      await pumpEventQueue();
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
      expect(rig.call.value.transcript.last.you, isFalse);
      expect(rig.call.value.transcript.last.text, 'Done. Pushed.');
    });

    test('reasoning is never spoken', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('think');
      rig.emit(const ReasoningDelta(_run, 'Let me think about this.'));
      await pumpEventQueue();
      expect(rig.voice.opened, isEmpty);
    });

    test('fallback speaks once', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      rig.emit(const TextDelta(_run, 'Done. '));
      rig.emit(const TextDelta(_run, 'Pushed.'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      rig.speakSocket.serverSends({'type': 'fallback'});
      await pumpEventQueue();
      expect(rig.voice.calls, contains('speak Done. Pushed.'));
      expect(rig.out.files, hasLength(1));
      expect(rig.mode, CallMode.speaking);
      rig.out.finishFile();
      await pumpEventQueue();
      expect(rig.mode, CallMode.listening);
    });

    test('a failed one-shot speech still returns to listening', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      rig.voice.speakResult = const Err(IrisFailure.offline());
      rig.emit(const TextDelta(_run, 'Done.'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      rig.speakSocket.serverSends({'type': 'fallback'});
      await pumpEventQueue();
      expect(rig.out.files, isEmpty);
      expect(rig.mode, CallMode.listening);
    });

    test('empty reply returns to listening', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('run the tool');
      rig.emit(const MessageStarted(_run));
      rig.emit(const ToolStarted(_run, name: 'terminal'));
      rig.emit(const ToolCompleted(_run, name: 'terminal'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      expect(rig.voice.opened, isEmpty);
      expect(rig.out.starts, isEmpty);
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
    });

    test('a reply that is only code says nothing', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('show me');
      rig.emit(const TextDelta(_run, '```\nls -la\n```'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      rig.speakSocket.serverSends({'type': 'fallback'});
      await pumpEventQueue();
      expect(rig.voice.calls.where((c) => c.startsWith('speak ')), isEmpty);
      expect(rig.mode, CallMode.listening);
    });

    test('a failed turn returns to listening', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      rig.emit(const TurnFailed(_run, 'model overloaded'));
      await pumpEventQueue();
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
    });

    test('silence is not a turn', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('');
      expect(rig.voice.calls, contains('transcribe'));
      expect(rig.chatBackend.submits, isEmpty);
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
    });

    test('stop phrase ends the call', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('Stop.');
      expect(rig.mode, CallMode.ended);
      expect(rig.chatBackend.submits, isEmpty);
      expect(rig.mic.open, isFalse);
      expect(rig.route.deactivations, 1);
    });

    test('echo is dropped', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      await rig.reply('Pushed the branch');
      expect(rig.mode, CallMode.listening);
      await rig.say('pushed the branch');
      expect(rig.chatBackend.submits, hasLength(1));
      expect(rig.mode, CallMode.listening);
    });

    test('barge-in', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('tell me a story');
      rig.emit(const TextDelta(_run, 'Once upon a time there was a branch.'));
      await pumpEventQueue();
      // The mic opens with the reply; its floor is the room before speech.
      expect(rig.mic.open, isTrue);
      rig.quiet(300);
      await rig.serverSpeaks();
      expect(rig.mode, CallMode.speaking);

      rig.quiet(500); // the grace
      rig.talk(200);
      expect(rig.mode, CallMode.speaking);
      rig.talk(100);
      await pumpEventQueue();
      expect(rig.out.stops, greaterThanOrEqualTo(1));
      expect(rig.speakSocket.sentJson.last, {'stop': true});
      expect(rig.chatBackend.calls, contains('interrupt $_run'));
      expect(
        rig.modes,
        containsAllInOrder([
          CallMode.speaking,
          CallMode.interrupted,
          CallMode.hearing,
        ]),
      );
      expect(rig.mode, CallMode.hearing);

      rig.voice.transcribeResult = const Ok('no, the short one');
      rig.talk(500);
      rig.quiet(3000);
      await pumpEventQueue();
      expect(rig.chatBackend.submits.last.$2, 'no, the short one');
      expect(rig.chatBackend.voiceSubmits.last?.interrupted, isTrue);
    });

    test('the interrupted turn ending late does not end the next', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('tell me a story');
      rig.emit(const TextDelta(_run, 'Once upon a time there was a branch.'));
      await pumpEventQueue();
      rig.quiet(300);
      await rig.serverSpeaks();
      rig.quiet(500);
      rig.talk(300);
      await pumpEventQueue();
      expect(rig.mode, CallMode.hearing);

      rig.voice.transcribeResult = const Ok('the short one');
      rig.talk(500);
      rig.quiet(3000);
      await pumpEventQueue();
      expect(rig.mode, CallMode.thinking);
      // The old turn's stop is reported only now.
      rig.emit(const TurnInterrupted(_run));
      await pumpEventQueue();
      expect(rig.mode, CallMode.thinking);

      rig.emit(const TextDelta(_run, 'Short it is.'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      expect(rig.speakSocket.sentJson, [
        {'text': 'Short it is.'},
        {'done': true},
      ]);
    });

    test('a quiet room never trips barge-in', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('tell me a story');
      rig.emit(const TextDelta(_run, 'Once upon a time.'));
      await pumpEventQueue();
      rig.quiet(300);
      await rig.serverSpeaks();
      rig.quiet(3000);
      await pumpEventQueue();
      expect(rig.mode, CallMode.speaking);
      expect(rig.chatBackend.calls, isNot(contains('interrupt $_run')));
    });

    test('barge-in off keeps the mic closed while Iris speaks', () async {
      final rig = _Rig(
        tuning: const VoiceTuning(bargeIn: false, thinkingSound: false),
      );
      await rig.begin();
      await rig.say('tell me a story');
      rig.emit(const TextDelta(_run, 'Once upon a time.'));
      await pumpEventQueue();
      await rig.serverSpeaks();
      expect(rig.mic.open, isFalse);
      rig.talk(2000);
      expect(rig.mode, CallMode.speaking);
    });

    test('no barge-in while thinking', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('deploy it');
      expect(rig.mode, CallMode.thinking);
      expect(rig.mic.open, isFalse);
      rig.talk(2000);
      await pumpEventQueue();
      expect(rig.mode, CallMode.thinking);
      expect(rig.chatBackend.calls, isNot(contains('interrupt $_run')));
      expect(rig.voice.calls.where((c) => c == 'transcribe'), hasLength(1));
    });

    test('failed transcription is held and retried', () async {
      final rig = _Rig();
      await rig.begin();
      rig.voice.transcribeResult = const Err(IrisFailure.offline());
      rig.talk(1000);
      rig.quiet(3000);
      await pumpEventQueue();
      expect(rig.voice.calls.where((c) => c == 'transcribe'), hasLength(2));
      expect(rig.call.value.heldTake, isTrue);
      expect(rig.mode, CallMode.listening);
      expect(rig.chatBackend.submits, isEmpty);

      rig.voice.transcribeResult = const Ok('check the deploy');
      await rig.call.retryHeld();
      await pumpEventQueue();
      expect(rig.voice.wavs.last, rig.voice.wavs.first);
      expect(rig.chatBackend.submits.single.$2, 'check the deploy');
      expect(rig.call.value.heldTake, isFalse);
      expect(rig.mode, CallMode.thinking);
    });

    test('a new take replaces a held one', () async {
      final rig = _Rig();
      await rig.begin();
      rig.voice.transcribeQueue.addAll(const [
        Err(IrisFailure.offline()),
        Err(IrisFailure.offline()),
      ]);
      await rig.say('second try');
      expect(rig.call.value.heldTake, isTrue);
      await rig.say('second try');
      expect(rig.call.value.heldTake, isFalse);
      expect(rig.chatBackend.submits.single.$2, 'second try');
    });

    test('muted ignores the mic', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('tell me');
      await rig.call.setMuted(muted: true);
      expect(rig.call.value.muted, isTrue);
      rig.emit(const TextDelta(_run, 'Here it is.'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      await rig.serverSpeaks();
      expect(rig.out.pcm, isNotEmpty, reason: 'replies still play');
      expect(rig.mic.open, isFalse);
      await rig.serverEnds();
      expect(rig.mode, CallMode.muted);
      expect(rig.mic.open, isFalse);
      rig.talk(1000);
      rig.quiet(3000);
      await pumpEventQueue();
      expect(rig.chatBackend.submits, hasLength(1));

      await rig.call.setMuted(muted: false);
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
    });

    test('muting while listening shows muted at once', () async {
      final rig = _Rig();
      await rig.begin();
      rig.talk(500);
      await rig.call.setMuted(muted: true);
      expect(rig.mode, CallMode.muted);
      expect(rig.mic.open, isFalse);
    });

    test('push to talk', () async {
      final rig = _Rig(
        settings: const VoiceSettings(style: CallStyle.pushToTalk),
      );
      await rig.begin();
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isFalse);

      rig.voice.transcribeResult = const Ok('add a task');
      await rig.call.hold(down: true);
      expect(rig.mic.open, isTrue);
      expect(rig.mode, CallMode.hearing);
      // Quiet speech: no detector decides when the take ends.
      rig.quiet(3500);
      await pumpEventQueue();
      expect(rig.voice.calls, isNot(contains('transcribe')));
      await rig.call.hold(down: false);
      await pumpEventQueue();
      expect(rig.voice.calls, contains('transcribe'));
      expect(rig.chatBackend.submits.single.$2, 'add a task');
      expect(rig.mic.open, isFalse);
    });

    test('a tap too short to be a take is ignored', () async {
      final rig = _Rig(
        settings: const VoiceSettings(style: CallStyle.pushToTalk),
      );
      await rig.begin();
      await rig.call.hold(down: true);
      rig.talk(200);
      await rig.call.hold(down: false);
      await pumpEventQueue();
      expect(rig.voice.calls, isNot(contains('transcribe')));
      expect(rig.mode, CallMode.listening);
    });

    test('reconnect pauses listening', () async {
      final rig = _Rig();
      await rig.begin();
      rig.chatBackend.linkDown();
      await pumpEventQueue();
      expect(rig.mode, CallMode.reconnecting);
      expect(rig.mic.open, isFalse);
      rig.chatBackend.linkUp();
      await pumpEventQueue();
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
    });

    test('a link down for 30 s ends the call', () {
      fakeAsync((async) {
        final rig = _Rig();
        unawaited(rig.begin());
        async.flushMicrotasks();
        rig.forgetPreflight();
        expect(rig.mode, CallMode.listening);
        rig.chatBackend.linkDown();
        async.elapse(const Duration(seconds: 29));
        expect(rig.mode, CallMode.reconnecting);
        async.elapse(const Duration(seconds: 1));
        expect(rig.mode, CallMode.error);
        expect(rig.call.value.failure, 'The call ended unexpectedly.');
        expect(rig.mic.open, isFalse);
        expect(rig.route.active, isFalse);
        unawaited(rig.call.end());
        async.flushMicrotasks();
      });
    });

    test('pause for a phone call', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      rig.emit(const TextDelta(_run, 'Done. '));
      await pumpEventQueue();
      await rig.serverSpeaks();
      final first = rig.speakSocket;
      final stopsBefore = rig.out.stops;

      await rig.call.pause(PauseReason.phoneCall);
      expect(rig.mode, CallMode.paused);
      expect(rig.call.value.paused, PauseReason.phoneCall);
      expect(rig.out.stops, stopsBefore + 1);
      expect(rig.mic.open, isFalse);
      expect(first.closed, isTrue);

      // The reply finishes while the phone call goes on, and is kept.
      rig.emit(const TextDelta(_run, 'Pushed.'));
      rig.emit(const MessageCompleted(_run));
      await pumpEventQueue();
      expect(rig.voice.opened, hasLength(1));
      expect(rig.mode, CallMode.paused);

      await rig.call.resume();
      await pumpEventQueue();
      expect(rig.voice.opened, hasLength(2));
      expect(rig.speakSocket.sentJson, [
        {'text': 'Done. Pushed.'},
        {'done': true},
      ]);
      await rig.serverSpeaks();
      expect(rig.mode, CallMode.speaking);
      await rig.serverEnds();
      expect(rig.mode, CallMode.listening);
      expect(rig.call.value.paused, isNull);
    });

    test('resuming with nothing owed listens', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.call.pause(PauseReason.unplugged);
      expect(rig.mode, CallMode.paused);
      await rig.call.resume();
      expect(rig.mode, CallMode.listening);
      expect(rig.mic.open, isTrue);
    });

    test('two starts leave one capture', () async {
      final rig = _Rig();
      await rig.chat.open();
      rig.voice.sockets.add(FakeAudioSocket.speaking());
      await Future.wait([rig.call.begin(), rig.call.begin()]);
      await pumpEventQueue();
      expect(rig.mic.starts, 1);
      expect(rig.route.activations, 1);
      await Future.wait([rig.call.end(), rig.call.end()]);
      expect(rig.mic.stops, 1);
      expect(rig.route.deactivations, 1);
      expect(rig.mode, CallMode.ended);
      // Ended is final.
      await rig.call.begin();
      expect(rig.mic.starts, 1);
      expect(rig.mode, CallMode.ended);
    });

    test('ending mid-reply closes the socket and silences playback', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('push it');
      rig.emit(const TextDelta(_run, 'Done.'));
      await pumpEventQueue();
      await rig.serverSpeaks();
      await rig.call.end();
      expect(rig.speakSocket.closed, isTrue);
      expect(rig.out.playing, isFalse);
      expect(rig.mic.open, isFalse);
      rig.emit(const TextDelta(_run, 'More.'));
      await pumpEventQueue();
      expect(rig.voice.opened, hasLength(1));
    });

    test('thinking sound plays only while working', () {
      fakeAsync((async) {
        final rig = _Rig(tuning: const VoiceTuning());
        unawaited(rig.begin());
        async.flushMicrotasks();
        rig.forgetPreflight();
        rig.voice.transcribeResult = const Ok('deploy');
        rig.talk(1000);
        rig.quiet(3000);
        async.flushMicrotasks();
        expect(rig.mode, CallMode.thinking);
        expect(rig.out.starts, [24000]);
        expect(rig.out.pcm, hasLength(1));
        async.elapse(const Duration(milliseconds: 1100));
        expect(rig.out.pcm, hasLength(2));

        rig.emit(const TextDelta(_run, 'Deployed.'));
        async.flushMicrotasks();
        final speech = Uint8List.fromList(List.filled(480, 9));
        rig.speakSocket
          ..serverSends({'type': 'start', 'sample_rate': 22050})
          ..serverSendsBytes(speech);
        async.flushMicrotasks();
        expect(rig.out.starts.last, 22050);
        expect(rig.out.pcm, [speech]);
        async.elapse(const Duration(seconds: 3));
        expect(rig.out.pcm, [speech]);
        unawaited(rig.call.end());
        async.flushMicrotasks();
      });
    });

    test('no thinking sound when the server turns it off', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('deploy');
      expect(rig.mode, CallMode.thinking);
      expect(rig.out.starts, isEmpty);
    });

    test('elapsed and working time follow the clock', () async {
      final rig = _Rig();
      await rig.begin();
      rig.now = rig.now.add(const Duration(seconds: 5));
      await rig.say('deploy');
      rig.now = rig.now.add(const Duration(seconds: 7));
      rig.call.tick();
      expect(rig.call.value.elapsed, const Duration(seconds: 12));
      expect(rig.call.value.workingFor, const Duration(seconds: 7));
    });

    test('speaker, style and captions', () async {
      final rig = _Rig();
      await rig.begin();
      expect(rig.call.value.route.speaker, isTrue);
      await rig.call.setSpeaker(on: false);
      await pumpEventQueue();
      expect(rig.route.speaker, isFalse);
      expect(rig.call.value.route.speaker, isFalse);
      rig.call.toggleCaptions();
      expect(rig.call.value.captions, isTrue);
      await rig.call.setStyle(CallStyle.pushToTalk);
      expect(rig.call.value.style, CallStyle.pushToTalk);
      expect(rig.mic.open, isFalse);
      await rig.call.setStyle(CallStyle.handsFree);
      expect(rig.mic.open, isTrue);
    });
  });

  group('sendVoice', () {
    test(
      'a new chat is created, then the turn goes with its voice fields',
      () async {
        final backend = FakeChatBackend();
        final chat = ChatController(backend);
        await chat.open();
        final sent = await chat.sendVoice(
          'hello',
          const VoiceSubmit(voiceTurn: true),
        );
        expect(sent, isTrue);
        expect(backend.calls, contains('create'));
        expect(chat.runtimeId, 'run-new');
        expect(backend.submits.single.$2, 'hello');
        expect(backend.voiceSubmits.single?.voiceTurn, isTrue);
        expect(chat.value.items.whereType<UserTurn>().single.text, 'hello');
      },
    );

    test(
      'an older Hermes that refuses the fields gets the turn without them',
      () async {
        final backend = FakeChatBackend()
          ..submitQueue.add(
            const Err(
              IrisFailure(
                FailureKind.rejected,
                cause: RpcError(
                  code: -32602,
                  message:
                      "prompt.submit() got an unexpected keyword argument 'voice_turn'",
                ),
              ),
            ),
          );
        final chat = ChatController(backend, conversationId: 'stored-1');
        await chat.open();
        expect(
          await chat.sendVoice('hello', const VoiceSubmit(voiceTurn: true)),
          isTrue,
        );
        expect(backend.voiceSubmits, [isNotNull, isNull]);
        expect(chat.voiceFieldsRefused, isTrue);
        await chat.sendVoice('again', const VoiceSubmit(voiceTurn: true));
        expect(backend.voiceSubmits.last, isNull);
        expect(backend.submits, hasLength(3));
      },
    );

    test('another failure is reported and not retried', () async {
      final backend = FakeChatBackend()
        ..submitResult = const Err(IrisFailure.offline());
      final chat = ChatController(backend, conversationId: 'stored-1');
      await chat.open();
      expect(
        await chat.sendVoice('hello', const VoiceSubmit(voiceTurn: true)),
        isFalse,
      );
      expect(backend.submits, hasLength(1));
      expect(chat.voiceFieldsRefused, isFalse);
    });
  });
}
