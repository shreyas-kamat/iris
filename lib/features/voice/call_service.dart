/// Keeping a call alive with the screen off: on Android a microphone-type
/// foreground service with the call's notification (D1) and its Mute and End
/// buttons. iOS keeps the call going with the `audio` background mode and
/// shows its own microphone indicator, so the service does nothing there.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/logging.dart';
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

/// The Android foreground service, through `flutter_foreground_task`.
final class ForegroundCallService implements CallService {
  ForegroundCallService();

  static const _log = IrisLog('voice.service');
  static const _serviceId = 4417;

  /// The notification permission is asked once, on the first call; a
  /// refusal only hides the notification, the call goes on.
  static bool _askedNotifications = false;

  final _actions = StreamController<CallAction>.broadcast();
  bool _running = false;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<CallAction> get actions => _actions.stream;

  @override
  Future<void> start(CallNotice notice) async {
    if (!_android || _running) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'iris_calls',
        channelName: 'Voice calls',
        channelDescription: 'Shown while you are talking with Iris.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        stopWithTask: true,
      ),
    );
    if (!_askedNotifications) {
      _askedNotifications = true;
      try {
        final permission =
            await FlutterForegroundTask.checkNotificationPermission();
        if (permission != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
      } on Object catch (error) {
        _log.warn('notification permission', data: {'error': '$error'});
      }
    }
    FlutterForegroundTask.addTaskDataCallback(_onData);
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: notice.title,
      notificationText: notice.text,
      notificationButtons: _buttons(muted: notice.muted),
      callback: startCallTask,
    );
    _running = result is ServiceRequestSuccess;
    if (result case ServiceRequestFailure(:final error)) {
      _log.warn('call service did not start', data: {'error': '$error'});
    }
  }

  @override
  Future<void> update(CallNotice notice) async {
    if (!_running) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: notice.title,
      notificationText: notice.text,
      notificationButtons: _buttons(muted: notice.muted),
    );
  }

  @override
  Future<void> stop() async {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    if (!_running) return;
    _running = false;
    await FlutterForegroundTask.stopService();
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

  static List<NotificationButton> _buttons({required bool muted}) => [
    NotificationButton(
      id: muted ? 'unmute' : 'mute',
      text: muted ? 'Unmute' : 'Mute',
    ),
    const NotificationButton(id: 'end', text: 'End'),
  ];
}

/// The service's own isolate: it only passes the buttons back to the app.
@pragma('vm:entry-point')
void startCallTask() => FlutterForegroundTask.setTaskHandler(_CallTask());

final class _CallTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) =>
      FlutterForegroundTask.sendDataToMain(id);

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}
