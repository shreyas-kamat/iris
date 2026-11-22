/// Keeping a call alive with the screen off: on Android a microphone-type
/// foreground service with the call's notification (D1) and its Mute and End
/// buttons. The service is shared with push (see `ForegroundArbiter`); its
/// isolate is `startIrisServiceTask`, which passes the buttons back here. iOS keeps the call going with the `audio` background mode and
/// shows its own microphone indicator, so the service does nothing there.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../data/push/foreground_arbiter.dart';
import '../../data/push/foreground_driver.dart';
import 'voice_call.dart';

enum CallAction { mute, unmute, end }

/// What the call's notification says.
@immutable
final class CallNotice {
  const CallNotice({
    required this.title,
    required this.text,
    required this.muted,
    required this.elapsed,
  });

  final String title;
  final String text;
  final bool muted;

  /// How long the call has run. Not part of equality: the clock alone never
  /// re-sends the notification.
  final Duration elapsed;

  @override
  bool operator ==(Object other) =>
      other is CallNotice &&
      other.title == title &&
      other.text == text &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(title, text, muted);
}

abstract interface class CallService {
  Future<void> start(CallNotice notice);
  Future<void> update(CallNotice notice);
  Future<void> stop();

  /// The notification's buttons.
  Stream<CallAction> get actions;
}

/// The notification's state line (D1).
String noticeText(CallMode mode, {Duration? workingFor}) => switch (mode) {
  CallMode.connecting => 'Connecting',
  CallMode.listening => 'Listening',
  CallMode.hearing || CallMode.interrupted => 'Hearing you',
  CallMode.thinking || CallMode.tool =>
    workingFor == null
        ? 'Working on it'
        : 'Working on it · ${_clock(workingFor)}',
  CallMode.speaking => 'Speaking',
  CallMode.muted => 'Muted',
  CallMode.needs => 'Needs you',
  CallMode.reconnecting => 'Reconnecting',
  CallMode.paused => 'Paused',
  CallMode.error || CallMode.ended => 'Call ended',
};

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = two(d.inSeconds % 60);
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes % 60)}:$seconds';
  }
  return '${d.inMinutes}:$seconds';
}

/// The Android foreground service, shared with push through the [ForegroundArbiter]: while the call runs, its
/// notification, buttons and microphone type are the service's; when it ends, push (if on) keeps the service.
final class ForegroundCallService implements CallService {
  ForegroundCallService({ForegroundArbiter? arbiter})
    : _arbiter = arbiter ?? foregroundArbiter;

  final ForegroundArbiter _arbiter;
  final _actions = StreamController<CallAction>.broadcast();
  bool _running = false;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<CallAction> get actions => _actions.stream;

  @override
  Future<void> start(CallNotice notice) async {
    if (!_android || _running) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    _running = await _arbiter.need(ServiceOwner.call, _service(notice));
  }

  @override
  Future<void> update(CallNotice notice) async {
    if (!_running) return;
    await _arbiter.need(ServiceOwner.call, _service(notice));
  }

  @override
  Future<void> stop() async {
    if (!_android) return;
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    if (!_running) return;
    _running = false;
    await _arbiter.release(ServiceOwner.call);
  }

  void _onData(Object data) {
    final action = switch (data) {
      'mute' => CallAction.mute,
      'unmute' => CallAction.unmute,
      'end' => CallAction.end,
      _ => null,
    };
    if (action != null && !_actions.isClosed) _actions.add(action);
  }

  static ServiceNotice _service(CallNotice notice) => ServiceNotice(
    title: notice.title,
    text: notice.text,
    buttons: [
      ServiceButton(
        notice.muted ? 'unmute' : 'mute',
        notice.muted ? 'Unmute' : 'Mute',
      ),
      const ServiceButton('end', 'End'),
    ],
  );
}
