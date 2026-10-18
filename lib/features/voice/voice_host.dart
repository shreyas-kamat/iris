/// What a chat needs from the app to offer voice, handed to it whole so the
/// chat itself never reads a provider.
library;

import '../../app/device_state.dart';
import '../../data/voice/voice_backend.dart';
import '../../data/voice/voice_capabilities.dart';

final class VoiceHost {
  const VoiceHost({
    required this.backend,
    required this.capabilities,
    required this.spans,
    required this.onCallEnded,
  });

  final VoiceBackend backend;

  /// What this server and profile can do by voice. A host is only made once
  /// this has been read, so the voice button is never offered and then fails.
  final VoiceCapabilities capabilities;

  /// The voice calls already made in this conversation, oldest first.
  final List<VoiceCallSpan> spans;

  /// Records a finished call against the conversation's stored id.
  final void Function(String storedId, VoiceCallSpan span) onCallEnded;
}
