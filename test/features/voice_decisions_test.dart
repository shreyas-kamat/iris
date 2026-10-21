/// Approvals and questions by voice (frames B9a, B9b): the matching of what
/// was said, and the flow on both engines.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/voice/spoken.dart';
import 'package:iris/features/voice/voice_call.dart';
import 'package:iris/features/voice/voice_call_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';
import '../support/harness.dart';

const _run = 'run-1';

const _push = ApprovalRequest(
  sessionId: _run,
  command: 'git push origin main',
  description: 'Push to the remote',
  choices: ['once', 'session', 'always', 'deny'],
  queueId: 'q1',
);

const _deploy = ClarifyRequest(
  requestId: 'srq-1',
  sessionId: _run,
  questions: [
    ClarifyQuestion(
      id: 'env',
      text: 'Which environment should I deploy to?',
      choices: [
        ClarifyChoice(label: 'Staging', value: 'staging'),
        ClarifyChoice(label: 'Production', value: 'production'),
      ],
    ),
  ],
);

/// A chained call on a conversation that is already live as [_run].
final class _Rig {
  _Rig({
    VoiceEngine engine = VoiceEngine.chained,
    VoiceTuning tuning = const VoiceTuning(thinkingSound: false),
  }) {
    chat = ChatController(chatBackend, conversationId: 'stored-1');
    call = VoiceCall(
      chat: chat,
      backend: chatBackend,
      voice: voice,
      capabilities: VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: engine,
        tuning: tuning,
      ),
      settings: const VoiceSettings(),
      mic: mic,
      out: out,
      route: FakeAudioRoute(),
      livePeer: () => peer,
      clock: () => now,
    );
  }

  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  final mic = FakeMic();
  final out = FakeAudioOut();
  final peer = FakeLivePeer();
  late final ChatController chat;
  late final VoiceCall call;
  DateTime now = DateTime(2026, 10, 19, 9);

  CallMode get mode => call.value.mode;
  CallDecision? get decision => call.value.decision;

  Future<void> begin() async {
    await chat.open();
    voice.sockets.add(FakeAudioSocket.speaking());
    await call.begin();
    await pumpEventQueue();
    voice.calls.clear();
    voice.opened.clear();
    voice.wavs.clear();
    voice.transcribed.clear();
  }

  void talk(int ms, {int rms = 1000}) {
    for (var t = 0; t < ms; t += 100) {
      mic.pushLevel(rms);
    }
  }

  /// One whole take: a second of speech, then the silence that ends it.
  Future<void> say(String transcript) async {
    voice.transcribeResult = Ok(transcript);
    talk(1000);
    talk(3000, rms: 50);
    await pumpEventQueue();
  }

  void emit(ChatEvent event) => chatBackend.emit(event);

  /// The user said something and the agent started on it.
  Future<void> startTurn() async {
    await say('push my work');
    emit(const MessageStarted(_run));
    await pumpEventQueue();
  }

  FakeAudioSocket get speakSocket => voice.opened.last;

  List<String> get spokenTexts => [
    for (final socket in voice.opened)
      for (final frame in socket.sentJson)
        if (frame['text'] is String) frame['text']! as String,
  ];

  /// The server plays what it was sent, and the playback finishes.
  Future<void> serverSpeaks() async {
    speakSocket
      ..serverSends({'type': 'start', 'sample_rate': 24000, 'channels': 1})
      ..serverSendsBytes(Uint8List.fromList(List.filled(480, 1)))
      ..serverSends({'type': 'end'});
    await pumpEventQueue();
    out.drain();
    await pumpEventQueue();
  }

  Future<void> ask(ApprovalRequest request) async {
    voice.sockets.add(FakeAudioSocket());
    emit(ApprovalAsked(request));
    await pumpEventQueue();
  }
}

void main() {
  group('matching what was said', () {
    test('approve', () {
      for (final heard in [
        'approve',
        'Yes.',
        'go ahead',
        'Yeah, do it',
        'Okay!',
      ]) {
        expect(matchApproval(heard), SpokenVerdict.approve, reason: heard);
      }
    });

    test('deny', () {
      for (final heard in ['deny', 'No.', "don't", 'Don’t do that', 'Nope']) {
        expect(matchApproval(heard), SpokenVerdict.deny, reason: heard);
      }
    });

    test('anything unclear is neither', () {
      for (final heard in [
        'maybe later',
        '',
        'what does that do',
        'hmm let me think about it for a good while longer please',
      ]) {
        expect(matchApproval(heard), isNull, reason: heard);
      }
    });

    test('a refusal wins over a yes', () {
      expect(matchApproval("yes no wait don't"), SpokenVerdict.deny);
    });

    test('a choice is matched by its words', () {
      const choices = ['Staging', 'Production'];
      expect(matchChoice('staging', choices), 'Staging');
      expect(matchChoice('Go with production, please.', choices), 'Production');
    });

    test('an ordinal or an unknown answer matches no choice', () {
      const choices = ['Staging', 'Production'];
      expect(matchChoice('the second one', choices), isNull);
      expect(matchChoice('something else', choices), isNull);
      expect(matchChoice('staging or production', choices), isNull);
      expect(matchChoice('anything', const []), isNull);
    });
  });

  group('the chained call', () {
    test('approval mid-call: asked aloud, answered by a spoken yes', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      expect(rig.mode, CallMode.thinking);

      await rig.ask(_push);
      expect(rig.mode, CallMode.needs);
      final decision = rig.decision;
      expect(decision, isA<ApprovalDecision>());
      expect(decision!.prompt, 'Shall I run git push origin main?');
      expect(rig.spokenTexts, ['Shall I run git push origin main?']);
      expect(rig.speakSocket.sentJson.last, {'done': true});

      // The prompt plays, then the call listens for the answer.
      expect(rig.mic.open, isFalse);
      await rig.serverSpeaks();
      expect(rig.mic.open, isTrue);
      expect(rig.mode, CallMode.needs);

      await rig.say('yes');
      expect(rig.chatBackend.approvals, ['once']);
      expect(rig.decision, isNull);
      expect(rig.mode, CallMode.thinking);
      expect(rig.mic.open, isFalse);
      // The answer is not sent to the agent as a new turn.
      expect(rig.chatBackend.submitted, hasLength(1));
    });

    test('deny sends deny', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      await rig.ask(_push);
      await rig.serverSpeaks();
      await rig.say('no, deny it');
      expect(rig.chatBackend.approvals, ['deny']);
      expect(rig.decision, isNull);
    });

    test('approve uses the first choice that is not deny', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      await rig.ask(
        const ApprovalRequest(
          sessionId: _run,
          command: 'ls',
          description: '',
          choices: ['deny', 'session', 'once'],
          queueId: 'q2',
        ),
      );
      await rig.serverSpeaks();
      await rig.say('approve');
      expect(rig.chatBackend.approvals, ['session']);
    });

    test('unclear asks once more, then waits', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      await rig.ask(_push);
      await rig.serverSpeaks();

      rig.voice.sockets.add(FakeAudioSocket());
      await rig.say('maybe later');
      expect(rig.chatBackend.approvals, isEmpty);
      expect(rig.mode, CallMode.needs);
      expect(rig.spokenTexts, hasLength(2));
      expect(rig.spokenTexts.last, contains('approve or deny'));
      await rig.serverSpeaks();
      expect(rig.mic.open, isTrue);

      await rig.say('hmm, not sure');
      expect(rig.chatBackend.approvals, isEmpty);
      expect(rig.spokenTexts, hasLength(2));
      expect(rig.mode, CallMode.needs);
      expect(rig.mic.open, isTrue);

      await rig.say('approve');
      expect(rig.chatBackend.approvals, ['once']);
    });

    test('tapping always works, even while the prompt is playing', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      await rig.ask(_push);
      await rig.serverSpeaks();
      expect(rig.mode, CallMode.needs);

      await rig.call.approve(_push, SpokenVerdict.deny);
      await pumpEventQueue();
      expect(rig.chatBackend.approvals, ['deny']);
      expect(rig.decision, isNull);
      expect(rig.mode, CallMode.thinking);
      expect(rig.mic.open, isFalse);
    });

    test('a spoken answer to a question picks the matching choice', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      rig.voice.sockets.add(FakeAudioSocket());
      rig.emit(ClarifyAsked(_deploy));
      await pumpEventQueue();
      expect(rig.mode, CallMode.needs);
      expect(rig.decision, isA<QuestionDecision>());
      expect(rig.spokenTexts, ['Which environment should I deploy to?']);
      await rig.serverSpeaks();

      await rig.say('production');
      expect(rig.chatBackend.answers, ['env=production']);
      expect(rig.decision, isNull);
    });

    test('a spoken free answer is sent as it was heard', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      rig.voice.sockets.add(FakeAudioSocket());
      rig.emit(ClarifyAsked(_deploy));
      await pumpEventQueue();
      await rig.serverSpeaks();

      await rig.say('the second one');
      expect(rig.chatBackend.answers, ['env=the second one']);
      expect(rig.decision, isNull);
    });

    test('a withdrawn request clears the card', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      await rig.ask(_push);
      await rig.serverSpeaks();
      expect(rig.decision, isNotNull);

      rig.emit(const RequestWithdrawn(_run, 'q1'));
      await pumpEventQueue();
      expect(rig.decision, isNull);
      expect(rig.mode, CallMode.thinking);
      expect(rig.mic.open, isFalse);
    });

    test('a request outside a turn does not take over the call', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.ask(_push);
      expect(rig.mode, CallMode.listening);
      expect(rig.decision, isNull);
    });

    test('stopping the call while a card is up ends it cleanly', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.startTurn();
      await rig.ask(_push);
      await rig.call.end();
      expect(rig.mic.open, isFalse);
      expect(rig.call.value.isOver, isTrue);
    });
  });

  group('the GPT-Live call', () {
    test(
      'speaks it as commentary and takes the next words as the answer',
      () async {
        final rig = _Rig(engine: VoiceEngine.gptLive);
        await rig.chat.open();
        await rig.call.begin();
        await pumpEventQueue();
        rig.peer.serverSends({
          'type': 'session.delegation.created',
          'delegation': {'id': 'd1', 'text': 'push my work'},
        });
        await pumpEventQueue();
        expect(rig.mode, CallMode.thinking);

        rig.emit(ApprovalAsked(_push));
        await pumpEventQueue();
        expect(rig.mode, CallMode.needs);
        expect(rig.decision, isA<ApprovalDecision>());
        expect(rig.peer.sent.last, {
          'type': 'session.commentary.append',
          'text': 'Shall I run git push origin main?',
        });

        rig.peer.serverSends({
          'type': 'session.input_transcript.delta',
          'delta': 'deny',
        });
        await Future<void>.delayed(const Duration(milliseconds: 1700));
        expect(rig.chatBackend.approvals, ['deny']);
        expect(rig.decision, isNull);
        expect(rig.mode, CallMode.thinking);
      },
    );

    test('tapping answers and clears the card', () async {
      final rig = _Rig(engine: VoiceEngine.gptLive);
      await rig.chat.open();
      await rig.call.begin();
      await pumpEventQueue();
      rig.peer.serverSends({
        'type': 'session.delegation.created',
        'delegation': {'id': 'd1', 'text': 'push my work'},
      });
      await pumpEventQueue();
      rig.emit(ApprovalAsked(_push));
      await pumpEventQueue();
      await rig.call.approve(_push, SpokenVerdict.approve);
      await pumpEventQueue();
      expect(rig.chatBackend.approvals, ['once']);
      expect(rig.decision, isNull);
    });

    test('a spoken question answer goes through', () async {
      final rig = _Rig(engine: VoiceEngine.gptLive);
      await rig.chat.open();
      await rig.call.begin();
      await pumpEventQueue();
      rig.peer.serverSends({
        'type': 'session.delegation.created',
        'delegation': {'id': 'd1', 'text': 'deploy'},
      });
      await pumpEventQueue();
      rig.emit(ClarifyAsked(_deploy));
      await pumpEventQueue();
      expect(
        rig.peer.sent.last['text'],
        'Which environment should I deploy to?',
      );
      rig.peer.serverSends({
        'type': 'session.input_transcript.delta',
        'delta': 'Staging',
      });
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(rig.chatBackend.answers, ['env=staging']);
    });
  });

  group('the cards (B9a, B9b)', () {
    Future<_Rig> shown(WidgetTester tester, CallDecision decision) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(
        themed(VoiceCallScreen(call: rig.call, awake: FakeScreenAwake())),
      );
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.needs,
        decision: decision,
      );
      await tester.pump();
      return rig;
    }

    testWidgets('B9a shows the command in mono, with Deny and Approve', (
      tester,
    ) async {
      await shown(tester, const ApprovalDecision(_push));
      expect(find.text('NEEDS YOUR OK'), findsOneWidget);
      expect(find.text('Shall I run git push origin main?'), findsOneWidget);
      expect(find.text('Say “approve” or “deny”, or tap.'), findsOneWidget);
      expect(find.text('git push origin main'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('B9b lists the choices and a free answer', (tester) async {
      await shown(tester, QuestionDecision(_deploy, _deploy.questions.first));
      expect(find.text('IRIS ASKS'), findsOneWidget);
      expect(
        find.text('Which environment should I deploy to?'),
        findsOneWidget,
      );
      expect(find.text('Say your answer, or tap one.'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Something else…'), findsOneWidget);
    });

    testWidgets('tapping Approve and a choice answers through the call', (
      tester,
    ) async {
      final rig = await shown(tester, const ApprovalDecision(_push));
      await tester.tap(find.text('Approve'));
      await tester.pump();
      expect(rig.chatBackend.approvals, ['once']);

      final again = await shown(
        tester,
        QuestionDecision(_deploy, _deploy.questions.first),
      );
      await tester.tap(find.text('Production'));
      await tester.pump();
      expect(again.chatBackend.answers, ['env=production']);
    });

    testWidgets('200% text does not overflow on a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(
        themed(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: VoiceCallScreen(call: rig.call, awake: FakeScreenAwake()),
          ),
        ),
      );
      for (final decision in [
        const ApprovalDecision(_push),
        QuestionDecision(_deploy, _deploy.questions.first),
      ]) {
        rig.call.value = rig.call.value.copyWith(
          mode: CallMode.needs,
          decision: decision,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
