/// Hands-free turn taking: when a take starts and when it ends, from the
/// microphone's RMS and the server's voice tuning.
library;

import '../../data/voice/voice_capabilities.dart';

sealed class SpeechEvent {
  const SpeechEvent();
}

/// The user has been speaking long enough to count as a take.
final class SpeechStarted extends SpeechEvent {
  const SpeechStarted();
}

/// The take is over: quiet for the silence duration, or [capped] at the
/// longest recording the server allows.
final class SpeechEnded extends SpeechEvent {
  const SpeechEnded({required this.capped});
  final bool capped;
}

/// Feed it one RMS per microphone chunk, with the time since listening began
/// at the end of that chunk. A take starts with the first chunk above
/// `silenceThreshold` and ends once `silenceDuration` has passed since the
/// last loud chunk, or at `maxRecording`. A take shorter than 400 ms (a cough,
/// a door) produces no events at all.
final class SpeechDetector {
  SpeechDetector(this._tuning);

  static const _shortest = Duration(milliseconds: 400);

  final VoiceTuning _tuning;

  /// The end of the previous chunk, which is where the current one began.
  Duration _lastAt = Duration.zero;
  Duration? _takeStart;
  Duration? _lastLoud;
  bool _started = false;

  SpeechEvent? feed(double rms, Duration at) {
    final chunkStart = _lastAt;
    _lastAt = at;

    if (rms > _tuning.silenceThreshold) {
      _takeStart ??= chunkStart;
      _lastLoud = at;
    }
    final start = _takeStart;
    final lastLoud = _lastLoud;
    if (start == null || lastLoud == null) return null;

    if (at - start >= _tuning.maxRecording) {
      final wasStarted = _started;
      _endTake();
      return wasStarted ? const SpeechEnded(capped: true) : null;
    }
    if (at - lastLoud >= _tuning.silenceDuration) {
      final wasStarted = _started;
      _endTake();
      return wasStarted ? const SpeechEnded(capped: false) : null;
    }
    if (!_started && lastLoud == at && at - start >= _shortest) {
      _started = true;
      return const SpeechStarted();
    }
    return null;
  }

  /// Forgets any take in progress, e.g. when the mic closes for a turn.
  void reset() {
    _endTake();
    _lastAt = Duration.zero;
  }

  void _endTake() {
    _takeStart = null;
    _lastLoud = null;
    _started = false;
  }
}
