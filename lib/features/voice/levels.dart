/// Loudness of raw microphone and playback audio, in the units the server's
/// voice tuning uses.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const _fullScale = 32767.0;

/// Root mean square of 16-bit little-endian mono samples, in int16 units
/// (0 for silence, about 32767 at full scale): Hermes's
/// `voice.silence_threshold` is in these units. An odd trailing byte is
/// ignored.
double rmsOf(Uint8List s16le) {
  final count = s16le.lengthInBytes ~/ 2;
  if (count == 0) return 0;
  final data = ByteData.sublistView(s16le);
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    final sample = data.getInt16(i * 2, Endian.little);
    sum += sample * sample;
  }
  return math.sqrt(sum / count);
}

/// The orb's 0..1 level for an RMS: dBFS from -45 (a quiet room) to 0
/// (clipping), as `RecordVoiceRecorder.level` spreads it.
double orbLevel(double rms) {
  if (rms <= 0) return 0;
  final dbfs = 20 * math.log(rms / _fullScale) / math.ln10;
  return ((dbfs + 45) / 45).clamp(0.0, 1.0);
}
