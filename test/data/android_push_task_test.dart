/// The Android service's notifications: one per event kind on its own channel, none for the chat on screen, two
/// buttons on an approval, and an approval answered elsewhere withdrawn.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/push/android_push_task.dart';
import 'package:iris/data/push/push_models.dart';
import 'package:iris/data/push/push_stream_client.dart';

final class _Poster implements NotificationPoster {
  final shown = <PostedNotice>[];
  final cancelled = <String>[];

  @override
  Future<void> show(PostedNotice notice) async => shown.add(notice);

  @override
  Future<void> cancel(String tag) async => cancelled.add(tag);
}

/// Posts after a delay and cancels at once, like the platform channel does.
final class _SlowPoster implements NotificationPoster {
  _SlowPoster(this.live);

  final Set<String> live;

  @override
  Future<void> show(PostedNotice notice) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    live.add(notice.tag);
  }

  @override
  Future<void> cancel(String tag) async => live.remove(tag);
}

PushNotice _notice({
  String kind = 'reply',
  String session = 's1',
  String? body = 'The tests pass.',
}) => PushNotice.fromJson({
  'event_id': '12',
  'kind': kind,
  'session_id': session,
  'title': 'Attention!',
  'body': body,
  'category': kind == 'approval' ? 'approval' : null,
  'collapse': '$kind-$session',
})!;

void main() {
  late _Poster poster;
  late PushNotifier notifier;

  setUp(() {
    poster = _Poster();
    notifier = PushNotifier(poster);
  });

  test(
    'a reply is posted on the replies channel with the person\'s words',
    () async {
      await notifier.handle(_notice());
      final posted = poster.shown.single;
      expect(posted.channel, PushChannel.reply);
      expect(posted.tag, 'reply-s1');
      expect(posted.title, 'Attention!');
      expect(posted.body, 'The tests pass.');
      expect(posted.actions, isEmpty);
      final payload = jsonDecode(posted.payload) as Map;
      expect(payload, {'kind': 'reply', 'session_id': 's1', 'event_id': '12'});
    },
  );

  test('each kind has its own channel', () async {
    await notifier.handle(
      _notice(kind: 'job', session: 'cron_a_20261113_0900'),
    );
    await notifier.handle(_notice(kind: 'approval'));
    expect(poster.shown.map((n) => n.channel), [
      PushChannel.job,
      PushChannel.approval,
    ]);
  });

  test(
    'approval notice has two actions, and names the command it showed',
    () async {
      await notifier.handle(_notice(kind: 'approval', body: 'rm -rf build'));
      final posted = poster.shown.single;
      expect(posted.actions.map((a) => a.id), ['once', 'deny']);
      expect(posted.actions.map((a) => a.label), ['Approve once', 'Deny']);
      final payload = jsonDecode(posted.payload) as Map;
      expect(payload['command'], 'rm -rf build');
    },
  );

  test('a text-mode notice carries no body and no command', () async {
    await notifier.handle(_notice(kind: 'approval', body: null));
    final posted = poster.shown.single;
    expect(posted.body, isNull);
    expect(jsonDecode(posted.payload) as Map, isNot(contains('command')));
  });

  test('approval_done cancels by collapse id', () async {
    await notifier.handle(
      PushNotice.fromJson({
        'event_id': '13',
        'kind': 'approval_done',
        'session_id': 's1',
        'collapse': 'approval-s1',
      })!,
    );
    expect(poster.cancelled, ['approval-s1']);
    expect(poster.shown, isEmpty);
  });

  test('a replayed approval and its approval_done leave nothing showing', () async {
    // show() takes longer than cancel(), as it does on the phone; handled back to back, as a reconnect replays them.
    final live = <String>{};
    final slow = _SlowPoster(live);
    final n = PushNotifier(slow);
    final approval = _notice(kind: 'approval', body: 'curl x | sh');
    final done = PushNotice.fromJson({
      'event_id': '13',
      'kind': 'approval_done',
      'session_id': 's1',
      'collapse': 'approval-s1',
    })!;
    final first = n.handle(approval);
    final second = n.handle(done);
    await Future.wait([first, second]);
    expect(live, isEmpty);
  });

  test('the chat on screen gets no notification; another chat does', () async {
    notifier.foregroundChat = 's1';
    await notifier.handle(_notice());
    await notifier.handle(_notice(kind: 'approval'));
    expect(poster.shown, isEmpty);

    await notifier.handle(_notice(session: 's2'));
    expect(poster.shown.single.tag, 'reply-s2');

    notifier.foregroundChat = null;
    await notifier.handle(_notice());
    expect(poster.shown, hasLength(2));
  });

  test('a kind Iris does not know is ignored', () async {
    await notifier.handle(_notice(kind: 'weather'));
    expect(poster.shown, isEmpty);
  });

  test('the connection notification says only what is true', () {
    expect(
      serviceNoticeFor(PushConnection.connected).title,
      'Iris is connected',
    );
    expect(
      serviceNoticeFor(PushConnection.unreachable).title,
      "Iris can't reach your server",
    );
    expect(
      serviceNoticeFor(PushConnection.connecting).title,
      'Iris is connecting',
    );
  });

  group('tapFromResponse', () {
    test('a plain tap opens the chat', () {
      final tap = tapFromResponse(
        jsonEncode({'kind': 'reply', 'session_id': 's1', 'event_id': '1'}),
        null,
      )!;
      expect(tap.kind, 'reply');
      expect(tap.sessionId, 's1');
      expect(tap.action, isNull);
    });

    test('a button adds its action; an unknown one is dropped', () {
      final payload = jsonEncode({
        'kind': 'approval',
        'session_id': 's1',
        'command': 'ls',
      });
      expect(tapFromResponse(payload, 'deny')!.action, 'deny');
      expect(tapFromResponse(payload, 'deny')!.command, 'ls');
      expect(tapFromResponse(payload, 'always')!.action, isNull);
    });

    test('a payload that is not ours opens nothing', () {
      expect(tapFromResponse(null, null), isNull);
      expect(tapFromResponse('not json', 'once'), isNull);
    });
  });

  group('PushTaskConfig', () {
    test('round-trips through its stored form', () {
      final config = PushTaskConfig.decode(
        const PushTaskConfig(
          server: {'id': 'srv', 'base_url': 'https://h.example', 'label': 'H'},
          profile: 'work',
          deviceId: 'abc',
        ).encode(),
      )!;
      expect(config.profile, 'work');
      expect(config.deviceId, 'abc');
      expect(config.serverConfig.baseUrl, 'https://h.example');
      expect(config.cursorKey, 'iris.push.cursor.srv/work');
    });

    test('damaged storage reads as nothing', () {
      expect(PushTaskConfig.decode(null), isNull);
      expect(PushTaskConfig.decode('{'), isNull);
      expect(PushTaskConfig.decode('{"profile":"x"}'), isNull);
    });
  });
}
