/// Interrupting Iris by speaking over it.
library;

import 'dart:math' as math;

import '../../data/voice/voice_capabilities.dart';

/// One per spoken reply. [calibrate] with the microphone's RMS in the moments
/// before playback (the room's floor); then [feed] the RMS while Iris speaks,
/// with the time since playback began. After `bargeInGrace`, RMS above the
/// floor × `bargeInMultiplier` held for 200 ms trips it.
///
/// The bar never drops below `silenceThreshold`, so a silent room does not
/// make a breath an interruption. Uncalibrated, the floor is that threshold.
final class BargeInDetector {
  BargeInDetector(this._tuning);

  static const _held = Duration(milliseconds: 200);

  final VoiceTuning _tuning;
  double _floorSum = 0;
  int _floorCount = 0;
  Duration? _loudSince;

  void calibrate(double rms) {
    _floorSum += rms;
    _floorCount++;
  }

  double get _bar {
    final threshold = _tuning.silenceThreshold.toDouble();
    final floor = _floorCount == 0 ? threshold : _floorSum / _floorCount;
    return math.max(floor * _tuning.bargeInMultiplier, threshold);
  }

  /// True once the user has spoken over the reply.
  bool feed(double rms, Duration sincePlayback) {
    if (!_tuning.bargeIn || sincePlayback < _tuning.bargeInGrace) {
      _loudSince = null;
      return false;
    }
    if (rms <= _bar) {
      _loudSince = null;
      return false;
    }
    final since = _loudSince ??= sincePlayback;
    return sincePlayback - since >= _held;
  }
}
