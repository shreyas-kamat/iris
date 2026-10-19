/// What a chat needs from the app to offer voice, handed to it whole so the
/// chat itself never reads a provider.
library;

import '../../app/device_state.dart';
import '../../app/voice_providers.dart';
import '../../data/voice/voice_backend.dart';
import '../../data/voice/voice_capabilities.dart';
import 'audio/audio_out.dart';
import 'audio/audio_route.dart';
import 'audio/mic_capture.dart';
import 'call_service.dart';
import 'live_channel.dart';
import 'preflight.dart';
import 'screen_awake.dart';

/// The platform seams one call runs on: the microphone, playback, the audio
/// session, the foreground service and the screen lock.
final class CallParts {
  const CallParts({
    required this.mic,
    required this.out,
    required this.route,
    required this.awake,
    this.service,
    this.livePeer,
  });

  /// The real ones. The route and playback share the speaker choice, because
  /// the iOS player resets the category when it sets up.
  factory CallParts.platform(VoiceSettings settings) {
    final route = PlatformAudioRoute(speaker: settings.speaker);
    return CallParts(
      mic: RecordMicCapture(),
      out: PlatformAudioOut(afterSetup: route.reapply),
      route: route,
      service: ForegroundCallService(),
      awake: const WakelockScreenAwake(),
    );
  }

  final MicCapture mic;
  final AudioOut out;
  final AudioRoute route;
  final ScreenAwake awake;
  final CallService? service;
  final LivePeer Function()? livePeer;
}

final class VoiceHost {
  const VoiceHost({
    required this.backend,
    required this.capabilities,
    required this.spans,
    required this.onCallEnded,
    this.settings = const VoiceSettings(),
    this.server = defaultServerName,
    this.parts = CallParts.platform,
  });

  final VoiceBackend backend;

  /// What this server and profile can do by voice. A host is only made once
  /// this has been read, so the voice button is never offered and then fails.
  final VoiceCapabilities capabilities;

  /// The voice calls already made in this conversation, oldest first.
  final List<VoiceCallSpan> spans;

  /// Records a finished call against the conversation's stored id.
  final void Function(String storedId, VoiceCallSpan span) onCallEnded;

  /// How this device likes calls.
  final VoiceSettings settings;

  /// The server's name, for the call's header and its failure copy.
  final String server;

  /// Builds the platform seams for one call. Tests pass fakes.
  final CallParts Function(VoiceSettings settings) parts;
}
