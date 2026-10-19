import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/demo/demo_voice.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/voice/voice_call.dart';

import '../support/fake_chat_backend.dart';

void main() {
  test('demo voice offers a chained setup with voices', () async {
    final caps = (await DemoVoiceBackend().capabilities()).valueOrNull!;

    expect(caps.engine, VoiceEngine.chained);
    expect(caps.voiceMode, isTrue);
    expect(caps.dictation, isTrue);
    expect(caps.currentVoice, isNotNull);
  });

  test('demo call walks every state', () {
    fakeAsync((async) {
      final chatBackend = FakeChatBackend();
      final chat = ChatController(chatBackend, conversationId: 'demo-1');
      final parts = demoCallParts(const VoiceSettings());
      final call = VoiceCall(
        chat: chat,
        backend: chatBackend,
        voice: DemoVoiceBackend(),
        capabilities: const VoiceCapabilities(
          dictation: true,
          voiceMode: true,
          engine: VoiceEngine.chained,
        ),
        settings: const VoiceSettings(),
        mic: parts.mic,
        out: parts.out,
        route: parts.route,
        scripted: parts.scripted,
      );

      final modes = <CallMode>[];
      call.addListener(() {
        final mode = call.value.mode;
        if (modes.isEmpty || modes.last != mode) modes.add(mode);
      });
      var peak = 0.0;
      call.value.level.addListener(() {
        peak = max(peak, call.value.level.value);
      });

      unawaited(call.begin());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 20));

      expect(
        modes,
        containsAllInOrder([
          CallMode.connecting,
          CallMode.listening,
          CallMode.hearing,
          CallMode.thinking,
          CallMode.tool,
          CallMode.needs,
          CallMode.speaking,
          CallMode.listening,
        ]),
      );
      expect(peak, greaterThan(0));
      expect(call.value.transcript.any((line) => line.you), isTrue);
      expect(call.value.transcript.any((line) => !line.you), isTrue);

      unawaited(call.end());
      async.flushMicrotasks();
      call.dispose();
      async.flushMicrotasks();
    });
  });
}
