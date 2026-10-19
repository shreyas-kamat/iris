/// The voice frames at phone size: the call screen in listening (B3), a tool
/// running (B6), an approval card (B9a), captions on (C1), and the Settings
/// voice section (E1a), each in both brightnesses; B3 and B6 again with
/// reduced motion.
///
/// Like the other goldens, these are reviewed by eye. Run with
/// `--update-goldens` on this file only, then open every PNG and check it
/// against the design. Animated frames run on the fake clock, so the same
/// code renders the same image on any day.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/chat_controller.dart';
import 'package:iris/features/settings/settings_screen.dart';
import 'package:iris/features/voice/voice_call.dart';
import 'package:iris/features/voice/voice_call_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';
import '../support/fonts.dart';

/// A phone's logical size. The goldens are captured at this size and no other.
const _phone = Size(390, 844);

/// The Settings frame needs more height to show the voice section.
const _tall = Size(390, 1600);

/// Frames a screen as the app frames it: the Iris theme above the navigator
/// and the phone's size. [animated] leaves motion on, for the frames that show
/// the orb moving; the reduced-motion frames turn it off.
Widget _framed(
  Widget screen, {
  required bool isDark,
  bool animated = false,
  Size size = _phone,
  List<Override> overrides = const [],
}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: isDark);
  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: !animated),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        builder: (context, navigator) => IrisTheme(
          data: theme,
          child: Material(type: MaterialType.transparency, child: navigator),
        ),
        home: screen,
      ),
    ),
  );
}

/// A call on a fake engine, with the state a frame needs set on it.
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
        voiceKey: 'tts.edge.voice',
        currentVoice: 'en-US-AriaNeural',
        tuning: VoiceTuning(thinkingSound: false),
      ),
      settings: const VoiceSettings(),
      mic: mic,
      out: out,
      route: route,
      server: 'Hermes Ops',
      service: service,
    );
  }

  final chatBackend = FakeChatBackend();
  final voice = FakeVoiceBackend();
  final mic = FakeMic();
  final out = FakeAudioOut();
  final route = FakeAudioRoute();
  final service = FakeCallService();
  final awake = FakeScreenAwake();
  late final ChatController chat;
  late final VoiceCall call;

  void set(VoiceCallState Function(VoiceCallState s) change) {
    call.value = change(call.value);
  }
}

/// The Settings overrides: the server, a live link, and a chained voice setup
/// with its voice, the same as the settings tests use.
List<Override> _settingsOverrides(FakeVoiceBackend voice) {
  voice.capabilitiesResult = const Ok(
    VoiceCapabilities(
      dictation: true,
      voiceMode: true,
      engine: VoiceEngine.chained,
      voiceKey: 'tts.edge.voice',
      currentVoice: 'en-US-AriaNeural',
    ),
  );
  return [
    preferencesStoreProvider.overrideWithValue(MemoryPreferencesStore()),
    initialPreferencesProvider.overrideWithValue(const {}),
    activeServerProvider.overrideWithValue(
      const ServerConfig(
        id: 's',
        baseUrl: 'https://hermes.example.com',
        label: 'Hermes Ops',
      ),
    ),
    activeLinkProvider.overrideWith(
      (ref) => Stream.value(const LinkState(LinkPhase.live)),
    ),
    activeVoiceProvider.overrideWith((ref) async => voice),
    conversationsProvider.overrideWith(
      (ref) async => const ConversationPage(items: [], total: 0),
    ),
    profilesProvider.overrideWith((ref) async => const []),
  ];
}

void main() {
  setUpAll(loadIrisFonts);

  /// Lets the frame lay out, then moves a fixed time on, so animated frames
  /// land on the same step every run.
  Future<void> settle(WidgetTester tester, {bool animated = false}) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    if (animated) await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> capture(
    WidgetTester tester, {
    required Widget screen,
    required String name,
    required bool isDark,
    bool animated = false,
    Size size = _phone,
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(size);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _framed(
        screen,
        isDark: isDark,
        animated: animated,
        size: size,
        overrides: overrides,
      ),
    );
    await settle(tester, animated: animated);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/voice_${name}_${isDark ? 'dark' : 'light'}.png',
      ),
    );
  }

  Widget callScreen(_Rig rig) =>
      VoiceCallScreen(call: rig.call, awake: rig.awake);

  for (final isDark in [true, false]) {
    testWidgets('B3 listening, ${isDark ? 'dark' : 'light'}', (tester) async {
      final rig = _Rig();
      rig.set(
        (s) => s.copyWith(mode: CallMode.listening, style: CallStyle.handsFree),
      );
      (rig.call.value.level as ValueNotifier<double>).value = 0.2;
      await capture(
        tester,
        screen: callScreen(rig),
        name: 'b3',
        isDark: isDark,
      );
    });

    testWidgets('B6 tool running, ${isDark ? 'dark' : 'light'}', (
      tester,
    ) async {
      final rig = _Rig();
      rig.set(
        (s) => s.copyWith(
          mode: CallMode.tool,
          tool: 'calendar · tomorrow',
          toolTrail: const ['notes · search'],
          workingFor: const Duration(seconds: 14),
        ),
      );
      await capture(
        tester,
        screen: callScreen(rig),
        name: 'b6',
        isDark: isDark,
      );
    });

    testWidgets('B9a approval card, ${isDark ? 'dark' : 'light'}', (
      tester,
    ) async {
      final rig = _Rig();
      rig.set(
        (s) => s.copyWith(
          mode: CallMode.needs,
          decision: const ApprovalDecision(
            ApprovalRequest(
              sessionId: 'demo',
              command: 'rm -rf build/cache',
              description: 'Delete the build cache',
              choices: ['once', 'deny'],
            ),
          ),
        ),
      );
      await capture(
        tester,
        screen: callScreen(rig),
        name: 'b9a',
        isDark: isDark,
      );
    });

    testWidgets('C1 captions on, ${isDark ? 'dark' : 'light'}', (tester) async {
      final rig = _Rig();
      rig.set(
        (s) => s.copyWith(
          mode: CallMode.speaking,
          captions: true,
          transcript: const [
            Caption(you: true, text: 'What is on my calendar tomorrow?'),
            Caption(
              you: false,
              text:
                  'Tomorrow you have a design review at ten, then lunch with Priya.',
              heard: 30,
            ),
          ],
        ),
      );
      await capture(
        tester,
        screen: callScreen(rig),
        name: 'c1',
        isDark: isDark,
        animated: true,
      );
    });

    testWidgets('E1a voice settings, ${isDark ? 'dark' : 'light'}', (
      tester,
    ) async {
      final voice = FakeVoiceBackend();
      await capture(
        tester,
        screen: const SettingsScreen(),
        name: 'e1a',
        isDark: isDark,
        size: _tall,
        overrides: _settingsOverrides(voice),
      );
    });
  }

  testWidgets('B3 listening with reduced motion, dark', (tester) async {
    final rig = _Rig();
    rig.set((s) => s.copyWith(mode: CallMode.listening));
    (rig.call.value.level as ValueNotifier<double>).value = 0.2;
    await capture(tester, screen: callScreen(rig), name: 'b3_rm', isDark: true);
  });

  testWidgets('B6 tool running with reduced motion, dark', (tester) async {
    final rig = _Rig();
    rig.set(
      (s) => s.copyWith(
        mode: CallMode.tool,
        tool: 'calendar · tomorrow',
        toolTrail: const ['notes · search'],
        workingFor: const Duration(seconds: 14),
      ),
    );
    await capture(tester, screen: callScreen(rig), name: 'b6_rm', isDark: true);
  });
}
