/// What a server's voice setup lets Iris offer, read from its config.
///
/// Parsing is as forgiving as Hermes Desktop's own: a hand-edited config can
/// hold a string where a number belongs, a bare string for a list, or a value
/// that makes no sense, and none of that may stop a call from starting.
library;

import 'package:flutter/foundation.dart';

import '../../core/json.dart';
import 'voice_catalog.dart';

enum VoiceEngine { chained, gptLive }

/// Server-side tuning for the call loop. The defaults are Hermes's.
@immutable
final class VoiceTuning {
  const VoiceTuning({
    this.silenceThreshold = 200,
    this.silenceDuration = const Duration(seconds: 3),
    this.maxRecording = const Duration(seconds: 120),
    this.bargeIn = true,
    this.bargeInGrace = const Duration(milliseconds: 500),
    this.bargeInMultiplier = 3.0,
    this.stopPhrases = const ['stop'],
    this.thinkingSound = true,
  });

  /// Reads the `voice` block of the config. Anything that is not a usable
  /// value takes its default.
  factory VoiceTuning.fromConfig(Json voice) {
    const defaults = VoiceTuning();
    if (!voice.isMap) return defaults;

    final threshold = voice['silence_threshold'].doubleOrNull;
    final duration = voice['silence_duration'].doubleOrNull;
    final longest = voice['max_recording_seconds'].doubleOrNull;
    final grace = voice['barge_in_grace_seconds'].doubleOrNull;
    final multiplier = voice['barge_in_threshold_multiplier'].doubleOrNull;

    return VoiceTuning(
      silenceThreshold: threshold != null && threshold > 0
          ? threshold.round()
          : defaults.silenceThreshold,
      silenceDuration: duration != null && duration > 0
          ? _seconds(duration)
          : defaults.silenceDuration,
      maxRecording: longest != null && longest >= 1
          ? _seconds(longest)
          : defaults.maxRecording,
      bargeIn: voice['barge_in'].boolOrNull ?? defaults.bargeIn,
      bargeInGrace: grace != null && grace >= 0
          ? _seconds(grace)
          : defaults.bargeInGrace,
      bargeInMultiplier: multiplier != null && multiplier > 0
          ? multiplier
          : defaults.bargeInMultiplier,
      stopPhrases: _phrases(voice['stop_phrases']) ?? defaults.stopPhrases,
      thinkingSound:
          voice['thinking_sound'].boolOrNull ?? defaults.thinkingSound,
    );
  }

  /// RMS of int16 samples below which the microphone is taken to be quiet.
  final int silenceThreshold;

  /// Quiet for this long ends the take.
  final Duration silenceDuration;

  /// A take is cut off at this length.
  final Duration maxRecording;

  final bool bargeIn;
  final Duration bargeInGrace;
  final double bargeInMultiplier;

  /// Lower-case phrases that end Iris's speech when heard. May be empty.
  final List<String> stopPhrases;
  final bool thinkingSound;

  static Duration _seconds(double value) =>
      Duration(milliseconds: (value * 1000).round());

  /// A list, or a bare string standing for one phrase. Null when absent, so
  /// the default applies; an explicit empty list stays empty.
  static List<String>? _phrases(Json value) {
    if (value.isList) {
      return [
        for (final item in value.list)
          if (item.stringOrNull?.trim().toLowerCase() case final phrase?)
            if (phrase.isNotEmpty) phrase,
      ];
    }
    final single = value.stringOrNull?.trim().toLowerCase();
    if (single == null) return null;
    return single.isEmpty ? const [] : [single];
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceTuning &&
      other.silenceThreshold == silenceThreshold &&
      other.silenceDuration == silenceDuration &&
      other.maxRecording == maxRecording &&
      other.bargeIn == bargeIn &&
      other.bargeInGrace == bargeInGrace &&
      other.bargeInMultiplier == bargeInMultiplier &&
      listEquals(other.stopPhrases, stopPhrases) &&
      other.thinkingSound == thinkingSound;

  @override
  int get hashCode => Object.hash(
    silenceThreshold,
    silenceDuration,
    maxRecording,
    bargeIn,
    bargeInGrace,
    bargeInMultiplier,
    Object.hashAll(stopPhrases),
    thinkingSound,
  );
}

/// What this server and profile can do by voice.
@immutable
final class VoiceCapabilities {
  const VoiceCapabilities({
    required this.dictation,
    required this.voiceMode,
    required this.engine,
    this.liveTranscription = false,
    this.ttsProvider = 'edge',
    this.voiceKey,
    this.currentVoice,
    this.unavailableReason,
    this.tuning = const VoiceTuning(),
  });

  /// Nothing: the server cannot be asked, or it has speech-to-text off.
  static const none = VoiceCapabilities(
    dictation: false,
    voiceMode: false,
    engine: VoiceEngine.chained,
  );

  /// [config] is `GET /api/config`; [liveStatus] is
  /// `GET /api/audio/voice-live/status`, or null when the server has no such
  /// route (an older Hermes), which means chained.
  factory VoiceCapabilities.fromServer({
    required Json config,
    Json? liveStatus,
  }) {
    final sttEnabled = config['stt']['enabled'].boolOrNull ?? true;
    final voice = config['voice'];

    final configured = _normaliseMode(voice['voice_chat_mode'].stringOrNull);
    final reported = liveStatus == null
        ? null
        : _normaliseMode(liveStatus['mode'].stringOrNull);
    final engine =
        liveStatus != null && (reported ?? configured) == VoiceEngine.gptLive
        ? VoiceEngine.gptLive
        : VoiceEngine.chained;

    final available = liveStatus?['available'].boolOrNull ?? true;
    final provider =
        config['tts']['provider'].stringOrNull?.trim().toLowerCase() ?? 'edge';
    final key = voiceConfigKey(engine, provider);

    String? current;
    if (engine == VoiceEngine.gptLive) {
      current =
          liveStatus?['voice'].stringOrNull ??
          voice['gpt_live']['voice'].stringOrNull;
    } else if (key != null) {
      var node = config;
      for (final part in key.split('.')) {
        node = node[part];
      }
      current = node.stringOrNull;
    }

    final gptLiveBlocked = engine == VoiceEngine.gptLive && !available;
    return VoiceCapabilities(
      dictation: sttEnabled,
      voiceMode: sttEnabled && !gptLiveBlocked,
      engine: engine,
      liveTranscription: config['stt']['streaming'].boolOrNull ?? false,
      ttsProvider: provider,
      voiceKey: key,
      currentVoice: current,
      unavailableReason: gptLiveBlocked
          ? (liveStatus?['reason'].stringOrNull?.trim().isNotEmpty ?? false)
                ? liveStatus!['reason'].string().trim()
                : 'GPT-Live needs an OpenAI API key on this server.'
          : null,
      tuning: VoiceTuning.fromConfig(voice),
    );
  }

  /// Dictation (the mic button) is offered.
  final bool dictation;

  /// A live call is offered.
  final bool voiceMode;
  final VoiceEngine engine;

  /// Your own words appear while you speak (`stt.streaming`).
  final bool liveTranscription;
  final String ttsProvider;

  /// The dotted config key the voice is stored under.
  final String? voiceKey;
  final String? currentVoice;

  /// Why a call is not offered when the engine is configured but cannot run.
  final String? unavailableReason;
  final VoiceTuning tuning;

  /// Hermes's `voice_chat_mode()`: lower-case, `_` as `-`, and a few aliases.
  static VoiceEngine? _normaliseMode(String? mode) {
    if (mode == null) return null;
    final name = mode.trim().toLowerCase().replaceAll('_', '-');
    return switch (name) {
      'gpt-live' || 'gptlive' || 'live' => VoiceEngine.gptLive,
      _ => VoiceEngine.chained,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceCapabilities &&
      other.dictation == dictation &&
      other.voiceMode == voiceMode &&
      other.engine == engine &&
      other.liveTranscription == liveTranscription &&
      other.ttsProvider == ttsProvider &&
      other.voiceKey == voiceKey &&
      other.currentVoice == currentVoice &&
      other.unavailableReason == unavailableReason &&
      other.tuning == tuning;

  @override
  int get hashCode => Object.hash(
    dictation,
    voiceMode,
    engine,
    liveTranscription,
    ttsProvider,
    voiceKey,
    currentVoice,
    unavailableReason,
    tuning,
  );
}
