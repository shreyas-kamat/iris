/// The audio session for a call: voice-chat category, interruptions (a phone
/// call), headphones coming out, and which output Iris speaks through.
library;

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../../core/logging.dart';

enum InterruptionKind { began, ended }

@immutable
final class RouteInfo {
  const RouteInfo({required this.speaker, this.headset});

  /// The loudspeaker rather than the earpiece. Moot while a headset is in.
  final bool speaker;

  /// The connected headset's name, e.g. "AirPods Pro".
  final String? headset;

  @override
  bool operator ==(Object other) =>
      other is RouteInfo &&
      other.speaker == speaker &&
      other.headset == headset;

  @override
  int get hashCode => Object.hash(speaker, headset);
}

abstract interface class AudioRoute {
  /// Claims the session for a call: play-and-record, voice chat, audio focus.
  Future<void> activate();

  /// Gives the session back to the system and other apps.
  Future<void> deactivate();

  /// A phone call or another app taking the audio, and its end. Ducking (a
  /// notification sound) is not an interruption.
  Stream<InterruptionKind> get interruptions;

  /// Headphones unplugged or disconnected: playback should pause at once.
  Stream<void> get becameNoisy;

  /// The current output, whenever it changes.
  Stream<RouteInfo> get route;

  Future<void> setSpeaker({required bool on});
}

final class PlatformAudioRoute implements AudioRoute {
  PlatformAudioRoute({bool speaker = true}) : _speaker = speaker;

  static const _log = IrisLog('voice.route');

  // AudioDeviceType is marked experimental; only its names are relied on,
  // and a renamed type would fail the build here rather than misroute.
  // ignore: experimental_member_use
  static const _headsets = <AudioDeviceType>{
    // ignore: experimental_member_use
    AudioDeviceType.wiredHeadset,
    // ignore: experimental_member_use
    AudioDeviceType.wiredHeadphones,
    // ignore: experimental_member_use
    AudioDeviceType.bluetoothA2dp,
    // ignore: experimental_member_use
    AudioDeviceType.bluetoothSco,
    // ignore: experimental_member_use
    AudioDeviceType.bluetoothLe,
    // ignore: experimental_member_use
    AudioDeviceType.usbAudio,
    // ignore: experimental_member_use
    AudioDeviceType.hearingAid,
    // ignore: experimental_member_use
    AudioDeviceType.airPlay,
    // ignore: experimental_member_use
    AudioDeviceType.carAudio,
  };

  static final _configuration = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    // No defaultToSpeaker: the earpiece must stay reachable, so the speaker
    // is an explicit override that [setSpeaker] applies.
    avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.allowBluetoothA2dp,
    avAudioSessionMode: AVAudioSessionMode.voiceChat,
    androidAudioAttributes: const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.voiceCommunication,
    ),
    androidWillPauseWhenDucked: false,
  );

  final _route = StreamController<RouteInfo>.broadcast();
  bool _speaker;
  bool _active = false;
  StreamSubscription<AudioDevicesChangedEvent>? _devices;
  RouteInfo? _last;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Stream<InterruptionKind> get interruptions =>
      Stream.fromFuture(AudioSession.instance).asyncExpand(
        (session) => session.interruptionEventStream
            .where((event) => event.type != AudioInterruptionType.duck)
            .map(
              (event) =>
                  event.begin ? InterruptionKind.began : InterruptionKind.ended,
            ),
      );

  @override
  Stream<void> get becameNoisy => Stream.fromFuture(
    AudioSession.instance,
  ).asyncExpand((session) => session.becomingNoisyEventStream);

  /// Starts with the current output, once the session is active.
  @override
  Stream<RouteInfo> get route async* {
    if (_last case final last?) yield last;
    yield* _route.stream;
  }

  @override
  Future<void> activate() async {
    final session = await AudioSession.instance;
    await session.configure(_configuration);
    await session.setActive(true);
    if (_isAndroid) {
      await AndroidAudioManager().setMode(
        AndroidAudioHardwareMode.inCommunication,
      );
    }
    _active = true;
    _devices ??= session.devicesChangedEventStream.listen((_) async {
      // iOS drops an output override when the route changes.
      await _applySpeaker();
      await _publish();
    });
    await _applySpeaker();
    await _publish();
  }

  /// Puts the category, mode and output back after another plugin (the iOS
  /// PCM player) has set its own.
  Future<void> reapply() async {
    if (!_active) return;
    final session = await AudioSession.instance;
    await session.configure(_configuration);
    await _applySpeaker();
  }

  @override
  Future<void> deactivate() async {
    _active = false;
    await _devices?.cancel();
    _devices = null;
    try {
      if (_isAndroid) {
        final manager = AndroidAudioManager();
        await manager.setSpeakerphoneOn(false);
        await manager.setMode(AndroidAudioHardwareMode.normal);
      }
      final session = await AudioSession.instance;
      await session.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } on Object catch (error) {
      _log.warn('session release failed', data: {'error': '$error'});
    }
  }

  @override
  Future<void> setSpeaker({required bool on}) async {
    _speaker = on;
    if (!_active) return;
    await _applySpeaker();
    await _publish();
  }

  Future<void> _applySpeaker() async {
    if (!_active) return;
    try {
      if (_isAndroid) {
        await AndroidAudioManager().setSpeakerphoneOn(_speaker);
      } else if (_isIos) {
        await AVAudioSession().overrideOutputAudioPort(
          _speaker
              ? AVAudioSessionPortOverride.speaker
              : AVAudioSessionPortOverride.none,
        );
      }
    } on Object catch (error) {
      _log.warn('output switch failed', data: {'error': '$error'});
    }
  }

  Future<void> _publish() async {
    String? headset;
    try {
      final session = await AudioSession.instance;
      final outputs = await session.getDevices(includeInputs: false);
      for (final device in outputs) {
        if (_headsets.contains(device.type) && device.name.trim().isNotEmpty) {
          headset = device.name.trim();
          break;
        }
      }
    } on Object catch (error) {
      _log.warn('device list failed', data: {'error': '$error'});
    }
    final info = RouteInfo(speaker: _speaker, headset: headset);
    if (info == _last) return;
    _last = info;
    if (!_route.isClosed) _route.add(info);
  }

  Future<void> dispose() async {
    await deactivate();
    await _route.close();
  }
}
