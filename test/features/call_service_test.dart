import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/voice/audio/audio_route.dart';
import 'package:iris/features/voice/call_service.dart';
import 'package:iris/features/voice/voice_call.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';

final class _Rig {
  _Rig() {
    chat = ChatController(chatBackend, conversationId: 'stored-1');
    call = VoiceCall(
      chat: chat,
      backend: chatBackend,
      voice: voice,
      capabilities: const VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: VoiceEngine.chained,
        tuning: VoiceTuning(thinkingSound: false),
      ),
      settings: const VoiceSettings(),
      mic: mic,
      out: out,
      route: route,
      service: service,
    );
  }

  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  final mic = FakeMic();
  final out = FakeAudioOut();
  final route = FakeAudioRoute();
  final service = FakeCallService();
  late final ChatController chat;
  late final VoiceCall call;

  CallMode get mode => call.value.mode;

  Future<void> begin() async {
    await chat.open();
    voice.sockets.add(FakeAudioSocket.speaking());
    await call.begin();
    await pumpEventQueue();
  }

  Future<void> say(String transcript) async {
    voice.transcribeResult = Ok(transcript);
    for (var i = 0; i < 10; i++) {
      mic.pushLevel(1000);
    }
    for (var i = 0; i < 30; i++) {
      mic.pushLevel(50);
    }
    await pumpEventQueue();
  }
}

void main() {
  group('notice text', () {
    test('each mode has its line', () {
      expect(noticeText(CallMode.listening), 'Listening');
      expect(noticeText(CallMode.hearing), 'Hearing you');
      expect(
        noticeText(
          CallMode.thinking,
          workingFor: const Duration(minutes: 2, seconds: 7),
        ),
        'Working on it · 2:07',
      );
      expect(noticeText(CallMode.tool), 'Working on it');
      expect(noticeText(CallMode.speaking), 'Speaking');
      expect(noticeText(CallMode.muted), 'Muted');
      expect(noticeText(CallMode.reconnecting), 'Reconnecting');
      expect(noticeText(CallMode.paused), 'Paused');
    });

    test('an hour of work still reads', () {
      expect(
        noticeText(
          CallMode.thinking,
          workingFor: const Duration(hours: 1, minutes: 3, seconds: 4),
        ),
        'Working on it · 1:03:04',
      );
    });
  });

  test('the service starts only once the checks pass', () async {
    final rig = _Rig();
    await rig.chat.open();
    rig.voice.sockets.add(FakeAudioSocket.speaking());
    final begun = rig.call.begin();
    expect(rig.service.starts, isEmpty);
    await begun;
    await pumpEventQueue();
    expect(rig.service.starts.single.title, 'Talking with Iris');
    expect(rig.service.running, isTrue);
  });

  test('notice follows the call', () async {
    final rig = _Rig();
    await rig.begin();
    expect(rig.service.current?.text, 'Listening');
    await rig.say('deploy it');
    expect(rig.mode, CallMode.thinking);
    expect(rig.service.current?.text, startsWith('Working on it'));
    expect(rig.service.current?.title, 'Talking with Iris');
    await rig.call.setMuted(muted: true);
    expect(rig.service.current?.muted, isTrue);
  });

  test('the notice is not re-sent when nothing on it changed', () async {
    final rig = _Rig();
    await rig.begin();
    final before = rig.service.updates.length;
    rig.call.tick();
    rig.call.tick();
    expect(rig.service.updates.length, before);
  });

  test('actions drive the call', () async {
    final rig = _Rig();
    await rig.begin();
    rig.service.press(CallAction.mute);
    await pumpEventQueue();
    expect(rig.call.value.muted, isTrue);
    expect(rig.mode, CallMode.muted);
    rig.service.press(CallAction.unmute);
    await pumpEventQueue();
    expect(rig.call.value.muted, isFalse);
    rig.service.press(CallAction.end);
    await pumpEventQueue();
    expect(rig.mode, CallMode.ended);
    expect(rig.service.stops, 1);
  });

  test('interruption began pauses, ended does not resume', () async {
    final rig = _Rig();
    await rig.begin();
    rig.route.interrupt(InterruptionKind.began);
    await pumpEventQueue();
    expect(rig.mode, CallMode.paused);
    expect(rig.call.value.paused, PauseReason.phoneCall);
    rig.route.interrupt(InterruptionKind.ended);
    await pumpEventQueue();
    expect(rig.mode, CallMode.paused);
    await rig.call.resume();
    expect(rig.mode, CallMode.listening);
  });

  test('becoming noisy pauses playback', () async {
    final rig = _Rig();
    await rig.begin();
    rig.route.unplug();
    await pumpEventQueue();
    expect(rig.mode, CallMode.paused);
    expect(rig.call.value.paused, PauseReason.unplugged);
    expect(rig.out.stops, greaterThanOrEqualTo(1));
  });

  group('service stops on every end path', () {
    test('the End button', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.call.end();
      expect(rig.service.stops, 1);
    });

    test('a stop phrase', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('stop');
      expect(rig.mode, CallMode.ended);
      expect(rig.service.stops, 1);
    });

    test('an error', () {
      fakeAsync((async) {
        final rig = _Rig();
        unawaited(rig.begin());
        async.flushMicrotasks();
        expect(rig.service.running, isTrue);
        rig.chatBackend.linkDown();
        async.elapse(const Duration(seconds: 31));
        expect(rig.mode, CallMode.error);
        expect(rig.service.stops, 1);
      });
    });

    test('the chat going away', () async {
      final rig = _Rig();
      await rig.begin();
      rig.call.dispose();
      await pumpEventQueue();
      expect(rig.service.stops, 1);
      expect(rig.mic.open, isFalse);
    });

    test('a failed check never starts it', () async {
      final rig = _Rig()
        ..voice.transcribeResult = const Err(IrisFailure.offline());
      await rig.chat.open();
      await rig.call.begin();
      expect(rig.mode, CallMode.error);
      expect(rig.service.starts, isEmpty);
      expect(rig.service.stops, 0);
    });
  });
}
