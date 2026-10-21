/// The live voice screen (frames B1 to B10b, B2b, D3a, D3b): what each state
/// of a call says, the controls, and how the screen is entered and left.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/design/components/iris_voice_orb.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/voice/audio/audio_route.dart';
import 'package:iris/features/voice/voice_call.dart';
import 'package:iris/features/voice/voice_call_screen.dart';
import 'package:iris/features/voice/voice_host.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';
import '../support/harness.dart';

/// A call, its fakes and the screen's seams.
final class _Rig {
  _Rig({
    VoiceSettings settings = const VoiceSettings(),
    this.engine = VoiceEngine.chained,
    String server = 'hermes.local',
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
        tuning: const VoiceTuning(thinkingSound: false),
      ),
      settings: settings,
      mic: mic,
      out: out,
      route: route,
      server: server,
      service: service,
    );
  }

  final VoiceEngine engine;
  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  final mic = FakeMic();
  final out = FakeAudioOut();
  final route = FakeAudioRoute();
  final service = FakeCallService();
  final awake = FakeScreenAwake();
  late final ChatController chat;
  late final VoiceCall call;

  /// Opens the chat and passes the preflight, as the chat screen would.
  Future<void> begin(WidgetTester tester) => tester.runAsync(() async {
    await chat.open();
    voice.sockets.add(FakeAudioSocket.speaking());
    await call.begin();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  /// Puts the call in [mode] without running the engine through it.
  void show(
    CallMode mode, {
    String? tool,
    List<String> trail = const [],
    Duration? workingFor,
    Duration? elapsed,
    PauseReason? paused,
    String? failure,
    PreflightStep? step,
    bool? muted,
  }) {
    call.value = call.value.copyWith(
      mode: mode,
      tool: tool,
      clearTool: tool == null,
      toolTrail: trail,
      workingFor: workingFor,
      clearWorkingFor: workingFor == null,
      elapsed: elapsed,
      paused: paused,
      clearPaused: paused == null,
      failure: failure,
      step: step,
      clearStep: step == null,
      muted: muted,
    );
  }
}

Widget _screen(_Rig rig, {MediaQueryData? media}) {
  final screen = VoiceCallScreen(call: rig.call, awake: rig.awake);
  // Inside the harness, which pins its own window size.
  return themed(
    media == null ? screen : MediaQuery(data: media, child: screen),
  );
}

Future<void> _pumpScreen(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(_screen(rig));
  await tester.pump();
}

Future<void> _nap(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 60)),
);

/// A button that opens the call screen and records how it was left.
Widget _opener(_Rig rig, void Function(VoiceCallExit? exit) onExit) => themed(
  Builder(
    builder: (context) => TextButton(
      onPressed: () async => onExit(
        await openVoiceCall(context, call: rig.call, awake: rig.awake),
      ),
      child: const Text('open'),
    ),
  ),
);

void main() {
  group('what each state says', () {
    Future<void> check(
      WidgetTester tester,
      CallMode mode,
      List<String> texts, {
      String? tool,
      List<String> trail = const [],
      Duration? workingFor,
      Duration? elapsed,
      PauseReason? paused,
      String? failure,
      PreflightStep? step,
      bool? muted,
      List<String> absent = const [],
    }) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(
        mode,
        tool: tool,
        trail: trail,
        workingFor: workingFor,
        elapsed: elapsed,
        paused: paused,
        failure: failure,
        step: step,
        muted: muted,
      );
      await tester.pump();
      for (final text in texts) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final text in absent) {
        expect(find.text(text), findsNothing, reason: text);
      }
    }

    testWidgets('B1 connecting, with the step under way', (tester) async {
      await check(tester, CallMode.connecting, [
        'CONNECTING',
        'Connecting to hermes.local…',
        'Checking speech-to-text…',
      ], step: PreflightStep.speechToText);
    });

    testWidgets('B1 connecting, before any step', (tester) async {
      await check(tester, CallMode.connecting, [
        'CONNECTING',
        'This takes a moment.',
      ]);
    });

    testWidgets('B2 listening', (tester) async {
      await check(tester, CallMode.listening, [
        'LISTENING',
        'I’m listening.',
        'Just start talking.',
      ]);
    });

    testWidgets('B3 hearing you', (tester) async {
      await check(tester, CallMode.hearing, [
        'HEARING YOU',
        'Pause when you’re done.',
      ]);
    });

    testWidgets('B4 thinking shows the clock after ten seconds', (
      tester,
    ) async {
      await check(tester, CallMode.thinking, [
        'THINKING · 01:48',
        'Working on it.',
        'This can take a few minutes. You can lock your screen; I’ll keep going.',
      ], workingFor: const Duration(minutes: 1, seconds: 48));
      await check(
        tester,
        CallMode.thinking,
        ['THINKING'],
        workingFor: const Duration(seconds: 4),
        absent: ['THINKING · 00:04'],
      );
    });

    testWidgets('B5 a tool pill and the trail of finished ones', (
      tester,
    ) async {
      await check(
        tester,
        CallMode.tool,
        [
          'RUNNING A TOOL · 02:07',
          'Looking that up.',
          'web.search',
          'flutter riverpod 3',
          'web.fetch · riverpod.dev/docs/3.0',
          'web.search · riverpod 3 migration',
        ],
        tool: 'web.search · flutter riverpod 3',
        trail: [
          'web.fetch · riverpod.dev/docs/3.0',
          'web.search · riverpod 3 migration',
        ],
        workingFor: const Duration(minutes: 2, seconds: 7),
      );
    });

    testWidgets('B6 speaking', (tester) async {
      await check(tester, CallMode.speaking, [
        'SPEAKING',
        'Talk any time to interrupt.',
      ]);
    });

    testWidgets('B7 barge-in, with the cut shown', (tester) async {
      await check(tester, CallMode.interrupted, [
        'INTERRUPTED · LISTENING',
        'Go on.',
        'Iris stopped mid-sentence and is listening.',
        '0 ms',
        '120 ms',
        '300 ms',
      ]);
    });

    testWidgets('B8 muted offers Unmute and says replies still play', (
      tester,
    ) async {
      await check(
        tester,
        CallMode.muted,
        [
          'MUTED',
          'Your mic is off.',
          'Iris can’t hear you. Replies still play.',
          'UNMUTE',
        ],
        muted: true,
        absent: ['MUTE'],
      );
    });

    testWidgets('B10a reconnecting counts the seconds since the link dropped', (
      tester,
    ) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.reconnecting, elapsed: const Duration(seconds: 100));
      await tester.pump();
      rig.show(CallMode.reconnecting, elapsed: const Duration(seconds: 108));
      await tester.pump();
      expect(find.text('RECONNECTING · 00:08'), findsOneWidget);
      expect(find.text('Connection lost.'), findsOneWidget);
      expect(
        find.text('Trying again. Your call is paused and nothing is lost.'),
        findsOneWidget,
      );
    });

    testWidgets('B10b the call ended, with the reason and two ways on', (
      tester,
    ) async {
      await check(
        tester,
        CallMode.error,
        [
          'CALL ENDED',
          'The call ended unexpectedly.',
          'Your conversation so far is saved in the chat. Start again whenever you’re ready.',
          'Call again',
          'Back to chat',
        ],
        failure: 'The call ended unexpectedly.',
        absent: ['END CALL'],
      );
    });

    testWidgets('B10b names the part that did not answer', (tester) async {
      await check(
        tester,
        CallMode.error,
        ["Iris can't reach speech-to-text on hermes.local"],
        failure: "Iris can't reach speech-to-text on hermes.local",
      );
    });

    testWidgets('D3a paused by a phone call', (tester) async {
      await check(tester, CallMode.paused, [
        'CALL PAUSED',
        'A phone call interrupted us.',
        'Resume',
        'End',
      ], paused: PauseReason.phoneCall);
    });

    testWidgets('D3b paused by unplugged headphones', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.call.value = rig.call.value.copyWith(
        route: const RouteInfo(speaker: false, headset: 'AirPods'),
      );
      await tester.pump();
      rig.call.value = rig.call.value.copyWith(
        route: const RouteInfo(speaker: false),
        mode: CallMode.paused,
        paused: PauseReason.unplugged,
      );
      await tester.pump();
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Headphones unplugged.'), findsOneWidget);
      expect(find.text('Route was AirPods'), findsOneWidget);
      expect(find.text('Resume on speaker'), findsOneWidget);
      expect(find.text('End call'), findsOneWidget);
    });
  });

  group('the header', () {
    testWidgets('names the server for a chained call', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      expect(find.text('VOICE · HERMES.LOCAL'), findsOneWidget);
      expect(find.text('Hands-free'), findsOneWidget);
    });

    testWidgets('names GPT-Live and OpenAI for a GPT-Live call', (
      tester,
    ) async {
      final rig = _Rig(engine: VoiceEngine.gptLive);
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      expect(find.text('VOICE · GPT-LIVE · OPENAI'), findsOneWidget);
    });

    testWidgets('shows the call clock', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.listening, elapsed: const Duration(seconds: 14));
      await tester.pump();
      expect(find.text('00:14'), findsOneWidget);
    });
  });

  group('push to talk (B2b)', () {
    testWidgets('a chip, a hold button and its own copy', (tester) async {
      final rig = _Rig(
        settings: const VoiceSettings(style: CallStyle.pushToTalk),
      );
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.listening);
      await tester.pump();
      expect(find.text('Push to talk'), findsOneWidget);
      expect(find.text('PUSH TO TALK'), findsOneWidget);
      expect(find.text('Hold the button to speak.'), findsOneWidget);
      expect(
        find.text('Let go when you’re done and Iris will answer.'),
        findsOneWidget,
      );
      expect(find.text('Hold to talk'), findsOneWidget);
    });

    testWidgets('holding the button opens the mic, letting go closes it', (
      tester,
    ) async {
      final rig = _Rig(
        settings: const VoiceSettings(style: CallStyle.pushToTalk),
      );
      addTearDown(rig.call.dispose);
      await rig.begin(tester);
      await _pumpScreen(tester, rig);
      expect(rig.mic.open, isFalse);

      final hold = await tester.startGesture(
        tester.getCenter(find.text('Hold to talk')),
      );
      await _nap(tester);
      await tester.pump();
      expect(rig.mic.open, isTrue);
      expect(rig.call.value.mode, CallMode.hearing);

      await hold.up();
      await _nap(tester);
      await tester.pump();
      expect(rig.call.value.mode, isNot(CallMode.hearing));
    });

    testWidgets('hands-free has no hold button', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.listening);
      await tester.pump();
      expect(find.text('Hold to talk'), findsNothing);
    });
  });

  group('the controls', () {
    testWidgets('mute, captions, route and end are all there', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.listening);
      await tester.pump();
      for (final label in ['MUTE', 'CAPTIONS', 'SPEAKER', 'END CALL']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('End'), findsOneWidget);
    });

    testWidgets('mute turns solid and reads Unmute', (tester) async {
      final rig = _Rig();
      addTearDown(rig.call.dispose);
      await rig.begin(tester);
      await _pumpScreen(tester, rig);
      await tester.tap(find.byKey(const ValueKey('call-mute')));
      await _nap(tester);
      await tester.pump();
      expect(rig.call.value.muted, isTrue);
      expect(find.text('UNMUTE'), findsOneWidget);
      expect(
        find.text('Iris can’t hear you. Replies still play.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('call-mute')));
      await _nap(tester);
      await tester.pump();
      expect(rig.call.value.muted, isFalse);
      expect(find.text('MUTE'), findsOneWidget);
    });

    testWidgets('captions toggles the call', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      expect(rig.call.value.captions, isFalse);
      await tester.tap(find.byKey(const ValueKey('call-captions')));
      await tester.pump();
      expect(rig.call.value.captions, isTrue);
    });

    testWidgets('the route control cycles speaker and earpiece', (
      tester,
    ) async {
      final rig = _Rig();
      addTearDown(rig.call.dispose);
      await rig.begin(tester);
      await _pumpScreen(tester, rig);
      expect(find.text('SPEAKER'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('call-route')));
      await _nap(tester);
      await tester.pump();
      expect(rig.route.speaker, isFalse);
      expect(find.text('EARPIECE'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('call-route')));
      await _nap(tester);
      await tester.pump();
      expect(rig.route.speaker, isTrue);
      expect(find.text('SPEAKER'), findsOneWidget);
    });

    testWidgets('a headset names the route, uppercased', (tester) async {
      final rig = _Rig();
      addTearDown(rig.call.dispose);
      await rig.begin(tester);
      await _pumpScreen(tester, rig);
      rig.route.plugIn('AirPods');
      await _nap(tester);
      await tester.pump();
      expect(find.text('AIRPODS'), findsOneWidget);
    });

    testWidgets('reconnecting dims mute and captions', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.reconnecting);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('call-captions')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(rig.call.value.captions, isFalse);
    });

    testWidgets('Resume on speaker moves to the speaker and resumes', (
      tester,
    ) async {
      final rig = _Rig();
      addTearDown(rig.call.dispose);
      await rig.begin(tester);
      await _pumpScreen(tester, rig);
      await tester.runAsync(() => rig.call.pause(PauseReason.unplugged));
      await tester.pump();
      expect(rig.call.value.mode, CallMode.paused);

      rig.route.speaker = false;
      await tester.tap(find.text('Resume on speaker'));
      await _nap(tester);
      await tester.pump();
      expect(rig.route.speaker, isTrue);
      expect(rig.call.value.mode, CallMode.listening);
    });
  });

  group('layout', () {
    Future<void> small(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the orb is 168 on 320 pt', (tester) async {
      await small(tester);
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(
        _screen(
          rig,
          media: const MediaQueryData(
            size: Size(320, 568),
            disableAnimations: true,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(IrisVoiceOrb).first),
        const Size(168, 168),
      );
    });

    testWidgets('the orb is 232 on a normal phone', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      expect(
        tester.getSize(find.byType(IrisVoiceOrb).first),
        const Size(232, 232),
      );
    });

    testWidgets('the call controls are at least 56 points', (tester) async {
      await small(tester);
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await tester.pumpWidget(
        _screen(
          rig,
          media: const MediaQueryData(
            size: Size(320, 568),
            disableAnimations: true,
          ),
        ),
      );
      await tester.pump();
      for (final key in ['mute', 'captions', 'route', 'end']) {
        expect(
          tester.getSize(find.byKey(ValueKey('call-$key'))).height,
          greaterThanOrEqualTo(56),
          reason: key,
        );
      }
      expect(tester.getSize(find.byKey(const ValueKey('call-mute'))).width, 56);
    });

    for (final mode in [
      CallMode.connecting,
      CallMode.listening,
      CallMode.tool,
      CallMode.interrupted,
      CallMode.error,
      CallMode.paused,
    ]) {
      testWidgets('200% text does not overflow in ${mode.name}', (
        tester,
      ) async {
        await small(tester);
        final rig = _Rig();
        addTearDown(() => rig.call.dispose());
        await tester.pumpWidget(
          _screen(
            rig,
            media: const MediaQueryData(
              size: Size(320, 568),
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
          ),
        );
        rig.show(
          mode,
          tool: 'web.search · flutter riverpod 3 migration guide',
          trail: [
            'web.fetch · riverpod.dev/docs/3.0',
            'web.search · riverpod 3',
          ],
          workingFor: const Duration(minutes: 2),
          failure: "Iris can't reach speech-to-text on a very long server name",
          paused: mode == CallMode.paused ? PauseReason.phoneCall : null,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduced motion leaves no ticker running', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      rig.show(CallMode.speaking);
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('the screen and the call', () {
    testWidgets('keeps the screen awake while visible', (tester) async {
      final rig = _Rig();
      addTearDown(() => rig.call.dispose());
      await _pumpScreen(tester, rig);
      expect(rig.awake.held, isTrue);
      await tester.pumpWidget(themed(const SizedBox()));
      await tester.pump();
      expect(rig.awake.held, isFalse);
    });

    testWidgets('leaving the screen ends the call', (tester) async {
      final rig = _Rig();
      await rig.begin(tester);
      await _pumpScreen(tester, rig);
      expect(rig.service.running, isTrue);
      await tester.pumpWidget(themed(const SizedBox()));
      await _nap(tester);
      await tester.pump();
      expect(rig.call.value.isOver, isTrue);
      expect(rig.service.running, isFalse);
      expect(rig.mic.open, isFalse);
    });

    testWidgets('the system back button ends the call and leaves', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.begin(tester);
      VoiceCallExit? exit;
      await tester.pumpWidget(_opener(rig, (e) => exit = e));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(VoiceCallScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(find.byType(VoiceCallScreen), findsNothing);
      expect(exit, VoiceCallExit.done);
      expect(rig.call.value.isOver, isTrue);
    });

    testWidgets('End hangs up and returns done', (tester) async {
      final rig = _Rig();
      await rig.begin(tester);
      VoiceCallExit? exit;
      await tester.pumpWidget(_opener(rig, (e) => exit = e));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('call-end')));
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(exit, VoiceCallExit.done);
      expect(rig.call.value.isOver, isTrue);
    });

    testWidgets('Call again returns again, Back to chat returns done', (
      tester,
    ) async {
      for (final (label, expected) in [
        ('Call again', VoiceCallExit.again),
        ('Back to chat', VoiceCallExit.done),
      ]) {
        final rig = _Rig();
        VoiceCallExit? exit;
        await tester.pumpWidget(_opener(rig, (e) => exit = e));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        rig.show(CallMode.error, failure: 'The call ended unexpectedly.');
        await tester.pump();
        await tester.tap(find.text(label));
        await _nap(tester);
        await tester.pumpAndSettle();
        expect(exit, expected, reason: label);
      }
    });
  });

  group('from the chat', () {
    late FakeChatBackend backend;
    late FakeVoiceBackend voice;
    late FakeMic mic;
    late FakeAudioRoute route;
    late FakeCallService service;
    late FakeScreenAwake awake;
    late List<(String, VoiceCallSpan)> ended;

    setUp(() {
      backend = FakeChatBackend();
      voice = FakeVoiceBackend()..sockets.add(FakeAudioSocket.speaking());
      mic = FakeMic();
      route = FakeAudioRoute();
      service = FakeCallService();
      awake = FakeScreenAwake();
      ended = [];
    });

    VoiceHost host() => VoiceHost(
      backend: voice,
      capabilities: const VoiceCapabilities(
        dictation: true,
        voiceMode: true,
        engine: VoiceEngine.chained,
        tuning: VoiceTuning(thinkingSound: false),
      ),
      spans: const [],
      onCallEnded: (id, span) => ended.add((id, span)),
      server: 'hermes.local',
      parts: (_) => CallParts(
        mic: mic,
        out: FakeAudioOut(),
        route: route,
        service: service,
        awake: awake,
      ),
    );

    Future<void> openChat(WidgetTester tester) async {
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatScreen(
                    backend: backend,
                    conversationId: 'stored-1',
                    voice: host(),
                  ),
                ),
              ),
              child: const Text('open chat'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open chat'));
      await tester.pumpAndSettle();
    }

    testWidgets('the voice button opens the call, End returns with a span', (
      tester,
    ) async {
      await openChat(tester);
      await tester.tap(find.byKey(const ValueKey('voice')));
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(find.byType(VoiceCallScreen), findsOneWidget);
      expect(service.running, isTrue);
      expect(awake.held, isTrue);

      await tester.tap(find.byKey(const ValueKey('call-end')));
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(find.byType(VoiceCallScreen), findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(service.running, isFalse);
      expect(awake.held, isFalse);
      expect(ended, hasLength(1));
      expect(ended.single.$1, 'stored-1');
      expect(ended.single.$2.fromIndex, greaterThanOrEqualTo(0));
    });

    testWidgets('popping the chat ends the call', (tester) async {
      await openChat(tester);
      await tester.tap(find.byKey(const ValueKey('voice')));
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(service.running, isTrue);

      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(service.running, isFalse);
      expect(mic.open, isFalse);
      expect(route.active, isFalse);
    });

    testWidgets('a failed check shows the ended screen and no service starts', (
      tester,
    ) async {
      voice.transcribeResult = const Err(IrisFailure.offline());
      await openChat(tester);
      await tester.tap(find.byKey(const ValueKey('voice')));
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(find.text('CALL ENDED'), findsOneWidget);
      expect(
        find.text("Iris can't reach speech-to-text on hermes.local"),
        findsOneWidget,
      );
      expect(service.starts, isEmpty);
      await tester.tap(find.text('Back to chat'));
      await _nap(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(ended, isEmpty);
    });
  });
}
