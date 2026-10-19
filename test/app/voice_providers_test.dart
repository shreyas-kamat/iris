/// Voice capability, the device's voice settings and call spans.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/voice_providers.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/demo/demo_mode.dart';
import 'package:iris/demo/demo_voice.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

void main() {
  late FakeHttp http;
  late MemoryPreferencesStore store;
  late ProviderContainer container;
  late ServerConnection connection;
  late DashboardSession session;

  ProviderContainer makeContainer({
    Map<PreferenceKey, String> initial = const {},
    List<Override> extra = const [],
    bool linked = true,
  }) {
    final made = ProviderContainer(
      overrides: [
        preferencesStoreProvider.overrideWithValue(store),
        initialPreferencesProvider.overrideWithValue(initial),
        activeSessionProvider.overrideWith(
          (ref) async => linked ? session : null,
        ),
        ...extra,
      ],
    );
    addTearDown(made.dispose);
    made.read(activeServerIdProvider.notifier).select('srv');
    return made;
  }

  setUp(() {
    http = FakeHttp()
      ..on('GET', '/api/config', (_) => FakeReply.json({}))
      ..on(
        'GET',
        '/api/audio/voice-live/status',
        (_) => FakeReply.json({'mode': 'chained', 'available': true}),
      );
    connection = ServerConnection.create(
      const ServerConfig(id: 'srv', baseUrl: 'https://h.example', label: 'H'),
      adapter: http,
    );
    session = DashboardSession(
      http: connection,
      connector: (uri, headers) async => FakeWireSocket(),
    );
    store = MemoryPreferencesStore();
    container = makeContainer();
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
  });

  group('capabilities', () {
    test('capabilities follow the profile', () async {
      // A paused provider never completes in a container test: listen first.
      final sub = container.listen(voiceCapabilitiesProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await container.read(voiceCapabilitiesProvider.future);
      expect(first.voiceMode, isTrue);
      expect(http.to('/api/config').last.uri.queryParameters, {
        'profile': 'default',
      });

      container.read(activeProfileProvider.notifier).select('work');
      await container.read(voiceCapabilitiesProvider.future);

      expect(http.to('/api/config').last.uri.queryParameters, {
        'profile': 'work',
      });
      expect(http.to('/api/audio/voice-live/status').last.uri.queryParameters, {
        'profile': 'work',
      });
    });

    test('a failed read is none', () async {
      http.on(
        'GET',
        '/api/config',
        (_) => FakeReply.json({'detail': 'down'}, status: 500),
      );
      final sub = container.listen(voiceCapabilitiesProvider, (_, _) {});
      addTearDown(sub.close);

      final caps = await container.read(voiceCapabilitiesProvider.future);

      expect(caps, VoiceCapabilities.none);
    });

    test('no live link is none', () async {
      final bare = makeContainer(linked: false);
      final sub = bare.listen(voiceCapabilitiesProvider, (_, _) {});
      addTearDown(sub.close);

      expect(
        await bare.read(voiceCapabilitiesProvider.future),
        VoiceCapabilities.none,
      );
      expect(http.requests, isEmpty);
    });

    test(
      'demo mode has a scripted voice backend that reaches no server',
      () async {
        final demo = makeContainer(
          extra: [demoModeProvider.overrideWithValue(true)],
        );
        final sub = demo.listen(activeVoiceProvider, (_, _) {});
        addTearDown(sub.close);

        final backend = await demo.read(activeVoiceProvider.future);
        expect(backend, isA<DemoVoiceBackend>());
        final caps = await demo.read(voiceCapabilitiesProvider.future);
        expect(caps.voiceMode, isTrue);
        expect(caps.engine, VoiceEngine.chained);
      },
    );
  });

  group('settings', () {
    test('defaults', () {
      expect(container.read(voiceSettingsProvider), const VoiceSettings());
      expect(const VoiceSettings().style, CallStyle.handsFree);
      expect(const VoiceSettings().speaker, isTrue);
      expect(const VoiceSettings().captions, isFalse);
    });

    test('settings persist', () {
      container.read(voiceSettingsProvider.notifier)
        ..setStyle(CallStyle.pushToTalk)
        ..setSpeaker(speaker: false)
        ..setCaptions(captions: true);

      expect(
        container.read(voiceSettingsProvider),
        const VoiceSettings(
          style: CallStyle.pushToTalk,
          speaker: false,
          captions: true,
        ),
      );
      expect(store.values[('', 'voice.style')], 'pushToTalk');
      expect(store.values[('', 'voice.speaker')], 'false');
      expect(store.values[('', 'voice.captions')], 'true');
    });

    test('saved settings load, and a damaged value is the default', () {
      final loaded = makeContainer(
        initial: {
          ('', 'voice.style'): 'pushToTalk',
          ('', 'voice.speaker'): 'false',
          ('', 'voice.captions'): 'true',
        },
      );
      expect(
        loaded.read(voiceSettingsProvider),
        const VoiceSettings(
          style: CallStyle.pushToTalk,
          speaker: false,
          captions: true,
        ),
      );

      final damaged = makeContainer(
        initial: {('', 'voice.style'): 'bogus', ('', 'voice.speaker'): '???'},
      );
      expect(damaged.read(voiceSettingsProvider), const VoiceSettings());
    });

    test('settings are app-wide, not per server', () {
      container
          .read(voiceSettingsProvider.notifier)
          .setStyle(CallStyle.pushToTalk);
      container.read(activeServerIdProvider.notifier).select('other');
      expect(container.read(voiceSettingsProvider).style, CallStyle.pushToTalk);
    });
  });

  group('call spans', () {
    VoiceCallSpan span(int n) => VoiceCallSpan(
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000 * n),
      endedAt: DateTime.fromMillisecondsSinceEpoch(1000 * n + 500),
      fromIndex: n,
    );

    test('spans round-trip and cap at 20', () {
      final writer = container.read(voiceCallSpansWriterProvider);
      for (var n = 1; n <= 25; n++) {
        writer.add('conv', span(n));
      }

      final spans = container.read(voiceCallSpansProvider('conv'));
      expect(spans, hasLength(20));
      expect(spans.first.fromIndex, 6);
      expect(spans.last.fromIndex, 25);
      expect(spans.last, span(25));
      expect(container.read(voiceCallSpansProvider('other')), isEmpty);
      expect(
        store.values[('srv/default', 'voiceCalls.conv')],
        startsWith('[{"s":'),
      );
    });

    test('spans follow the profile', () {
      container.read(voiceCallSpansWriterProvider).add('conv', span(1));
      container.read(activeProfileProvider.notifier).select('work');
      expect(container.read(voiceCallSpansProvider('conv')), isEmpty);
      container.read(activeProfileProvider.notifier).select('default');
      expect(container.read(voiceCallSpansProvider('conv')), hasLength(1));
    });

    test('a damaged span value is empty', () {
      expect(VoiceCallSpan.decodeList(null), isEmpty);
      expect(VoiceCallSpan.decodeList(''), isEmpty);
      expect(VoiceCallSpan.decodeList('not json'), isEmpty);
      expect(VoiceCallSpan.decodeList('{"s":1}'), isEmpty);
      expect(
        VoiceCallSpan.decodeList(
          '[{"s":1000,"e":2000,"i":3},"junk",{"s":"x"},{"s":5,"e":4,"i":1},'
          '{"s":1,"e":2,"i":-1}]',
        ),
        [
          VoiceCallSpan(
            startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
            endedAt: DateTime.fromMillisecondsSinceEpoch(2000),
            fromIndex: 3,
          ),
        ],
      );
    });

    test('a damaged stored value does not stop the next call being saved', () {
      final damaged = makeContainer(
        initial: {('srv/default', 'voiceCalls.conv'): 'garbage'},
      );
      damaged.read(voiceCallSpansWriterProvider).add('conv', span(2));
      expect(damaged.read(voiceCallSpansProvider('conv')), [span(2)]);
    });
  });
}
