/// The `transcribe-stream` socket: the microphone's PCM goes up as it is
/// recorded, partial words come back while the person speaks, and the final
/// transcript arrives once the end is signalled.
///
/// Only when the server has `stt.streaming` on; otherwise it answers with an
/// error frame, which `finish` reports.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../core/failure.dart';
import '../../core/result.dart';
import 'audio_socket.dart';

final class TranscribeStream {
  /// Opens the stream for audio at [sampleRate] (16-bit little-endian mono PCM).
  TranscribeStream(this._socket, {int sampleRate = 16000}) {
    _sub = _socket.frames.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
    );
    _send({'sample_rate': sampleRate});
  }

  static const _route = '/api/audio/transcribe-stream';

  final AudioSocket _socket;
  late final StreamSubscription<AudioFrame> _sub;
  final _partials = StreamController<String>.broadcast();
  final _result = Completer<Result<String>>();
  bool _closed = false;

  /// What has been heard so far, as the server revises it. Never carries the
  /// final transcript; that is [finish]'s.
  Stream<String> get partials => _partials.stream;

  /// Sends the next chunk of recorded audio.
  void add(Uint8List pcm) {
    if (_closed) return;
    try {
      _socket.sendBytes(pcm);
    } on StateError {
      // Closed under us; reported through [finish].
    }
  }

  /// Signals the end of the audio and waits for the final words. An error
  /// frame, a dropped socket and a silent server are all failures. Closes the
  /// socket either way.
  Future<Result<String>> finish({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!_result.isCompleted) _send({'eos': true});
    final result = await _result.future.timeout(
      timeout,
      onTimeout: () => const Err<String>(
        IrisFailure(
          FailureKind.timeout,
          message: 'Transcription took too long.',
          endpoint: _route,
        ),
      ),
    );
    await _shutdown();
    return result;
  }

  /// Gives up without signalling the end.
  Future<void> cancel() async {
    _complete(const Err(IrisFailure.cancelled()));
    await _shutdown();
  }

  void _send(Map<String, Object?> json) {
    try {
      _socket.sendJson(json);
    } on StateError {
      // Closed under us; reported through [finish].
    }
  }

  void _onFrame(AudioFrame frame) {
    if (frame is! AudioText) return;
    final json = frame.json;
    switch (json['type'].stringOrNull) {
      case 'partial':
        final text = json['text'].stringOrNull;
        if (text != null && !_partials.isClosed) _partials.add(text);
      case 'final':
        _complete(
          Ok(
            (json['transcript'].stringOrNull ?? json['text'].stringOrNull ?? '')
                .trim(),
          ),
        );
      case 'error':
        _complete(
          Err(
            IrisFailure(
              FailureKind.server,
              message:
                  json['message'].stringOrNull ??
                  'Live transcription failed on the server.',
              endpoint: _route,
            ),
          ),
        );
    }
  }

  void _onClosed() {
    _complete(
      const Err(
        IrisFailure(
          FailureKind.offline,
          message: 'The transcription connection dropped.',
          endpoint: _route,
        ),
      ),
    );
    unawaited(_shutdown());
  }

  void _complete(Result<String> result) {
    if (!_result.isCompleted) _result.complete(result);
  }

  Future<void> _shutdown() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await _partials.close();
    await _socket.close();
  }
}
