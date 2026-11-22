/// The Android foreground service's own isolate: it holds the push stream open, posts each notice as a notification,
/// and passes the call notification's buttons back to the app.
///
/// It runs without the app's UI, after the app is swiped away and after a reboot, so it reads everything it needs
/// itself: the server and device from the service's stored data ([PushTaskConfig]), the login from the keystore. The
/// app tells it which chat is on screen (no notification for that one) and whether a call holds the notification.
///
/// Taps are not handled here: a notification opens the app's activity, and the app's own isolate reads the tap
/// (`tapFromResponse`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/json.dart';
import '../../core/logging.dart';
import '../net/credentials.dart';
import '../net/server_config.dart';
import '../net/server_connection.dart';
import 'foreground_arbiter.dart';
import 'push_intents.dart';
import 'push_models.dart';
import 'push_stream_client.dart';

/// Keys in the service's stored data (`FlutterForegroundTask.saveData`).
abstract final class PushTaskKeys {
  /// The [PushTaskConfig] while push is on; absent while it is off.
  static const config = 'iris.push.config';
}

/// Messages between the app and the service isolate.
abstract final class PushTaskMessages {
  /// Service → app: the service isolate started and wants the holder and the foreground chat.
  static const hello = 'hello';

  /// Service → app: the stream's [PushConnection], by name.
  static const state = 'push_state';

  /// App → service: `push` or `call`, whoever's notification is shown.
  static const holder = 'holder';

  /// App → service: the stored id of the chat on screen, or null.
  static const foreground = 'foreground';

  /// App → service: the config changed (or was removed); start or stop the stream accordingly.
  static const reload = 'reload';

  /// Android (`MainActivity.onDestroy`) → service: the app's engine, and any call in it, is gone.
  static const appGone = 'app_gone';
}

/// What the service needs to reach the server on its own. No secrets: the login stays in the keystore.
@immutable
final class PushTaskConfig {
  const PushTaskConfig({
    required this.server,
    required this.profile,
    required this.deviceId,
  });

  /// [ServerConfig.toJson].
  final Map<String, Object?> server;
  final String profile;
  final String deviceId;

  ServerConfig get serverConfig => ServerConfig.fromJson(Json.of(server));

  /// Where the stream's cursor is kept: per server and profile, so a switch does not replay another's events.
  String get cursorKey => 'iris.push.cursor.${server['id']}/$profile';

  String encode() =>
      jsonEncode({'server': server, 'profile': profile, 'device_id': deviceId});

  static PushTaskConfig? decode(String? stored) {
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored);
      if (json is! Map) return null;
      final server = json['server'];
      final profile = json['profile'];
      final device = json['device_id'];
      if (server is! Map || profile is! String || device is! String) {
        return null;
      }
      if (server['id'] is! String || server['base_url'] is! String) {
        return null;
      }
      return PushTaskConfig(
        server: server.cast<String, Object?>(),
        profile: profile,
        deviceId: device,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PushTaskConfig && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// The permanent notification's words for the stream's state.
ServiceNotice serviceNoticeFor(PushConnection state) => switch (state) {
  PushConnection.connected => const ServiceNotice(
    title: 'Iris is connected',
    text: 'Waiting for replies, approvals and jobs',
  ),
  PushConnection.unreachable => const ServiceNotice(
    title: "Iris can't reach your server",
    text: 'Notifications are paused until it can',
  ),
  PushConnection.connecting || PushConnection.off => const ServiceNotice(
    title: 'Iris is connecting',
    text: 'To your server, for notifications',
  ),
};

/// A tap on a notification posted here, as the app reads it: [payload] is the JSON this service attached, [actionId]
/// the button pressed (null for the notification itself).
PushTap? tapFromResponse(String? payload, String? actionId) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    return PushTap.fromPayload({
      ...decoded.cast<String, Object?>(),
      'action': ?actionId,
    });
  } on FormatException {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Notifications

enum PushChannel {
  reply('iris_reply', 'Replies', 'A reply in a chat you are waiting on.'),
  approval(
    'iris_approval',
    'Approvals',
    'Hermes is waiting for you to approve something.',
  ),
  job('iris_job', 'Scheduled jobs', 'A scheduled job finished.'),

  /// The service's own notification. Created by the service plugin, low importance: it never makes a sound.
  connection(
    'iris_connection',
    'Connection',
    'Shown while Iris stays connected for notifications.',
  );

  const PushChannel(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static PushChannel? forKind(String kind) => switch (kind) {
    'reply' || 'test' => reply,
    'approval' => approval,
    'job' => job,
    _ => null,
  };
}

@immutable
final class PostedAction {
  const PostedAction(this.id, this.label);

  final String id;
  final String label;
}

/// One notification to post. [tag] is the notice's collapse id: a later one with the same tag replaces it.
@immutable
final class PostedNotice {
  const PostedNotice({
    required this.tag,
    required this.channel,
    required this.title,
    required this.body,
    required this.payload,
    this.actions = const [],
  });

  final String tag;
  final PushChannel channel;
  final String title;
  final String? body;

  /// JSON the app reads back on a tap ([tapFromResponse]).
  final String payload;
  final List<PostedAction> actions;
}

abstract interface class NotificationPoster {
  Future<void> show(PostedNotice notice);
  Future<void> cancel(String tag);
}

/// Turns the stream's notices into notifications.
final class PushNotifier {
  PushNotifier(this._poster);

  static const _log = IrisLog('push.notify');

  final NotificationPoster _poster;

  /// The stored id of the chat on screen, sent from the app. Its notices are not shown: the person is looking at it.
  String? foregroundChat;

  Future<void> _last = Future<void>.value();

  /// One notice at a time, in the order they arrived: a post and a cancel for the same tag race on the platform
  /// channel otherwise, and a reconnect replays an approval and its withdrawal back to back.
  Future<void> handle(PushNotice notice) {
    final next = _last.then((_) => _handle(notice));
    _last = next.catchError((Object error) {
      _log.warn('a notice failed', data: error.runtimeType);
    });
    return next;
  }

  Future<void> _handle(PushNotice notice) async {
    final tag = notice.collapse ?? '${notice.kind}-${notice.sessionId}';
    if (notice.kind == 'approval_done') {
      await _poster.cancel(notice.collapse ?? 'approval-${notice.sessionId}');
      return;
    }
    final channel = PushChannel.forKind(notice.kind);
    if (channel == null) return;
    if (foregroundChat != null && foregroundChat == notice.sessionId) {
      _log.debug('notice for the chat on screen not shown');
      return;
    }
    final approval = notice.kind == 'approval';
    try {
      await _poster.show(
        PostedNotice(
          tag: tag,
          channel: channel,
          title: notice.title ?? PushEventSettings.defaultText,
          body: notice.body,
          payload: jsonEncode({
            'kind': notice.kind,
            'session_id': notice.sessionId,
            'event_id': notice.eventId,
            // What the notification showed, to pick the right approval when two are waiting.
            if (approval) 'command': ?notice.body,
          }),
          actions: approval
              ? const [
                  PostedAction('once', 'Approve once'),
                  PostedAction('deny', 'Deny'),
                ]
              : const [],
        ),
      );
    } on Object catch (error) {
      _log.warn('could not post a notification', data: error.runtimeType);
    }
  }
}

/// [NotificationPoster] over flutter_local_notifications. Android only.
final class LocalNotificationPoster implements NotificationPoster {
  LocalNotificationPoster([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// One id for every push notification; the tag tells them apart (Android keys a notification by tag and id).
  static const _id = 7300;

  static const icon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(icon),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channel in PushChannel.values) {
      if (channel == PushChannel.connection) continue;
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channel.id,
          channel.label,
          description: channel.description,
          importance: channel == PushChannel.approval
              ? Importance.high
              : Importance.defaultImportance,
        ),
      );
    }
  }

  @override
  Future<void> show(PostedNotice notice) => _plugin.show(
    id: _id,
    title: notice.title,
    body: notice.body,
    payload: notice.payload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        notice.channel.id,
        notice.channel.label,
        channelDescription: notice.channel.description,
        importance: notice.channel == PushChannel.approval
            ? Importance.high
            : Importance.defaultImportance,
        priority: notice.channel == PushChannel.approval
            ? Priority.high
            : Priority.defaultPriority,
        tag: notice.tag,
        styleInformation: notice.body == null
            ? null
            : BigTextStyleInformation(notice.body!),
        // Opening the app asks for the unlock first, so an approval is never answered from the lock screen.
        actions: [
          for (final action in notice.actions)
            AndroidNotificationAction(
              action.id,
              action.label,
              showsUserInterface: true,
            ),
        ],
        // The lock screen shows that Iris has something, not what it is.
        visibility: NotificationVisibility.private,
      ),
    ),
  );

  @override
  Future<void> cancel(String tag) => _plugin.cancel(id: _id, tag: tag);
}

// ---------------------------------------------------------------------------------------------------------------
// The service isolate

/// The service's entry point, for both owners: the call (buttons) and push (stream).
@pragma('vm:entry-point')
void startIrisServiceTask() =>
    FlutterForegroundTask.setTaskHandler(IrisServiceTask());

final class IrisServiceTask extends TaskHandler {
  static const _log = IrisLog('push.service');

  final _poster = LocalNotificationPoster();
  late final _notifier = PushNotifier(_poster);
  bool _posterReady = false;

  PushTaskConfig? _config;
  ServerConnection? _connection;
  PushStreamClient? _client;
  PushConnection _state = PushConnection.off;

  /// Whose notification is up. Push's unless the app says a call holds it; with the app gone there is no call.
  String _holder = 'push';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _reload();
    FlutterForegroundTask.sendDataToMain({PushTaskMessages.hello: true});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopStream();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    if (data.containsKey(PushTaskMessages.foreground)) {
      final chat = data[PushTaskMessages.foreground];
      _notifier.foregroundChat = chat is String ? chat : null;
    }
    final holder = data[PushTaskMessages.holder];
    if (holder is String && holder != _holder) {
      _holder = holder;
      if (_holder == 'push' && _client != null) unawaited(_showState());
    }
    if (data[PushTaskMessages.reload] == true) unawaited(_reload());
    if (data[PushTaskMessages.appGone] == true) unawaited(_appGone());
  }

  /// A call cannot outlive the app; push can. With push off the service has no reason left to run.
  Future<void> _appGone() async {
    _notifier.foregroundChat = null;
    if (_config == null) {
      await FlutterForegroundTask.stopService();
      return;
    }
    if (_holder != 'push') {
      _holder = 'push';
      await _showState();
    }
  }

  @override
  void onNotificationButtonPressed(String id) =>
      FlutterForegroundTask.sendDataToMain(id);

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  Future<void> _reload() async {
    final config = PushTaskConfig.decode(
      await FlutterForegroundTask.getData<String>(key: PushTaskKeys.config),
    );
    if (config == _config && _client != null) {
      // The app asks for a reload on every start and has just put "connecting" on the notification (it does not know
      // better yet); say again what is true.
      if (_holder == 'push' && _state != PushConnection.off) {
        unawaited(_showState());
      }
      FlutterForegroundTask.sendDataToMain({
        PushTaskMessages.state: _state.name,
      });
      return;
    }
    _stopStream();
    _config = config;
    if (config == null) {
      _setState(PushConnection.off);
      return;
    }
    if (!_posterReady) {
      try {
        await _poster.init();
        _posterReady = true;
      } on Object catch (error) {
        _log.warn('notifications unavailable', data: error.runtimeType);
      }
    }
    final server = config.serverConfig;
    final secrets =
        (await CredentialStore.platform().read(server.id)).valueOrNull ??
        ServerSecrets.none;
    final connection = _connection = ServerConnection.create(
      server,
      secrets: secrets,
    );
    final client = _client = PushStreamClient(
      transport: DashboardPushStreamTransport(
        connection,
        deviceId: config.deviceId,
        profile: config.profile,
      ),
      cursor: await FlutterForegroundTask.getData<String>(
        key: config.cursorKey,
      ),
      onCursor: (cursor) => unawaited(
        FlutterForegroundTask.saveData(key: config.cursorKey, value: cursor),
      ),
      onNotice: (notice) => unawaited(_notifier.handle(notice)),
      onState: _setState,
    );
    unawaited(client.run());
  }

  void _stopStream() {
    _client?.stop();
    _client = null;
    _connection?.close();
    _connection = null;
  }

  void _setState(PushConnection state) {
    _state = state;
    FlutterForegroundTask.sendDataToMain({PushTaskMessages.state: state.name});
    if (_holder == 'push' && state != PushConnection.off) {
      unawaited(_showState());
    }
  }

  Future<void> _showState() async {
    final notice = serviceNoticeFor(_state);
    await FlutterForegroundTask.updateService(
      notificationTitle: notice.title,
      notificationText: notice.text,
      notificationButtons: const [],
    );
  }
}
