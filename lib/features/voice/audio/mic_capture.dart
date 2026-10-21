/// The microphone as a live PCM stream, for the call loop.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../core/logging.dart';

/// 16 kHz signed 16-bit little-endian mono, with the platform's echo
/// cancellation and noise suppression on, so Iris does not hear itself.
abstract interface class MicCapture {
  /// Opens the microphone. False when it cannot (no permission, or the
  /// platform refused). Calling it while already open does nothing more.
  Future<bool> start();

  /// Chunks while open. Broadcast; nothing is buffered for late listeners.
  Stream<Uint8List> get pcm;

  /// Closes the microphone. Safe to call when closed.
  Future<void> stop();
}

final class RecordMicCapture implements MicCapture {
  RecordMicCapture();

  static const _log = IrisLog('voice.mic');

  static const sampleRate = 16000;

  final _pcm = StreamController<Uint8List>.broadcast();
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _source;

  /// The open or opening attempt, so two quick starts share one capture.
  Future<bool>? _starting;

  @override
  Stream<Uint8List> get pcm => _pcm.stream;

  @override
  Future<bool> start() => _starting ??= _open();

  Future<bool> _open() async {
    final recorder = _recorder ??= AudioRecorder();
    try {
      if (!await recorder.hasPermission(request: false)) {
        _starting = null;
        return false;
      }
      // The audio route owns the iOS session (play-and-record, voice chat);
      // left to itself the recorder would set its own category.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await recorder.ios?.manageAudioSession(false);
      }
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          // The call reacts to interruptions itself (a phone call pauses it).
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
          ),
        ),
      );
      _source = stream.listen(
        _pcm.add,
        onError: (Object error, StackTrace stack) =>
            _log.warn('mic stream failed', data: {'error': '$error'}),
      );
      return true;
    } on Object catch (error, stack) {
      _log.error('mic did not open', cause: error, stackTrace: stack);
      _starting = null;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final starting = _starting;
    if (starting == null) return;
    // Let an open in flight land first, so it cannot reopen after the stop.
    await starting;
    _starting = null;
    await _source?.cancel();
    _source = null;
    try {
      await _recorder?.stop();
    } on Object catch (error) {
      _log.warn('mic stop failed', data: {'error': '$error'});
    }
  }

  /// Releases the recorder for good.
  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
    _recorder = null;
    await _pcm.close();
  }
}
