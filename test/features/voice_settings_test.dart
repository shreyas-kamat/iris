/// Voice settings (E1a, E1b): the device's call defaults and the server's
/// voice, with its picker.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/data/voice/voice_catalog.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/settings/settings_screen.dart';
import 'package:iris/features/settings/voice_settings_section.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_voice.dart';
import '../support/harness.dart';

const _edge = VoiceCapabilities(
  dictation: true,
  voiceMode: true,
  engine: VoiceEngine.chained,
  voiceKey: 'tts.edge.voice',
  currentVoice: 'en-US-AriaNeural',
);

void main() {
  late FakeChatBackend backend;
  late FakeVoiceBackend voice;
  late MemoryPreferencesStore store;

  setUp(() {
    backend = FakeChatBackend();
    voice = FakeVoiceBackend();
    store = MemoryPreferencesStore();
  });
  tearDown(() => backend.close());

  Widget settings([VoiceCapabilities caps = _edge, MediaQueryData? media]) {
    voice.capabilitiesResult = Ok(caps);
    return ProviderScope(
      overrides: [
        preferencesStoreProvider.overrideWithValue(store),
        initialPreferencesProvider.overrideWithValue(const {}),
        activeServerProvider.overrideWithValue(
          const ServerConfig(
            id: 's',
            baseUrl: 'https://hermes.local',
            label: 'Home',
          ),
        ),
        activeLinkProvider.overrideWith(
          (ref) => Stream.value(const LinkState(LinkPhase.live)),
        ),
        activeChatProvider.overrideWith((ref) async => backend),
        activeVoiceProvider.overrideWith((ref) async => voice),
        conversationsProvider.overrideWith(
          (ref) async => const ConversationPage(items: [], total: 0),
        ),
        profilesProvider.overrideWith((ref) async => const []),
      ],
      child: themed(
        media == null
            ? const SettingsScreen()
            : MediaQuery(data: media, child: const SettingsScreen()),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('the section', () {
    testWidgets('is left out when the server has no voice mode', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(settings(VoiceCapabilities.none));
      await settle(tester);
      expect(find.text('VOICE'), findsNothing);
      expect(find.text('Conversation'), findsNothing);
    });

    testWidgets('GPT-Live that cannot run shows only why', (tester) async {
      await tall(tester);
      await tester.pumpWidget(
        settings(
          const VoiceCapabilities(
            dictation: true,
            voiceMode: false,
            engine: VoiceEngine.gptLive,
            unavailableReason:
                'GPT-Live needs an OpenAI API key on this server.',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('VOICE'), findsOneWidget);
      expect(
        find.text('GPT-Live needs an OpenAI API key on this server.'),
        findsOneWidget,
      );
      expect(find.text('Conversation'), findsNothing);
      expect(find.text('Captions by default'), findsNothing);
    });

    testWidgets('shows the defaults, and the server it reads voices from', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(settings());
      await settle(tester);
      expect(find.text('VOICE'), findsOneWidget);
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.text('Default for new calls'), findsOneWidget);
      expect(find.text('Hands-free'), findsOneWidget);
      expect(find.text('Push to talk'), findsOneWidget);
      expect(find.text('Speaker by default'), findsOneWidget);
      expect(
        find.text('Otherwise earpiece, or your last route'),
        findsOneWidget,
      );
      expect(find.text('Captions by default'), findsOneWidget);
      expect(find.text('Show the live transcript on calls'), findsOneWidget);
      expect(find.text('Offered by hermes.local'), findsOneWidget);
      expect(
        find.text('Voices come from your server, so this list can change.'),
        findsOneWidget,
      );
    });

    testWidgets('conversation, speaker and captions persist', (tester) async {
      final semantics = tester.ensureSemantics();
      await tall(tester);
      await tester.pumpWidget(settings());
      await settle(tester);
      final container = containerOf(tester);
      expect(container.read(voiceSettingsProvider), const VoiceSettings());

      await tester.tap(find.text('Push to talk'));
      await settle(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IrisSwitch && w.semanticLabel == 'Speaker by default',
        ),
      );
      await settle(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IrisSwitch && w.semanticLabel == 'Captions by default',
        ),
      );
      await settle(tester);

      expect(
        container.read(voiceSettingsProvider),
        const VoiceSettings(
          style: CallStyle.pushToTalk,
          speaker: false,
          captions: true,
        ),
      );
      expect(store.values.values, containsAll(['pushToTalk', 'false', 'true']));
      semantics.dispose();
    });
  });

  group('the voice row', () {
    testWidgets('shows the current voice, and the picker lists five', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(settings());
      await settle(tester);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Aria'), findsOneWidget);

      await tester.tap(find.text('Voice'));
      await settle(tester);
      for (final name in ['Aria', 'Jenny', 'Andrew', 'Brian', 'Sonia']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Offered by hermes.local'), findsWidgets);
    });

    testWidgets('an unknown current voice is kept first and checked', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(
        settings(
          const VoiceCapabilities(
            dictation: true,
            voiceMode: true,
            engine: VoiceEngine.chained,
            voiceKey: 'tts.edge.voice',
            currentVoice: 'en-AU-NatashaNeural',
          ),
        ),
      );
      await settle(tester);
      // The row shows it verbatim.
      expect(find.text('en-AU-NatashaNeural'), findsOneWidget);

      await tester.tap(find.text('Voice'));
      await settle(tester);
      expect(find.text('en-AU-NatashaNeural'), findsWidgets);
      expect(find.byIcon(Icons.check), findsOneWidget);
      final natasha = tester
          .getTopLeft(find.text('en-AU-NatashaNeural').last)
          .dy;
      final aria = tester.getTopLeft(find.text('Aria').last).dy;
      expect(natasha, lessThan(aria));
    });

    testWidgets('choosing writes the server and reads it again', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(settings());
      await settle(tester);
      final reads = voice.calls.where((c) => c == 'capabilities').length;

      await tester.tap(find.text('Voice'));
      await settle(tester);
      await tester.tap(find.text('Jenny'));
      await settle(tester);
      expect(
        voice.calls,
        contains('setVoice tts.edge.voice=en-US-JennyNeural'),
      );
      expect(
        voice.calls.where((c) => c == 'capabilities').length,
        greaterThan(reads),
      );
    });

    testWidgets('a failed write keeps the old voice and says so', (
      tester,
    ) async {
      await tall(tester);
      voice.setVoiceResult = const Err(IrisFailure.offline());
      await tester.pumpWidget(settings());
      await settle(tester);
      await tester.tap(find.text('Voice'));
      await settle(tester);
      await tester.tap(find.text('Jenny'));
      await settle(tester);
      expect(find.textContaining("Couldn't change the voice:"), findsOneWidget);
      expect(find.text('Aria'), findsOneWidget);
      expect(find.text('Jenny'), findsNothing);

      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('ElevenLabs lists the voices the server offers', (
      tester,
    ) async {
      await tall(tester);
      voice.voicesResult = const Ok([
        VoiceChoice('abc123', 'Wren'),
        VoiceChoice('def456', 'Rowan'),
      ]);
      await tester.pumpWidget(
        settings(
          const VoiceCapabilities(
            dictation: true,
            voiceMode: true,
            engine: VoiceEngine.chained,
            ttsProvider: 'elevenlabs',
            voiceKey: 'tts.elevenlabs.voice_id',
            currentVoice: 'abc123',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Wren'), findsOneWidget);
      await tester.tap(find.text('Voice'));
      await settle(tester);
      expect(find.text('Rowan'), findsOneWidget);
      await tester.tap(find.text('Rowan'));
      await settle(tester);
      expect(voice.calls, contains('setVoice tts.elevenlabs.voice_id=def456'));
    });

    testWidgets('GPT-Live offers its own voices', (tester) async {
      await tall(tester);
      await tester.pumpWidget(
        settings(
          const VoiceCapabilities(
            dictation: true,
            voiceMode: true,
            engine: VoiceEngine.gptLive,
            voiceKey: 'voice.gpt_live.voice',
            currentVoice: 'marin',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Marin'), findsOneWidget);
      await tester.tap(find.text('Voice'));
      await settle(tester);
      await tester.tap(find.text('Cedar'));
      await settle(tester);
      expect(voice.calls, contains('setVoice voice.gpt_live.voice=cedar'));
    });

    testWidgets('no list, no row: a footnote says which voice calls use', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(
        settings(
          const VoiceCapabilities(
            dictation: true,
            voiceMode: true,
            engine: VoiceEngine.chained,
            ttsProvider: 'piper',
            voiceKey: 'tts.piper.voice',
            currentVoice: 'amy',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Voice'), findsNothing);
      expect(
        find.text('Calls use whichever voice your server speaks with.'),
        findsOneWidget,
      );
      expect(find.text('Conversation'), findsOneWidget);
    });
  });

  // The section alone: the rest of Settings has its own layout at 200%.
  testWidgets('200% text does not overflow in the voice section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    voice.capabilitiesResult = const Ok(_edge);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesStoreProvider.overrideWithValue(store),
          initialPreferencesProvider.overrideWithValue(const {}),
          activeServerProvider.overrideWithValue(
            const ServerConfig(
              id: 's',
              baseUrl: 'https://hermes.local',
              label: 'Home',
            ),
          ),
          activeVoiceProvider.overrideWith((ref) async => voice),
        ],
        child: themed(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 2600),
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: VoiceSettingsSection(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Conversation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
