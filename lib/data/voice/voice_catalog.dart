/// The voices Iris can offer without asking the server, and where each one is
/// written in the server's config.
library;

import 'voice_capabilities.dart';

/// One voice in a picker: the id the server stores and a short label.
final class VoiceChoice {
  const VoiceChoice(this.id, this.label);

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is VoiceChoice && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'VoiceChoice($id, $label)';
}

const _openAiVoices = [
  'alloy',
  'ash',
  'ballad',
  'cedar',
  'coral',
  'echo',
  'fable',
  'marin',
  'nova',
  'onyx',
  'sage',
  'shimmer',
  'verse',
];

const _gptLiveVoices = [
  'marin',
  'cedar',
  'quartz',
  'ripple',
  'vesper',
  'willow',
  'stone',
  'gleam',
  'meridian',
  'bossa',
  'tempo',
  'beacon',
  'delta',
  'cinder',
];

const _edgeVoices = [
  'en-US-AriaNeural',
  'en-US-JennyNeural',
  'en-US-AndrewNeural',
  'en-US-BrianNeural',
  'en-GB-SoniaNeural',
];

/// The built-in voices for [engine] and, when chained, the text-to-speech
/// [ttsProvider]. Empty when Hermes offers no fixed list (the picker then
/// takes a typed id, or the Voice row is hidden).
List<VoiceChoice> builtInVoices(VoiceEngine engine, String ttsProvider) {
  if (engine == VoiceEngine.gptLive) {
    return [for (final id in _gptLiveVoices) VoiceChoice(id, _label(id))];
  }
  return switch (ttsProvider.trim().toLowerCase()) {
    'openai' => [for (final id in _openAiVoices) VoiceChoice(id, _label(id))],
    'edge' => [for (final id in _edgeVoices) VoiceChoice(id, _label(id))],
    _ => const [],
  };
}

/// The dotted config key that holds the voice, or null when the provider is
/// unknown.
String? voiceConfigKey(VoiceEngine engine, String ttsProvider) {
  if (engine == VoiceEngine.gptLive) return 'voice.gpt_live.voice';
  final provider = ttsProvider.trim().toLowerCase();
  if (provider.isEmpty) return null;
  const idProviders = {'elevenlabs', 'xai', 'mistral', 'minimax'};
  return 'tts.$provider.${idProviders.contains(provider) ? 'voice_id' : 'voice'}';
}

/// "marin" → "Marin"; "en-US-AriaNeural" → "Aria".
String voiceLabel(String id) => _label(id);

String _label(String id) {
  var name = id;
  final locale = RegExp('^[a-z]{2}-[A-Z]{2}-').firstMatch(name);
  if (locale != null) name = name.substring(locale.end);
  if (name.endsWith('Neural')) {
    name = name.substring(0, name.length - 'Neural'.length);
  }
  return name.isEmpty ? id : '${name[0].toUpperCase()}${name.substring(1)}';
}
