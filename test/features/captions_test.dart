/// Live captions on the call screen (C1) and the call divider in the chat
/// transcript (C2).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/design/components/iris_voice_orb.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/voice/voice_call.dart';
import 'package:iris/features/voice/voice_call_screen.dart';
import 'package:iris/features/voice/voice_host.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';
import '../support/harness.dart';

const _run = 'run-1';

final class _Rig {
  _Rig({VoiceSettings settings = const VoiceSettings()}) {
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
      settings: settings,
      mic: mic,
      out: out,
      route: FakeAudioRoute(),
    );
  }

  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  final mic = FakeMic();
  final out = FakeAudioOut();
  late final ChatController chat;
  late final VoiceCall call;

  List<Caption> get captions => call.value.transcript;

  Future<void> begin() async {
    await chat.open();
    voice.sockets.add(FakeAudioSocket.speaking());
    await call.begin();
    await pumpEventQueue();
    voice.calls.clear();
    voice.opened.clear();
  }

  void talk(int ms, {int rms = 1000}) {
    for (var t = 0; t < ms; t += 100) {
      mic.pushLevel(rms);
    }
  }

  Future<void> say(String transcript) async {
    voice.transcribeResult = Ok(transcript);
    talk(1000);
    talk(3000, rms: 50);
    await pumpEventQueue();
  }

  void emit(ChatEvent event) => chatBackend.emit(event);
}

Widget _screen(_Rig rig) =>
    themed(VoiceCallScreen(call: rig.call, awake: FakeScreenAwake()));

TextStyle? _styleOf(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    ),
  );
  return rich.text.style;
}

void main() {
  group('the captions layer (C1)', () {
    testWidgets('shrinks the orb to 104 and lists both sides', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(_screen(rig));
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.speaking,
        captions: true,
        transcript: const [
          Caption(you: true, text: 'How do I migrate a StateNotifier?'),
          Caption(you: false, text: 'You extend Notifier instead.'),
        ],
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(IrisVoiceOrb).first),
        const Size(104, 104),
      );
      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('IRIS'), findsOneWidget);
      // You in sans, Iris in serif.
      expect(
        _styleOf(tester, 'How do I migrate a StateNotifier?')?.fontFamily,
        'Geist',
      );
      expect(
        _styleOf(tester, 'You extend Notifier instead.')?.fontFamily,
        'InstrumentSerif',
      );
    });

    testWidgets('off, the orb is back at full size and no captions show', (
      tester,
    ) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(_screen(rig));
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.speaking,
        transcript: const [Caption(you: false, text: 'Hello there.')],
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(IrisVoiceOrb).first),
        const Size(232, 232),
      );
      expect(find.text('IRIS'), findsNothing);
    });

    testWidgets('iris text is ink once spoken and muted before', (
      tester,
    ) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(_screen(rig));
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.speaking,
        captions: true,
        transcript: const [
          Caption(
            you: false,
            text: 'Yes. Annotate the class and the generator does the rest.',
            heard: 4,
          ),
        ],
      );
      await tester.pump();
      final context = tester.element(find.byType(VoiceCallScreen));
      final palette = context.palette;
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('Yes. Annotate'),
        ),
      );
      final spans = <InlineSpan>[];
      rich.text.visitChildren((span) {
        spans.add(span);
        return true;
      });
      final ink = spans.whereType<TextSpan>().firstWhere(
        (span) => span.text == 'Yes.',
      );
      final waiting = spans.whereType<TextSpan>().firstWhere(
        (span) =>
            span.text == ' Annotate the class and the generator does the rest.',
      );
      expect(ink.style?.color, palette.ink);
      expect(waiting.style?.color, palette.inkMuted);
    });

    testWidgets('partial words show as the last line of you', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(_screen(rig));
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.hearing,
        captions: true,
        transcript: const [Caption(you: true, text: 'does that work with')],
      );
      await tester.pump();
      expect(find.text('does that work with'), findsOneWidget);
      expect(find.text('YOU'), findsOneWidget);
    });

    testWidgets('captions default from the settings', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig(settings: const VoiceSettings(captions: true));
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(_screen(rig));
      rig.call.value = rig.call.value.copyWith(mode: CallMode.listening);
      await tester.pump();
      expect(
        tester.getSize(find.byType(IrisVoiceOrb).first),
        const Size(104, 104),
      );
    });

    testWidgets('a card in the way puts the full orb back', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(_screen(rig));
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.needs,
        captions: true,
        decision: const ApprovalDecision(
          ApprovalRequest(
            sessionId: _run,
            command: 'ls',
            description: '',
            choices: ['once', 'deny'],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('200% text does not overflow with captions on', (tester) async {
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
      rig.call.value = rig.call.value.copyWith(
        mode: CallMode.speaking,
        captions: true,
        transcript: [
          for (var i = 0; i < 6; i++) ...[
            Caption(you: true, text: 'A question number $i about Riverpod?'),
            Caption(
              you: false,
              text:
                  'An answer number $i that goes on for a good while so it wraps.',
            ),
          ],
        ],
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('what the engine marks as heard', () {
    test('a sentence is muted until its audio starts, then ink', () async {
      final rig = _Rig();
      await rig.begin();
      await rig.say('hello');
      rig.emit(const MessageStarted(_run));
      rig.emit(const TextDelta(_run, 'You extend Notifier instead.'));
      await pumpEventQueue();

      var iris = rig.captions.lastWhere((c) => !c.you);
      expect(iris.text, 'You extend Notifier instead.');
      expect(iris.heard, 0);

      // The audio starts: what was sent is now being said.
      final socket = rig.voice.opened.last;
      socket
        ..serverSends({'type': 'start', 'sample_rate': 24000, 'channels': 1})
        ..serverSendsBytes(Uint8List.fromList(List.filled(480, 1)));
      await pumpEventQueue();
      iris = rig.captions.lastWhere((c) => !c.you);
      expect(iris.heard, 'You extend Notifier instead.'.length);

      // More text arrives while it plays: that part waits.
      rig.emit(const TextDelta(_run, ' The state is made in build.'));
      await pumpEventQueue();
      iris = rig.captions.lastWhere((c) => !c.you);
      expect(
        iris.text,
        'You extend Notifier instead. The state is made in build.',
      );
      expect(iris.heard, 'You extend Notifier instead.'.length);

      // When the reply is spoken in full, all of it is ink.
      rig.emit(const MessageCompleted(_run));
      socket.serverSends({'type': 'end'});
      await pumpEventQueue();
      rig.out.drain();
      await pumpEventQueue();
      iris = rig.captions.lastWhere((c) => !c.you);
      expect(iris.heard, isNull);
      await rig.call.end();
    });
  });

  group('the call divider (C2)', () {
    late FakeChatBackend backend;
    setUp(() => backend = FakeChatBackend());
    tearDown(() => backend.close());

    final started = DateTime(2026, 10, 19, 9);
    const items = [
      UserTurn(id: 'u0', text: 'First question'),
      AssistantTurn(id: 'a0', text: 'First answer'),
      UserTurn(id: 'u1', text: 'Spoken question'),
      AssistantTurn(id: 'a1', text: 'Spoken answer'),
      UserTurn(id: 'u2', text: 'Typed afterwards'),
    ];

    VoiceHost host(List<VoiceCallSpan> spans) => VoiceHost(
      backend: FakeVoiceBackend(),
      capabilities: const VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: VoiceEngine.chained,
      ),
      spans: spans,
      onCallEnded: (_, _) {},
    );

    Future<void> open(WidgetTester tester, List<VoiceCallSpan> spans) async {
      backend.historyResult = const Ok(items);
      await tester.pumpWidget(
        themed(
          ChatScreen(
            backend: backend,
            conversationId: 'stored-1',
            voice: host(spans),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a divider before the call and an end note after it', (
      tester,
    ) async {
      await open(tester, [
        VoiceCallSpan(
          startedAt: started,
          endedAt: started.add(const Duration(minutes: 4, seconds: 12)),
          fromIndex: 2,
          toIndex: 4,
        ),
      ]);
      expect(find.text('voice · 4 min'), findsOneWidget);
      expect(find.text('call ended 4:12'), findsOneWidget);

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('First answer'), lessThan(top('voice · 4 min')));
      expect(top('voice · 4 min'), lessThan(top('Spoken question')));
      expect(top('Spoken answer'), lessThan(top('call ended 4:12')));
      expect(top('call ended 4:12'), lessThan(top('Typed afterwards')));
    });

    testWidgets('a call with no end index ends where the transcript does', (
      tester,
    ) async {
      await open(tester, [
        VoiceCallSpan(
          startedAt: started,
          endedAt: started.add(const Duration(seconds: 40)),
          fromIndex: 3,
        ),
      ]);
      expect(find.text('voice · 40 s'), findsOneWidget);
      expect(find.text('call ended 0:40'), findsOneWidget);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Typed afterwards'), lessThan(top('call ended 0:40')));
    });

    testWidgets('no spans, no divider', (tester) async {
      await open(tester, const []);
      expect(find.textContaining('voice ·'), findsNothing);
      expect(find.textContaining('call ended'), findsNothing);
    });

    testWidgets('a call that produced nothing leaves no divider', (
      tester,
    ) async {
      await open(tester, [
        VoiceCallSpan(
          startedAt: started,
          endedAt: started.add(const Duration(minutes: 1)),
          fromIndex: 2,
          toIndex: 2,
        ),
      ]);
      expect(find.textContaining('voice ·'), findsNothing);
    });

    testWidgets('a span past the end of the transcript is ignored', (
      tester,
    ) async {
      await open(tester, [
        VoiceCallSpan(
          startedAt: started,
          endedAt: started.add(const Duration(minutes: 1)),
          fromIndex: 40,
        ),
      ]);
      expect(find.textContaining('voice ·'), findsNothing);
    });
  });

  group('span storage', () {
    test('toIndex survives storing and older records still load', () {
      final span = VoiceCallSpan(
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        fromIndex: 2,
        toIndex: 6,
      );
      expect(VoiceCallSpan.decodeList(VoiceCallSpan.encodeList([span])), [
        span,
      ]);
      const legacy = '[{"s":1000,"e":5000,"i":2}]';
      final loaded = VoiceCallSpan.decodeList(legacy).single;
      expect(loaded.toIndex, isNull);
      expect(loaded.fromIndex, 2);
    });
  });
}
