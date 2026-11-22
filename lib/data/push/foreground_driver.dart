/// The [ForegroundDriver] over flutter_foreground_task, and the one arbiter the app shares between push and calls.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/logging.dart';
import 'android_push_task.dart';
import 'foreground_arbiter.dart';

/// The app's single arbiter: a voice call and push must agree on the one service.
final ForegroundArbiter foregroundArbiter = ForegroundArbiter(
  PluginForegroundDriver(),
);

final class PluginForegroundDriver implements ForegroundDriver {
  static const _log = IrisLog('service');
  static const _serviceId = 4417;
  static const _types = MethodChannel('iris/foreground');

  /// The notification permission is asked once per run, the first time the service starts; a refusal only hides the
  /// notification.
  static bool _askedNotifications = false;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  static List<ForegroundServiceTypes> _plugin(Set<ServiceType> types) => [
    if (types.contains(ServiceType.microphone))
      ForegroundServiceTypes.microphone,
    if (types.contains(ServiceType.remoteMessaging))
      ForegroundServiceTypes.remoteMessaging,
  ];

  static List<NotificationButton> _buttons(ServiceNotice notice) => [
    for (final b in notice.buttons) NotificationButton(id: b.id, text: b.text),
  ];

  /// Never stops with the app's task: the plugin's stop-with-task mode stops the service whenever the app leaves the
  /// screen, and cannot be undone for the rest of the process. `MainActivity.onDestroy` tells the service isolate
  /// instead, which stops a call-only service itself.
  static ForegroundTaskOptions _options({required bool persistent}) =>
      ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        stopWithTask: false,
        autoRunOnBoot: persistent,
        autoRunOnMyPackageReplaced: persistent,
        allowWifiLock: persistent,
        allowAutoRestart: persistent,
      );

  static AndroidNotificationOptions _channel(
    ServiceOwner owner,
  ) => switch (owner) {
    ServiceOwner.call => AndroidNotificationOptions(
      channelId: 'iris_calls',
      channelName: 'Voice calls',
      channelDescription: 'Shown while you are talking with Iris.',
      onlyAlertOnce: true,
    ),
    ServiceOwner.push => AndroidNotificationOptions(
      channelId: PushChannel.connection.id,
      channelName: PushChannel.connection.label,
      channelDescription: PushChannel.connection.description,
      // Low importance and priority are the plugin's defaults: it never makes a sound.
      onlyAlertOnce: true,
    ),
  };

  @override
  Future<bool> start({
    required Set<ServiceType> types,
    required ServiceNotice notice,
    required ServiceOwner channel,
    required bool persistent,
  }) async {
    if (!_android) return false;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: _channel(channel),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: _options(persistent: persistent),
    );
    await _askNotifications();
    // Push's service outlives the app; a new run of the app finds it running and takes it over.
    if (await FlutterForegroundTask.isRunningService) {
      await update(notice, persistent: persistent);
      return true;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: _plugin(types),
      notificationTitle: notice.title,
      notificationText: notice.text,
      notificationButtons: _buttons(notice),
      callback: startIrisServiceTask,
    );
    if (result case ServiceRequestFailure(:final error)) {
      _log.warn('service did not start', data: {'error': '$error'});
      return false;
    }
    return true;
  }

  @override
  Future<void> update(ServiceNotice notice, {required bool persistent}) async {
    if (!_android) return;
    final result = await FlutterForegroundTask.updateService(
      foregroundTaskOptions: _options(persistent: persistent),
      notificationTitle: notice.title,
      notificationText: notice.text,
      notificationButtons: _buttons(notice),
    );
    if (result case ServiceRequestFailure(:final error)) {
      _log.warn('service update failed', data: {'error': '$error'});
    }
  }

  @override
  Future<bool> retype(Set<ServiceType> types) async {
    if (!_android) return false;
    try {
      await _types.invokeMethod<int>('setServiceTypes', [
        for (final t in types) t.name,
      ]);
    } on PlatformException catch (error) {
      _log.warn('could not store service types', data: error.code);
      return false;
    }
    final result = await FlutterForegroundTask.restartService();
    if (result case ServiceRequestFailure(:final error)) {
      _log.warn('service restart refused', data: {'error': '$error'});
      return false;
    }
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_android) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  void tell(Map<String, Object?> message) {
    if (_android) FlutterForegroundTask.sendDataToTask(message);
  }

  static Future<void> _askNotifications() async {
    if (_askedNotifications) return;
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
}
