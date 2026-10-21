/// A quiet bubble while the agent works, so a call in a pocket is audibly
/// alive. Made in code: there is no audio asset.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'audio/audio_out.dart';

const _on = Duration(milliseconds: 120);
const _period = Duration(milliseconds: 1020);

/// -30 dBFS.
const _peak = 1036.0;

/// One period: a soft 120 ms bubble of 220 Hz and 330 Hz, then 900 ms of
/// silence, as 16-bit little-endian mono at [sampleRate].
Uint8List thinkingBubble(int sampleRate) {
  final total = (sampleRate * _period.inMilliseconds / 1000).round();
  final on = (sampleRate * _on.inMilliseconds / 1000).round();
  final wave = List<double>.filled(on, 0);
  var loudest = 0.0;
  for (var i = 0; i < on; i++) {
    final t = i / sampleRate;
    // A raised-cosine envelope, so the bubble has no click at either end.
    final envelope = 0.5 - 0.5 * math.cos(2 * math.pi * i / (on - 1));
    final v =
        envelope *
        (math.sin(2 * math.pi * 220 * t) + math.sin(2 * math.pi * 330 * t));
    wave[i] = v;
    loudest = math.max(loudest, v.abs());
  }
  final data = ByteData(total * 2);
  final scale = loudest == 0 ? 0.0 : _peak / loudest;
  for (var i = 0; i < on; i++) {
    data.setInt16(i * 2, (wave[i] * scale).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Plays [thinkingBubble] on a loop through [AudioOut] until [stop].
final class ThinkingSound {
  ThinkingSound(this._out);

  final AudioOut _out;
  Timer? _timer;

  bool get playing => _timer != null;

  void start(int sampleRate) {
    if (_timer != null) return;
    final bubble = thinkingBubble(sampleRate);
    // One period is queued ahead, so the loop never runs dry.
    _timer = Timer.periodic(_period, (_) => _out.addPcm(bubble));
    unawaited(() async {
      await _out.startPcm(sampleRate);
      if (_timer != null) _out.addPcm(bubble);
    }());
  }

  /// Cuts the sound off at once.
  Future<void> stop() async {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    await _out.stop();
  }
}
