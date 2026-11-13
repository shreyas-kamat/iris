/// Reading a notification's payload into what a tap should do.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/push/push_intents.dart';

void main() {
  group('PushTap.fromPayload', () {
    test('reads a flat payload (Android)', () {
      final tap = PushTap.fromPayload({
        'kind': 'approval',
        'session_id': '20261113_101500_ab12cd',
        'event_id': 'e7',
        'action': 'once',
        'command': 'rm -rf build',
      });
      expect(tap, isNotNull);
      expect(tap!.kind, 'approval');
      expect(tap.sessionId, '20261113_101500_ab12cd');
      expect(tap.eventId, 'e7');
      expect(tap.action, 'once');
      expect(tap.command, 'rm -rf build');
    });

    test('reads the `iris` block of an APNs payload (iOS)', () {
      final tap = PushTap.fromPayload({
        'aps': {'alert': 'x'},
        'iris': {'kind': 'reply', 'session_id': 's1', 'event_id': 'e1'},
      });
      expect(tap!.kind, 'reply');
      expect(tap.sessionId, 's1');
      expect(tap.action, isNull);
    });

    test('a tap without an action just opens', () {
      final tap = PushTap.fromPayload({'kind': 'reply', 'session_id': 's1'});
      expect(tap!.action, isNull);
      expect(tap.eventId, isNull);
    });

    test('an action other than once or deny is dropped, not trusted', () {
      final tap = PushTap.fromPayload({
        'kind': 'approval',
        'session_id': 's1',
        'action': 'always',
      });
      expect(tap!.action, isNull);
    });

    test('a missing kind or session gives nothing to open', () {
      expect(PushTap.fromPayload({'session_id': 's1'}), isNull);
      expect(PushTap.fromPayload({'kind': 'reply'}), isNull);
      expect(PushTap.fromPayload({'kind': '', 'session_id': 's1'}), isNull);
      expect(PushTap.fromPayload({'kind': 'reply', 'session_id': ' '}), isNull);
      expect(PushTap.fromPayload(const {}), isNull);
    });

    test('fields of the wrong type are ignored', () {
      final tap = PushTap.fromPayload({
        'kind': 'reply',
        'session_id': 's1',
        'event_id': 5,
        'action': ['once'],
      });
      expect(tap!.eventId, isNull);
      expect(tap.action, isNull);
    });

    test('an unknown kind is kept; the router decides what to do', () {
      expect(
        PushTap.fromPayload({'kind': 'test', 'session_id': 's1'})!.kind,
        'test',
      );
    });
  });

  group('PushTap.fromJsonString', () {
    test('reads the payload string a local notification carries', () {
      final tap = PushTap.fromJsonString(
        '{"kind":"job","session_id":"cron_abc_20261113_0900","event_id":"e2"}',
      );
      expect(tap!.kind, 'job');
      expect(tap.jobId, 'abc');
    });

    test('anything that is not a JSON object gives nothing', () {
      expect(PushTap.fromJsonString(null), isNull);
      expect(PushTap.fromJsonString(''), isNull);
      expect(PushTap.fromJsonString('not json'), isNull);
      expect(PushTap.fromJsonString('[1]'), isNull);
    });
  });

  group('jobId', () {
    test('comes from a cron session id', () {
      const tap = PushTap(
        kind: 'job',
        sessionId: 'cron_a1b2c3d4e5f6_20261113_090000',
      );
      expect(tap.jobId, 'a1b2c3d4e5f6');
    });

    test('is null for an ordinary chat', () {
      const tap = PushTap(kind: 'reply', sessionId: '20261113_101500_ab12cd');
      expect(tap.jobId, isNull);
    });
  });
}
