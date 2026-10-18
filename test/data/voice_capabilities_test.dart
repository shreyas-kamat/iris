/// What the server's config and GPT-Live status say Iris may offer.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/data/voice/voice_catalog.dart';

Json j(Object? value) => Json.of(value);

void main() {
  group('capabilities', () {
    test('defaults', () {
      final caps = VoiceCapabilities.fromServer(config: j({}));
      expect(caps.dictation, isTrue);
      expect(caps.voiceMode, isTrue);
      expect(caps.engine, VoiceEngine.chained);
      expect(caps.tuning, equals(const VoiceTuning()));
    });

    test('stt disabled hides both', () {
      final caps = VoiceCapabilities.fromServer(
        config: j({
          'stt': {'enabled': false},
        }),
      );
      expect(caps.dictation, isFalse);
      expect(caps.voiceMode, isFalse);
    });

    test('the probed server', () {
      final caps = VoiceCapabilities.fromServer(
        config: j({
          'stt': {
            'enabled': true,
            'provider': 'openai',
            'streaming': false,
            'language': 'en',
          },
          'tts': {
            'provider': 'edge',
            'edge': {'voice': 'en-US-AriaNeural'},
          },
          'voice': {
            'voice_chat_mode': 'chained',
            'max_recording_seconds': 120,
            'silence_threshold': 200,
            'silence_duration': 3.0,
            'barge_in': true,
            'barge_in_grace_seconds': 0.5,
            'barge_in_threshold_multiplier': 3.0,
            'stop_phrases': ['stop'],
            'thinking_sound': true,
          },
        }),
        liveStatus: j({
          'ok': true,
          'mode': 'chained',
          'available': true,
          'reason': null,
          'model': 'gpt-live-1',
          'voice': 'marin',
        }),
      );
      expect(caps.engine, VoiceEngine.chained);
      expect(caps.liveTranscription, isFalse);
      expect(caps.ttsProvider, 'edge');
      expect(caps.voiceKey, 'tts.edge.voice');
      expect(caps.currentVoice, 'en-US-AriaNeural');
      expect(caps.voiceMode, isTrue);
      expect(caps.tuning, equals(const VoiceTuning()));
    });

    test('gpt-live with a key', () {
      final caps = VoiceCapabilities.fromServer(
        config: j({
          'voice': {'voice_chat_mode': 'gpt_live'},
        }),
        liveStatus: j({
          'mode': 'gpt-live',
          'available': true,
          'voice': 'marin',
        }),
      );
      expect(caps.engine, VoiceEngine.gptLive);
      expect(caps.voiceMode, isTrue);
      expect(caps.voiceKey, 'voice.gpt_live.voice');
      expect(caps.currentVoice, 'marin');
    });

    test('gpt-live without a key', () {
      final caps = VoiceCapabilities.fromServer(
        config: j({
          'voice': {'voice_chat_mode': 'gpt-live'},
        }),
        liveStatus: j({
          'mode': 'gpt-live',
          'available': false,
          'reason': 'no OpenAI API key is configured',
        }),
      );
      expect(caps.engine, VoiceEngine.gptLive);
      expect(caps.voiceMode, isFalse);
      expect(caps.dictation, isTrue);
      expect(caps.unavailableReason, contains('OpenAI'));
    });

    test('gpt-live with no status at all falls back to chained', () {
      final caps = VoiceCapabilities.fromServer(
        config: j({
          'voice': {'voice_chat_mode': 'gpt-live'},
        }),
      );
      expect(caps.engine, VoiceEngine.chained);
      expect(caps.voiceMode, isTrue);
    });

    test('mode names are normalised like Hermes does', () {
      for (final mode in ['GPT_LIVE', 'gptlive', 'live', ' Gpt-Live ']) {
        final caps = VoiceCapabilities.fromServer(
          config: j({
            'voice': {'voice_chat_mode': mode},
          }),
          liveStatus: j({'available': true}),
        );
        expect(caps.engine, VoiceEngine.gptLive, reason: mode);
      }
    });

    test('streaming stt turns on live transcription', () {
      final caps = VoiceCapabilities.fromServer(
        config: j({
          'stt': {'streaming': true},
        }),
      );
      expect(caps.liveTranscription, isTrue);
    });
  });

  group('tuning', () {
    test('tuning tolerates odd values', () {
      VoiceTuning t(Map<String, Object?> voice) =>
          VoiceTuning.fromConfig(j(voice));

      expect(t({'stop_phrases': []}).stopPhrases, isEmpty);
      expect(t({'stop_phrases': 'Stop now'}).stopPhrases, ['stop now']);
      expect(
        t({
          'stop_phrases': ['  Halt ', '', 'STOP'],
        }).stopPhrases,
        ['halt', 'stop'],
      );
      expect(t({}).stopPhrases, ['stop']);
      expect(
        t({'silence_duration': '2'}).silenceDuration,
        const Duration(seconds: 2),
      );
      expect(
        t({'silence_duration': 1.5}).silenceDuration,
        const Duration(milliseconds: 1500),
      );
      expect(
        t({'silence_duration': 0}).silenceDuration,
        const Duration(seconds: 3),
      );
      expect(t({'silence_threshold': -5}).silenceThreshold, 200);
      expect(t({'silence_threshold': '350'}).silenceThreshold, 350);
      expect(
        t({'max_recording_seconds': 0}).maxRecording,
        const Duration(seconds: 120),
      );
      expect(
        t({'max_recording_seconds': 45}).maxRecording,
        const Duration(seconds: 45),
      );
      expect(t({'barge_in': false}).bargeIn, isFalse);
      expect(t({'barge_in': 'false'}).bargeIn, isFalse);
      expect(t({'thinking_sound': false}).thinkingSound, isFalse);
      expect(t({'barge_in_grace_seconds': 0}).bargeInGrace, Duration.zero);
      expect(
        t({'barge_in_grace_seconds': 'x'}).bargeInGrace,
        const Duration(milliseconds: 500),
      );
      expect(t({'barge_in_threshold_multiplier': -1}).bargeInMultiplier, 3.0);
      expect(t({'barge_in_threshold_multiplier': 2}).bargeInMultiplier, 2.0);
    });

    test('a voice block that is not an object is the defaults', () {
      expect(VoiceTuning.fromConfig(j('nope')), equals(const VoiceTuning()));
    });
  });

  group('catalogue', () {
    test('catalogue', () {
      final openai = builtInVoices(VoiceEngine.chained, 'openai');
      expect(openai, hasLength(13));
      expect(openai.first.id, 'alloy');
      expect(openai.first.label, 'Alloy');

      final live = builtInVoices(VoiceEngine.gptLive, 'edge');
      expect(live, hasLength(14));
      expect(live.first.id, 'marin');

      final edge = builtInVoices(VoiceEngine.chained, 'edge');
      expect(edge.map((v) => v.id), [
        'en-US-AriaNeural',
        'en-US-JennyNeural',
        'en-US-AndrewNeural',
        'en-US-BrianNeural',
        'en-GB-SoniaNeural',
      ]);
      expect(edge.map((v) => v.label), [
        'Aria',
        'Jenny',
        'Andrew',
        'Brian',
        'Sonia',
      ]);

      expect(builtInVoices(VoiceEngine.chained, 'piper'), isEmpty);
    });

    test('config keys', () {
      expect(voiceConfigKey(VoiceEngine.chained, 'xai'), 'tts.xai.voice_id');
      expect(
        voiceConfigKey(VoiceEngine.chained, 'elevenlabs'),
        'tts.elevenlabs.voice_id',
      );
      expect(
        voiceConfigKey(VoiceEngine.chained, 'mistral'),
        'tts.mistral.voice_id',
      );
      expect(
        voiceConfigKey(VoiceEngine.chained, 'minimax'),
        'tts.minimax.voice_id',
      );
      expect(voiceConfigKey(VoiceEngine.chained, 'edge'), 'tts.edge.voice');
      expect(voiceConfigKey(VoiceEngine.chained, 'openai'), 'tts.openai.voice');
      expect(
        voiceConfigKey(VoiceEngine.gptLive, 'edge'),
        'voice.gpt_live.voice',
      );
      expect(voiceConfigKey(VoiceEngine.chained, ''), isNull);
    });
  });
}
