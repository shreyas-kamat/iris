/// What the active server can do by voice, and how this device likes calls.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs/preferences_store.dart';
import '../data/voice/voice_backend.dart';
import '../data/voice/voice_capabilities.dart';
import '../demo/demo_mode.dart';
import 'preferences.dart';
import 'providers.dart';

/// The voice backend for the active server, scoped to the active profile.
/// Null until the link exists. Demo mode has none until its scripted call
/// lands.
final activeVoiceProvider = FutureProvider<VoiceBackend?>((ref) async {
  final profile = ref.watch(activeProfileProvider);
  if (ref.watch(demoModeProvider)) return null;
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  return DashboardVoice(session, profile: profile);
});

/// What the active server and profile can do by voice. [VoiceCapabilities.none]
/// when there is no backend or the read failed, so nothing is offered that
/// might then fail. Invalidate it to read again (Settings opening, a call
/// about to start).
final voiceCapabilitiesProvider = FutureProvider<VoiceCapabilities>((
  ref,
) async {
  final backend = await ref.watch(activeVoiceProvider.future);
  if (backend == null) return VoiceCapabilities.none;
  return (await backend.capabilities()).or(VoiceCapabilities.none);
});

/// How a call listens.
enum CallStyle { handsFree, pushToTalk }

/// This device's call preferences. They follow the person, not the server.
@immutable
final class VoiceSettings {
  const VoiceSettings({
    this.style = CallStyle.handsFree,
    this.speaker = true,
    this.captions = false,
  });

  final CallStyle style;

  /// Calls start on the loudspeaker rather than the earpiece.
  final bool speaker;

  /// Live captions are on.
  final bool captions;

  VoiceSettings copyWith({CallStyle? style, bool? speaker, bool? captions}) =>
      VoiceSettings(
        style: style ?? this.style,
        speaker: speaker ?? this.speaker,
        captions: captions ?? this.captions,
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      other.style == style &&
      other.speaker == speaker &&
      other.captions == captions;

  @override
  int get hashCode => Object.hash(style, speaker, captions);
}

final voiceSettingsProvider =
    NotifierProvider<VoiceSettingsController, VoiceSettings>(
      VoiceSettingsController.new,
    );

class VoiceSettingsController extends Notifier<VoiceSettings> {
  @override
  VoiceSettings build() {
    String? at(String key) => ref.read(preferencesProvider)[('', key)];
    return VoiceSettings(
      style:
          CallStyle.values.asNameMap()[at(PreferenceKeys.voiceStyle)] ??
          CallStyle.handsFree,
      speaker: at(PreferenceKeys.voiceSpeaker) != 'false',
      captions: at(PreferenceKeys.voiceCaptions) == 'true',
    );
  }

  void setStyle(CallStyle style) {
    state = state.copyWith(style: style);
    _save(PreferenceKeys.voiceStyle, style.name);
  }

  void setSpeaker({required bool speaker}) {
    state = state.copyWith(speaker: speaker);
    _save(PreferenceKeys.voiceSpeaker, '$speaker');
  }

  void setCaptions({required bool captions}) {
    state = state.copyWith(captions: captions);
    _save(PreferenceKeys.voiceCaptions, '$captions');
  }

  void _save(String key, String value) =>
      ref.read(preferencesProvider.notifier).set('', key, value);
}
