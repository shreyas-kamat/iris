/// Android push from the app's side: starts and stops the service's push connection with the person's switch, keeps
/// the server's registration fresh, relays the connection state to Settings, tells the service which chat is on
/// screen, and opens what a tapped notification is about.
///
/// The service's isolate does the rest on its own (`android_push_task.dart`), so notifications keep coming with the
/// app closed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../data/push/android_push_task.dart';
import '../data/push/foreground_arbiter.dart';
import '../data/push/foreground_driver.dart';
import '../data/push/push_intents.dart';
import '../data/push/push_stream_client.dart';
import '../demo/demo_mode.dart';
import 'providers.dart';
import 'push_providers.dart';
import 'push_router.dart';

/// What the service should do. [unknown] while the app cannot tell yet (no server chosen, the demo): the service is
/// left as it is, so a cold start does not stop and restart a connection that was fine.
sealed class PushWanted {
  const PushWanted();

  static const unknown = PushUnknown();
  static const off = PushOff();
}

final class PushUnknown extends PushWanted {
  const PushUnknown();
}

final class PushOff extends PushWanted {
  const PushOff();
}

final class PushOn extends PushWanted {
  const PushOn(this.config);

  final PushTaskConfig config;

  @override
  bool operator ==(Object other) => other is PushOn && other.config == config;

  @override
  int get hashCode => config.hashCode;
}

final pushWantedProvider = Provider<PushWanted>((ref) {
  if (ref.watch(demoModeProvider)) return PushWanted.unknown;
  final server = ref.watch(activeServerProvider);
  if (server == null) return PushWanted.unknown;
  if (!ref.watch(pushEnabledProvider)) return PushWanted.off;
  return PushOn(
    PushTaskConfig(
      server: server.toJson(),
      profile: ref.watch(activeProfileProvider),
      deviceId: ref.read(pushDeviceIdProvider),
    ),
  );
});

/// Read once by the app shell; does nothing off Android.
final pushHostProvider = Provider<PushHost>((ref) {
  final host = PushHost(ref);
  ref.onDispose(host.dispose);
  host.start();
  return host;
});

class PushHost {
  PushHost(this._ref);

  static const _log = IrisLog('push');

  final Ref _ref;
  PushWanted _applied = PushWanted.unknown;
  AppLifecycleListener? _lifecycle;
  bool _resumed = true;
  bool _started = false;

  /// The arbiter's push notice follows the state the service reports.
  ForegroundArbiter get _arbiter => foregroundArbiter;

  void start() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(_onData);
    } on Object catch (error) {
      _log.warn('service messages unavailable', data: error.runtimeType);
    }
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _ref
      ..listen<PushWanted>(
        pushWantedProvider,
        (_, next) => unawaited(_apply(next)),
        fireImmediately: true,
      )
      ..listen<String?>(foregroundChatProvider, (_, _) => _sendForeground());
    unawaited(_listenForTaps());
  }

  void dispose() {
    if (!_started) return;
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    _lifecycle?.dispose();
  }

  Future<void> _apply(PushWanted wanted) async {
    if (wanted is PushUnknown || wanted == _applied) return;
    _applied = wanted;
    switch (wanted) {
      case PushOn(:final config):
        await FlutterForegroundTask.saveData(
          key: PushTaskKeys.config,
          value: config.encode(),
        );
        // Registered again on every start: the server may have dropped the device, or its settings moved on.
        final controller = await _ref.read(pushControllerProvider.future);
        unawaited(controller?.sync());
        final state = _ref.read(pushConnectionProvider);
        await _arbiter.need(
          ServiceOwner.push,
          serviceNoticeFor(
            state == PushConnection.off ? PushConnection.connecting : state,
          ),
        );
        FlutterForegroundTask.sendDataToTask({PushTaskMessages.reload: true});
      case PushOff():
        await FlutterForegroundTask.removeData(key: PushTaskKeys.config);
        FlutterForegroundTask.sendDataToTask({PushTaskMessages.reload: true});
        await _arbiter.release(ServiceOwner.push);
        _ref.read(pushConnectionProvider.notifier).set(PushConnection.off);
      case PushUnknown():
        return;
    }
  }

  void _onData(Object data) {
    if (data is! Map) return;
    if (data[PushTaskMessages.hello] == true) {
      FlutterForegroundTask.sendDataToTask({
        PushTaskMessages.holder: (_arbiter.shown ?? ServiceOwner.push).name,
        PushTaskMessages.foreground: _foreground,
      });
    }
    final state = PushConnection.fromWire(data[PushTaskMessages.state]);
    if (state != null) {
      _ref.read(pushConnectionProvider.notifier).set(state);
      if (state != PushConnection.off) {
        _arbiter.remember(ServiceOwner.push, serviceNoticeFor(state));
      }
    }
  }

  /// The chat on screen, only while the app itself is.
  String? get _foreground =>
      _resumed ? _ref.read(foregroundChatProvider) : null;

  void _sendForeground() => FlutterForegroundTask.sendDataToTask({
    PushTaskMessages.foreground: _foreground,
  });

  void _onLifecycle(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    _sendForeground();
    if (resumed) unawaited(_arbiter.resumed());
  }

  Future<void> _listenForTaps() async {
    final plugin = FlutterLocalNotificationsPlugin();
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(LocalNotificationPoster.icon),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _open(tapFromResponse(response.payload, response.actionId)),
      );
      final launch = await plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        _open(tapFromResponse(response.payload, response.actionId));
      }
    } on Object catch (error) {
      _log.warn('notification taps unavailable', data: error.runtimeType);
    }
  }

  /// Opens [tap] once the app has a server and a screen to open it on (a cold start from a notification has neither
  /// at first).
  void _open(PushTap? tap) {
    if (tap == null) return;
    Future<void> attempt(int tries) async {
      final ready =
          _ref.read(activeServerProvider) != null &&
          irisNavigatorKey.currentState != null;
      if (ready) {
        await _ref.read(pushRouterProvider).open(tap);
      } else if (tries < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await attempt(tries + 1);
      } else {
        _log.warn('a notification tap found nothing to open');
      }
    }

    unawaited(attempt(0));
  }
}
