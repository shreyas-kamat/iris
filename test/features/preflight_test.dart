import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/voice/preflight.dart';
import 'package:iris/features/voice/voice_call.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';

const _server = 'hermes.local';

final class _Rig {
  _Rig({String? conversationId = 'stored-1'}) {
    chat = ChatController(chatBackend, conversationId: conversationId);
  }

  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  late final ChatController chat;
  final steps = <PreflightStep>[];

  Future<Result<void>> run({Duration budget = const Duration(seconds: 20)}) =>
      chainedPreflight(
        chat: chat,
        voice: voice,
        server: _server,
        onStep: steps.add,
        budget: budget,
      );

  /// The speak stream answers as a working server does.
  void speakWorks() => voice.sockets.add(FakeAudioSocket.speaking());

  /// The speak stream gives up, as Edge TTS without a client wire does.
  void speakFallsBack() {
    final socket = FakeAudioSocket();
    socket.onJson = (json) {
      if (json['done'] == true) socket.serverSends({'type': 'fallback'});
    };
    voice.sockets.add(socket);
  }
}

String _message(Result<void> result) => switch (result) {
  Err(:final failure) => failure.message ?? '',
  Ok() => 'ok',
};

void main() {
  test('checks in order', () async {
    final rig = _Rig()..speakWorks();
    await rig.chat.open();
    final result = await rig.run();
    expect(result.isOk, isTrue, reason: _message(result));
    expect(rig.steps, [
      PreflightStep.agent,
      PreflightStep.speechToText,
      PreflightStep.textToSpeech,
    ]);
    expect(rig.voice.calls, [
      'lease stt on',
      'transcribe',
      'lease tts on',
      'socket /api/audio/speak-stream',
    ]);

    final wav = rig.voice.wavs.single;
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 16000);
    // 300 ms of 16 kHz 16-bit silence.
    expect(wav.length - 44, 9600);
    expect(wav.sublist(44).every((b) => b == 0), isTrue);

    final socket = rig.voice.opened.single;
    expect(socket.sentJson.take(2), [
      {'text': 'Ready.'},
      {'done': true},
    ]);
    // The audio is discarded and the socket closed.
    expect(socket.closed, isTrue);
  });

  test('a new chat is created by the agent check', () async {
    final rig = _Rig(conversationId: null)..speakWorks();
    await rig.chat.open();
    final result = await rig.run();
    expect(result.isOk, isTrue);
    expect(rig.chatBackend.calls, contains('create'));
    expect(rig.chat.runtimeId, 'run-new');
  });

  test('agent down fails first', () async {
    final rig = _Rig()
      ..chatBackend.resumeResult = const Err(IrisFailure.offline());
    await rig.chat.open();
    final result = await rig.run();
    expect(_message(result), "Iris can't reach the agent on hermes.local");
    expect(rig.voice.calls, isEmpty);
    expect(rig.steps, [PreflightStep.agent]);
  });

  test('stt error names it', () async {
    final rig = _Rig()
      ..voice.transcribeResult = const Err(IrisFailure.offline());
    await rig.chat.open();
    final result = await rig.run();
    expect(_message(result), "Iris can't reach speech-to-text on hermes.local");
    expect(rig.voice.calls, isNot(contains('lease tts on')));
  });

  test('tts start then pcm passes', () async {
    final rig = _Rig()..speakWorks();
    await rig.chat.open();
    expect((await rig.run()).isOk, isTrue);
    expect(rig.voice.calls.where((c) => c.startsWith('speak ')), isEmpty);
  });

  test('tts fallback then speakOnce ok passes', () async {
    final rig = _Rig()..speakFallsBack();
    await rig.chat.open();
    expect((await rig.run()).isOk, isTrue);
    expect(rig.voice.calls.last, 'speak Ready.');
  });

  test('tts fallback then speakOnce err fails', () async {
    final rig = _Rig()
      ..speakFallsBack()
      ..voice.speakResult = const Err(IrisFailure(FailureKind.server));
    await rig.chat.open();
    final result = await rig.run();
    expect(_message(result), "Iris can't reach text-to-speech on hermes.local");
  });

  test('a speak stream that cannot open falls back to one-shot', () async {
    final rig = _Rig()..voice.socketFailure = const Err(IrisFailure.offline());
    await rig.chat.open();
    expect((await rig.run()).isOk, isTrue);
    expect(rig.voice.calls.last, 'speak Ready.');
  });

  test(
    'a speak stream that ends without audio falls back to one-shot',
    () async {
      final socket = FakeAudioSocket();
      final rig = _Rig()..voice.sockets.add(socket);
      await rig.chat.open();
      final running = rig.run();
      while (socket.sentJson.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      socket.serverSends({'type': 'start', 'sample_rate': 24000});
      socket.serverSends({'type': 'end'});
      expect((await running).isOk, isTrue);
      expect(rig.voice.calls.last, 'speak Ready.');
    },
  );

  test('a check over budget fails', () async {
    final rig = _Rig()..voice.transcribeGate = Completer<void>();
    await rig.chat.open();
    final result = await rig.run(budget: const Duration(milliseconds: 50));
    expect(_message(result), "Iris can't reach speech-to-text on hermes.local");
  });

  test('lease failure in the body does not fail', () async {
    final rig = _Rig()
      ..speakWorks()
      ..voice.leaseResult = const Err(
        IrisFailure(FailureKind.server, message: 'lease refused'),
      );
    await rig.chat.open();
    expect((await rig.run()).isOk, isTrue);
  });

  group('in a call', () {
    VoiceCall callFor(_Rig rig, FakeMic mic) => VoiceCall(
      chat: rig.chat,
      backend: rig.chatBackend,
      voice: rig.voice,
      capabilities: const VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: VoiceEngine.chained,
      ),
      settings: const VoiceSettings(),
      mic: mic,
      out: FakeAudioOut(),
      route: FakeAudioRoute(),
      server: _server,
    );

    test('nothing is recorded before success', () async {
      final rig = _Rig()..speakWorks();
      final gate = rig.voice.transcribeGate = Completer<void>();
      final mic = FakeMic();
      final call = callFor(rig, mic);
      await rig.chat.open();
      final begun = call.begin();
      await pumpEventQueue();
      expect(call.value.mode, CallMode.connecting);
      expect(call.value.step, PreflightStep.speechToText);
      expect(mic.starts, 0);

      gate.complete();
      await begun;
      await pumpEventQueue();
      expect(call.value.mode, CallMode.listening);
      expect(call.value.step, isNull);
      expect(mic.starts, 1);
      await call.end();
    });

    test('a failed check ends on the error, naming the part', () async {
      final rig = _Rig()
        ..voice.transcribeResult = const Err(IrisFailure.offline());
      final mic = FakeMic();
      final route = FakeAudioRoute();
      final call = VoiceCall(
        chat: rig.chat,
        backend: rig.chatBackend,
        voice: rig.voice,
        capabilities: const VoiceCapabilities(
          dictation: true,
          voiceMode: true,
          engine: VoiceEngine.chained,
        ),
        settings: const VoiceSettings(),
        mic: mic,
        out: FakeAudioOut(),
        route: route,
        server: _server,
      );
      await rig.chat.open();
      await call.begin();
      expect(call.value.mode, CallMode.error);
      expect(
        call.value.failure,
        "Iris can't reach speech-to-text on hermes.local",
      );
      expect(mic.starts, 0);
      expect(route.active, isFalse);
    });

    test('ending releases the leases', () async {
      final rig = _Rig()..speakWorks();
      final call = callFor(rig, FakeMic());
      await rig.chat.open();
      await call.begin();
      await call.end();
      await pumpEventQueue();
      expect(rig.voice.calls, containsAll(['lease stt off', 'lease tts off']));
    });
  });

  test('ensureLive resumes a chat that is not attached yet', () async {
    final backend = FakeChatBackend()
      ..resumeResult = const Err(IrisFailure.offline());
    final chat = ChatController(backend, conversationId: 'stored-1');
    await chat.open();
    expect(chat.runtimeId, isNull);
    backend.resumeResult = const Ok(ResumedConversation(runtimeId: 'run-2'));
    expect(await chat.ensureLive(), isTrue);
    expect(chat.runtimeId, 'run-2');
  });

  test('the silent clip is what the speech-to-text check sends', () {
    expect(silentWav().length, 44 + 9600);
  });
}
