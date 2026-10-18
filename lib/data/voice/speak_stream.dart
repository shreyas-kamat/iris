/// One reply's `speak-stream` socket: text goes in as the agent writes it, and
/// speech comes back as PCM, sentence by sentence, from the first words.
library;

import 'dart:async';
import 'dart:typed_data';

import 'audio_socket.dart';

sealed class SpeakFrame {
  const SpeakFrame();
}

/// The first audio is about to arrive, in this format (16-bit little-endian
/// PCM).
final class SpeakStart extends SpeakFrame {
  const SpeakStart({required this.sampleRate, this.channels = 1});

  final int sampleRate;
  final int channels;
}

/// A chunk of speech.
final class SpeakPcm extends SpeakFrame {
  const SpeakPcm(this.pcm);

  final Uint8List pcm;
}

/// The server has said everything it was given, or the socket closed. Always
/// the last frame, so a listener never waits on a socket that went quiet.
final class SpeakEnd extends SpeakFrame {
  const SpeakEnd();
}

/// Synthesis produced nothing (or failed): speak the whole reply with the
/// one-shot route instead. Always the last frame.
final class SpeakFallback extends SpeakFrame {
  const SpeakFallback();
}

final class SpeakStream {
  SpeakStream(this._socket) {
    _sub = _socket.frames.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
    );
  }

  final AudioSocket _socket;
  late final StreamSubscription<AudioFrame> _sub;
  final _frames = StreamController<SpeakFrame>();

  bool _finished = false;
  bool _doneSent = false;

  /// What the server sends, in order. Buffered until listened to, and ended
  /// by a [SpeakEnd] or [SpeakFallback] (or, after [stop], by nothing at all).
  Stream<SpeakFrame> get frames => _frames.stream;

  /// Sends more of the reply. Empty text is not sent; whitespace is, since
  /// the gap between two deltas can be the only thing between two words.
  void add(String text) {
    if (text.isEmpty || _finished || _doneSent) return;
    _send({'text': text});
  }

  /// Says the reply is complete, so the server speaks what is left.
  void done() {
    if (_finished || _doneSent) return;
    _doneSent = true;
    _send({'done': true});
  }

  /// Cuts the speech off (a barge-in) and closes the socket. Nothing more is
  /// delivered on [frames], which ends.
  Future<void> stop() async {
    if (_finished) return;
    _finished = true;
    _send({'stop': true});
    await _sub.cancel();
    await _frames.close();
    await _socket.close();
  }

  void _send(Map<String, Object?> json) {
    try {
      _socket.sendJson(json);
    } on StateError {
      // The socket closed under us; the close is reported on its own.
    }
  }

  void _onFrame(AudioFrame frame) {
    if (_finished) return;
    switch (frame) {
      case AudioBytes(:final bytes):
        _frames.add(SpeakPcm(bytes));
      case AudioText(:final json):
        switch (json['type'].stringOrNull) {
          case 'start':
            final rate = json['sample_rate'].intOrNull;
            // A start that does not say how to play the audio cannot be used.
            if (rate == null || rate <= 0) return;
            _frames.add(
              SpeakStart(
                sampleRate: rate,
                channels: json['channels'].intOrNull ?? 1,
              ),
            );
          case 'end':
            _finish(const SpeakEnd());
          // A failed synthesis is reported as an error frame or as nothing at
          // all; either way the reply is still owed to the ear.
          case 'fallback' || 'error':
            _finish(const SpeakFallback());
        }
    }
  }

  void _onClosed() => _finish(const SpeakEnd());

  void _finish(SpeakFrame last) {
    if (_finished) return;
    _finished = true;
    _frames.add(last);
    unawaited(_frames.close());
    unawaited(_sub.cancel());
    unawaited(_socket.close());
  }
}
