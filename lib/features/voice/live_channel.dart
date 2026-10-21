/// The WebRTC link to GPT-Live: the microphone goes out as a track, the
/// model's voice comes back as one, and the `oai-events` data channel carries
/// what Hermes and the phone tell each other.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/json.dart';
import '../../core/logging.dart';

abstract interface class LivePeer {
  /// Opens the microphone (disabled) and the data channel, and returns the
  /// SDP offer to send to Hermes.
  Future<String> offer();

  /// Applies the vendor's answer, byte for byte.
  Future<void> answer(String sdp);

  /// Events from the data channel.
  Stream<Json> get events;

  /// Sends an event; queued until the channel is open.
  void send(Map<String, Object?> event);

  /// 0..1 loudness of the model's voice.
  Stream<double> get remoteLevel;

  Future<void> setMicEnabled({required bool on});
  Future<void> close();
}

final class WebRtcLivePeer implements LivePeer {
  WebRtcLivePeer();

  static const _log = IrisLog('voice.live');
  static const _levelEvery = Duration(milliseconds: 100);

  final _events = StreamController<Json>.broadcast();
  final _level = StreamController<double>.broadcast();
  final _queued = <String>[];
  RTCPeerConnection? _pc;
  MediaStream? _mic;
  RTCDataChannel? _channel;
  bool _open = false;
  bool _closed = false;
  Timer? _stats;

  @override
  Stream<Json> get events => _events.stream;

  @override
  Stream<double> get remoteLevel => _level.stream;

  @override
  Future<String> offer() async {
    final pc = _pc = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
    });
    final mic = _mic = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in mic.getAudioTracks()) {
      // Nothing is heard until the call has passed its checks.
      track.enabled = false;
      await pc.addTrack(track, mic);
    }
    final channel = _channel = await pc.createDataChannel(
      'oai-events',
      RTCDataChannelInit(),
    );
    channel
      ..onDataChannelState = (state) {
        if (state != RTCDataChannelState.RTCDataChannelOpen) return;
        _open = true;
        for (final text in _queued) {
          channel.send(RTCDataChannelMessage(text));
        }
        _queued.clear();
      }
      ..onMessage = (message) {
        if (message.isBinary || _events.isClosed) return;
        try {
          _events.add(Json.decode(message.text));
        } on FormatException {
          _log.warn('unreadable live event');
        }
      };
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<void> answer(String sdp) async {
    await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _stats ??= Timer.periodic(_levelEvery, (_) => unawaited(_readLevel()));
  }

  Future<void> _readLevel() async {
    final pc = _pc;
    if (pc == null || _closed) return;
    try {
      for (final report in await pc.getStats()) {
        final values = report.values;
        if (report.type == 'inbound-rtp' &&
            values['kind'] == 'audio' &&
            values['audioLevel'] is num) {
          if (!_level.isClosed) {
            _level.add((values['audioLevel'] as num).toDouble().clamp(0, 1));
          }
          return;
        }
      }
    } on Object catch (error) {
      _log.debug('stats unavailable', data: {'error': '$error'});
    }
  }

  @override
  void send(Map<String, Object?> event) {
    if (_closed) return;
    final text = jsonEncode(event);
    final channel = _channel;
    if (_open && channel != null) {
      unawaited(channel.send(RTCDataChannelMessage(text)));
    } else {
      _queued.add(text);
    }
  }

  @override
  Future<void> setMicEnabled({required bool on}) async {
    for (final track in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = on;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stats?.cancel();
    try {
      for (final track in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _mic?.dispose();
      await _channel?.close();
      await _pc?.close();
    } on Object catch (error) {
      _log.warn('live close failed', data: {'error': '$error'});
    }
    await _events.close();
    await _level.close();
  }
}
