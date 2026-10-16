/// Recording a short clip for dictation: 16 kHz mono WAV, what Hermes'
/// speech-to-text expects.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract interface class VoiceRecorder {
  /// Starts recording. False when the microphone is refused.
  Future<bool> start();

  /// Stops and returns the clip, or null if nothing was recorded.
  Future<Uint8List?> stop();

  /// Stops and throws the clip away.
  Future<void> cancel();

  /// How loud it is right now, 0 to 1, about ten a second while recording.
  Stream<double> get level;
}

final class RecordVoiceRecorder implements VoiceRecorder {
  final _recorder = AudioRecorder();
  String? _path;

  // dBFS from -45 (quiet room) to 0 (clipping), spread over 0 to 1.
  @override
  Stream<double> get level => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((a) => ((a.current + 45) / 45).clamp(0.0, 1.0));

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = p.join(dir.path, 'dictation.wav');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
    return true;
  }

  @override
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop() ?? _path;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    final path = _path;
    if (path != null && File(path).existsSync()) await File(path).delete();
  }
}
