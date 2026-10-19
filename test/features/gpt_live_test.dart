import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/voice/gpt_live_engine.dart';
import 'package:iris/features/voice/voice_call.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';

const _run = 'run-1';

final class _Rig {
  _Rig({bool autoStart = true, List<TranscriptItem> history = const []}) {
    peer = FakeLivePeer(autoStart: autoStart);
    chatBackend.historyResult = Ok(history);
    chat = ChatController(chatBackend, conversationId: 'stored-1');
    call = VoiceCall(
      chat: chat,
      backend: chatBackend,
      voice: voice,
      capabilities: const VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: VoiceEngine.gptLive,
      ),
      settings: const VoiceSettings(),
      mic: mic,
      out: FakeAudioOut(),
      route: FakeAudioRoute(),
      server: 'hermes.local',
      livePeer: () => peer,
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
  late final FakeLivePeer peer;
  late final ChatController chat;
  late final VoiceCall call;
  final modes = <CallMode>[];
  DateTime now = DateTime(2026, 10, 19, 9);

  CallMode get mode => call.value.mode;

  Future<void> begin() async {
    await chat.open();
    await call.begin();
    await pumpEventQueue();
  }

  Future<void> send(Map<String, Object?> event) async {
    peer.serverSends(event);
    await pumpEventQueue();
  }

  Future<void> userSays(String text) =>
      send({'type': 'session.input_transcript.delta', 'delta': text});

  Future<void> irisSays(String text) =>
      send({'type': 'session.output_transcript.delta', 'delta': text});

  Future<void> delegate([String id = 'd1']) => send({
    'type': 'session.delegation.created',
    'delegation': {'id': id},
  });
}

List<TranscriptItem> _turns(int pairs) => [
  for (var i = 0; i < pairs; i++) ...[
    UserTurn(id: 'u$i', text: 'question $i'),
    AssistantTurn(id: 'a$i', text: 'answer $i'),
  ],
];

void main() {
  test('history shape', () {
    final history = liveHistory(_turns(6));
    expect(history, hasLength(10));
    expect(history.first, {
      'type': 'message',
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': 'question 1'},
      ],
    });
    expect(history.last, {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': 'answer 5'},
      ],
    });
  });

  test('the call offers its history with the SDP', () async {
    final rig = _Rig(history: _turns(2));
    await rig.begin();
    expect(rig.voice.offers.single, rig.peer.offerSdp);
    expect(rig.voice.histories.single, hasLength(4));
    expect(rig.peer.answered, 'v=0\r\n');
  });

  test('preflight waits for session.started', () async {
    final rig = _Rig(autoStart: false);
    await rig.chat.open();
    final begun = rig.call.begin();
    await pumpEventQueue();
    expect(rig.mode, CallMode.connecting);
    expect(rig.call.value.step, PreflightStep.gptLive);
    expect(rig.peer.micOn, isFalse, reason: 'nothing is heard before');

    rig.peer.serverSends({'type': 'session.started'});
    await begun;
    await pumpEventQueue();
    expect(rig.mode, CallMode.listening);
    expect(rig.peer.micOn, isTrue);
    await rig.call.end();
  });

  test('a refused session fails with the server detail', () async {
    final rig = _Rig()
      ..voice.gptLiveResult = const Err(
        IrisFailure(
          FailureKind.server,
          statusCode: 503,
          message: 'No OpenAI API key is configured.',
        ),
      );
    await rig.begin();
    expect(rig.mode, CallMode.error);
    expect(
      rig.call.value.failure,
      "GPT-Live couldn't start: No OpenAI API key is configured.",
    );
    expect(rig.peer.closed, isTrue);
  });

  test('the agent is checked first', () async {
    final rig = _Rig()
      ..chatBackend.resumeResult = const Err(IrisFailure.offline());
    await rig.begin();
    expect(
      rig.call.value.failure,
      "Iris can't reach the agent on hermes.local",
    );
    expect(rig.voice.calls, isNot(contains('gptLive')));
  });

  test('delegation becomes a voice-live turn', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.irisSays('Hi, what can I do?');
    await rig.userSays('add a task ');
    await rig.userSays('to triage');
    expect(rig.mode, CallMode.hearing);
    await rig.delegate();

    expect(rig.chatBackend.submits.single.$2, 'add a task to triage');
    final voice = rig.chatBackend.voiceSubmits.single!;
    expect(voice.surface, 'voice-live');
    expect(voice.voiceTurn, isFalse);
    expect(
      voice.voiceContext,
      'assistant: Hi, what can I do?\nuser: add a task to triage',
    );
    expect(rig.mode, CallMode.thinking);
    expect(rig.call.value.transcript.map((c) => (c.you, c.text)), [
      (false, 'Hi, what can I do?'),
      (true, 'add a task to triage'),
    ]);

    // The same delegation announced twice is one turn.
    await rig.delegate();
    expect(rig.chatBackend.submits, hasLength(1));
  });

  test(
    'the context keeps the newest 6,000 chars of the last five minutes',
    () async {
      final rig = _Rig();
      await rig.begin();
      await rig.userSays('this is from long ago');
      rig.now = rig.now.add(const Duration(minutes: 6));
      for (var i = 0; i < 40; i++) {
        await rig.irisSays('${'a' * 90} $i.');
        await rig.userSays('${'u' * 90} $i.');
      }
      await rig.delegate();
      final context = rig.chatBackend.voiceSubmits.single!.voiceContext!;
      expect(context.length, lessThanOrEqualTo(6000));
      expect(context, isNot(contains('long ago')));
      expect(context.split('\n').last, 'user: ${'u' * 90} 39.');
      expect(
        context.split('\n').first,
        anyOf(startsWith('assistant: '), startsWith('user: ')),
      );
    },
  );

  test('the reply goes back as commentary', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.userSays('write me a report');
    await rig.delegate();
    final sentence = '${'word ' * 19}end.';
    final reply = List.filled(30, sentence).join(' ');
    expect(reply.length, greaterThan(2900));
    rig.chatBackend.emit(MessageCompleted(_run, content: reply));
    await pumpEventQueue();

    final commentary = [
      for (final e in rig.peer.sent)
        if (e['type'] == 'session.commentary.append') e['text']! as String,
    ];
    expect(commentary, hasLength(3));
    for (final chunk in commentary) {
      expect(chunk.length, lessThanOrEqualTo(1400));
      expect(chunk, endsWith('end.'));
    }
    expect(commentary.join(' '), reply);
    expect(rig.mode, CallMode.listening);
  });

  test('a streamed reply is sent back when it completes', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.userSays('push it');
    await rig.delegate();
    rig.chatBackend
      ..emit(const TextDelta(_run, 'Pushed '))
      ..emit(const TextDelta(_run, 'to main.'))
      ..emit(const MessageCompleted(_run));
    await pumpEventQueue();
    expect(rig.peer.sent.last, {
      'type': 'session.commentary.append',
      'text': 'Pushed to main.',
    });
  });

  test('tools show while the turn runs', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.userSays('search it');
    await rig.delegate();
    rig.chatBackend.emit(
      const ToolStarted(_run, name: 'web.search', input: 'riverpod'),
    );
    await pumpEventQueue();
    expect(rig.mode, CallMode.tool);
    expect(rig.call.value.tool, 'web.search · riverpod');
    rig.chatBackend.emit(const ToolCompleted(_run, name: 'web.search'));
    await pumpEventQueue();
    expect(rig.mode, CallMode.thinking);
    expect(rig.call.value.toolTrail, ['web.search · riverpod']);
  });

  test('modes from the channel', () async {
    final rig = _Rig();
    await rig.begin();
    expect(rig.mode, CallMode.listening);
    await rig.userSays('hello');
    expect(rig.mode, CallMode.hearing);
    rig.peer.level(0.2);
    await pumpEventQueue();
    expect(rig.mode, CallMode.speaking);
    expect(rig.call.value.level.value, closeTo(0.2, 1e-9));
    rig.peer.level(0.01);
    await pumpEventQueue();
    expect(rig.mode, CallMode.listening);
    await rig.delegate();
    expect(rig.mode, CallMode.thinking);
    rig.peer.level(0.3);
    await pumpEventQueue();
    expect(rig.mode, CallMode.speaking, reason: 'the model talks meanwhile');
    rig.peer.level(0);
    await pumpEventQueue();
    expect(rig.mode, CallMode.thinking);
  });

  test('mute and end', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.call.setMuted(muted: true);
    expect(rig.peer.sentTypes.last, 'session.input_audio.mute');
    expect(rig.peer.micOn, isFalse);
    expect(rig.mode, CallMode.muted);
    await rig.call.setMuted(muted: false);
    expect(rig.peer.sentTypes.last, 'session.input_audio.unmute');
    expect(rig.peer.micOn, isTrue);

    await rig.call.end();
    expect(rig.peer.sentTypes.last, 'session.close');
    expect(rig.peer.closed, isTrue);
    expect(rig.mode, CallMode.ended);
  });

  test('session.closed ends the call', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.send({'type': 'session.closed'});
    expect(rig.mode, CallMode.ended);
    expect(rig.peer.closed, isTrue);
  });

  test('fatal error', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.send({
      'type': 'error',
      'error': {'message': 'The realtime session expired.'},
    });
    expect(rig.mode, CallMode.error);
    expect(rig.call.value.failure, 'The realtime session expired.');
    expect(rig.peer.closed, isTrue);
  });

  test('a pause closes the mic and resume opens it', () async {
    final rig = _Rig();
    await rig.begin();
    await rig.call.pause(PauseReason.phoneCall);
    expect(rig.mode, CallMode.paused);
    expect(rig.peer.micOn, isFalse);
    await rig.call.resume();
    expect(rig.mode, CallMode.listening);
    expect(rig.peer.micOn, isTrue);
  });

  group('chunker', () {
    test('chunker keeps sentences whole', () {
      final chunks = chunkForCommentary(
        'One. Two is longer! Three? Four.',
        limit: 14,
      );
      expect(chunks, ['One.', 'Two is longer!', 'Three? Four.']);
    });

    test('a sentence longer than the limit is cut at a space', () {
      final chunks = chunkForCommentary('${'word ' * 10}end.', limit: 20);
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(20));
      }
      expect(chunks.join(' '), '${'word ' * 10}end.');
    });

    test('nothing to say is no chunks', () {
      expect(chunkForCommentary('   '), isEmpty);
    });
  });
}
