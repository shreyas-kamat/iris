/// Iris's voice coming out of the phone: streamed PCM for a reply, or a whole
/// file when the server falls back to one-shot speech.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging.dart' show IrisLog;
import '../levels.dart';

abstract interface class AudioOut {
  /// Begins a reply's audio at [sampleRate] (the speak stream's `start`
  /// frame), signed 16-bit little-endian mono.
  Future<void> startPcm(int sampleRate);

  /// Queues a chunk; it plays after what came before.
  void addPcm(Uint8List pcm);

  /// No more chunks. Completes once everything queued has been heard.
  Future<void> endPcm();

  /// Plays a whole file (the one-shot fallback). Completes when it is done,
  /// or when [stop] cuts it.
  Future<void> playFile(Uint8List bytes, String mime);

  /// Silences everything at once (barge-in, End) and completes any pending
  /// [endPcm] or [playFile].
  Future<void> stop();

  /// 0..1 loudness of what is playing, for the orb.
  Stream<double> get level;
}

/// Plays PCM where a voice call's audio belongs: Android's voice
/// communication stream (so the earpiece and speaker switch apply and the
/// echo canceller hears it), iOS's play-and-record session. Files go through
/// `just_audio`.
final class PlatformAudioOut implements AudioOut {
  /// [afterSetup] runs after the iOS PCM player has (re)claimed the audio
  /// session, so the route can put its own category, mode and output back.
  PlatformAudioOut({Future<void> Function()? afterSetup})
    : _sink = defaultTargetPlatform == TargetPlatform.iOS
          ? _PcmSoundSink(afterSetup)
          : _ChannelPcmSink();

  static const _log = IrisLog('voice.out');

  /// The orb's level moves in steps of this much audio.
  static const _slice = Duration(milliseconds: 50);

  /// Stands in for the level while a file plays, which has no samples here.
  static const _fileLevel = 0.45;

  final _PcmSink _sink;
  final _level = StreamController<double>.broadcast();
  final _slices = Queue<double>();
  Timer? _ticker;
  int _sampleRate = 24000;
  final _partial = BytesBuilder(copy: false);

  AudioPlayer? _player;
  Completer<void>? _file;

  @override
  Stream<double> get level => _level.stream;

  @override
  Future<void> startPcm(int sampleRate) async {
    _resetLevel();
    _sampleRate = sampleRate;
    await _sink.start(sampleRate);
  }

  @override
  void addPcm(Uint8List pcm) {
    if (pcm.isEmpty) return;
    _sink.feed(pcm);
    _queueLevels(pcm);
  }

  @override
  Future<void> endPcm() async {
    try {
      await _sink.end();
    } finally {
      _resetLevel();
    }
  }

  @override
  Future<void> playFile(Uint8List bytes, String mime) async {
    await _stopFile();
    final done = _file = Completer<void>();
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'iris-reply${_extension(mime)}'));
    await file.writeAsBytes(bytes, flush: true);
    // The call reacts to interruptions itself; the player only plays.
    final player = _player = AudioPlayer(handleInterruptions: false);
    StreamSubscription<PlayerState>? watch;
    try {
      await player.setFilePath(file.path);
      if (done.isCompleted) return; // stopped while loading
      watch = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed &&
            !done.isCompleted) {
          done.complete();
        }
      });
      _level.add(_fileLevel);
      unawaited(player.play());
      await done.future;
    } on Object catch (error, stack) {
      _log.error('file playback failed', cause: error, stackTrace: stack);
    } finally {
      await watch?.cancel();
      if (identical(_player, player)) _player = null;
      await player.dispose();
      if (!_level.isClosed) _level.add(0);
      if (file.existsSync()) await file.delete();
      if (!done.isCompleted) done.complete();
    }
  }

  @override
  Future<void> stop() async {
    _resetLevel();
    await Future.wait([_sink.stop(), _stopFile()]);
  }

  Future<void> _stopFile() async {
    final done = _file;
    _file = null;
    await _player?.stop();
    if (done != null && !done.isCompleted) done.complete();
  }

  /// The level follows the audio in [_slice] steps from when it was queued:
  /// the speak stream sends faster than real time, so the samples wait their
  /// turn here as they do in the player.
  void _queueLevels(Uint8List pcm) {
    final sliceBytes = (_sampleRate * _slice.inMilliseconds ~/ 1000) * 2;
    _partial.add(pcm);
    if (_partial.length < sliceBytes) return;
    final bytes = _partial.takeBytes();
    var offset = 0;
    for (; offset + sliceBytes <= bytes.length; offset += sliceBytes) {
      _slices.add(
        orbLevel(
          rmsOf(Uint8List.sublistView(bytes, offset, offset + sliceBytes)),
        ),
      );
    }
    if (offset < bytes.length) {
      _partial.add(Uint8List.sublistView(bytes, offset));
    }
    _ticker ??= Timer.periodic(_slice, (_) {
      if (_slices.isEmpty) {
        _level.add(0);
        _ticker?.cancel();
        _ticker = null;
      } else {
        _level.add(_slices.removeFirst());
      }
    });
  }

  void _resetLevel() {
    _ticker?.cancel();
    _ticker = null;
    _slices.clear();
    _partial.clear();
    if (!_level.isClosed) _level.add(0);
  }

  static String _extension(String mime) => switch (mime.toLowerCase()) {
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => '.wav',
    'audio/ogg' || 'audio/opus' => '.ogg',
    'audio/aac' => '.aac',
    'audio/mp4' || 'audio/m4a' => '.m4a',
    _ => '.mp3',
  };

  Future<void> dispose() async {
    await stop();
    await _level.close();
  }
}

abstract interface class _PcmSink {
  Future<void> start(int sampleRate);
  void feed(Uint8List pcm);
  Future<void> end();
  Future<void> stop();
}

/// Android: `PcmOutChannel` in the app's own Kotlin, an `AudioTrack` with
/// voice-communication usage. (`flutter_pcm_sound` plays Android audio as
/// media, which the speaker switch and the echo canceller ignore.)
final class _ChannelPcmSink implements _PcmSink {
  static const _channel = MethodChannel('iris/pcm_out');

  @override
  Future<void> start(int sampleRate) =>
      _channel.invokeMethod<void>('start', {'sampleRate': sampleRate});

  @override
  void feed(Uint8List pcm) =>
      unawaited(_channel.invokeMethod<void>('feed', {'pcm': pcm}));

  @override
  Future<void> end() => _channel.invokeMethod<void>('end');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// iOS: `flutter_pcm_sound` in the play-and-record category. Its feed
/// callback reports zero frames left once the queue has drained.
final class _PcmSoundSink implements _PcmSink {
  _PcmSoundSink(this._afterSetup);

  final Future<void> Function()? _afterSetup;
  int? _rate;
  bool _drained = true;
  Completer<void>? _ending;

  @override
  Future<void> start(int sampleRate) async {
    if (_rate != sampleRate) {
      // Its default logging prints sample bytes; PCM is never logged.
      await FlutterPcmSound.setLogLevel(LogLevel.none);
      await FlutterPcmSound.setup(
        sampleRate: sampleRate,
        channelCount: 1,
        iosAudioCategory: IosAudioCategory.playAndRecord,
        iosAllowBackgroundAudio: true,
      );
      FlutterPcmSound.setFeedCallback(_onFeed);
      await _afterSetup?.call();
      _rate = sampleRate;
    }
    _drained = true;
  }

  void _onFeed(int remaining) {
    if (remaining != 0) return;
    _drained = true;
    final ending = _ending;
    _ending = null;
    if (ending != null && !ending.isCompleted) ending.complete();
  }

  @override
  void feed(Uint8List pcm) {
    _drained = false;
    unawaited(
      FlutterPcmSound.feed(PcmArrayInt16(bytes: ByteData.sublistView(pcm))),
    );
  }

  @override
  Future<void> end() {
    if (_drained) return Future.value();
    return (_ending ??= Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    // Releasing is the only way to drop what is queued.
    if (_rate != null) await FlutterPcmSound.release();
    _rate = null;
    _drained = true;
    final ending = _ending;
    _ending = null;
    if (ending != null && !ending.isCompleted) ending.complete();
  }
}
