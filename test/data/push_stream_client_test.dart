/// The Android push stream: SSE frames off the wire, the cursor it resumes from, signing in again after a 401, and
/// the backoff between attempts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/push/push_models.dart';
import 'package:iris/data/push/push_stream_client.dart';

Stream<List<int>> _bytes(List<String> chunks) =>
    Stream.fromIterable([for (final c in chunks) utf8.encode(c)]);

String _notice(String id, {String kind = 'reply', String session = 's1'}) =>
    'id: $id\nevent: notice\ndata: ${jsonEncode({'event_id': id, 'kind': kind, 'session_id': session, 'title': 'Attention!', 'body': null, 'category': null, 'collapse': '$kind-$session'})}\n\n';

/// Answers each `open` with the next scripted opening; once the script runs out, the server is unreachable.
final class _Transport implements PushStreamTransport {
  _Transport(this.script);

  final List<StreamOpening Function()> script;
  final afters = <String?>[];
  var signIns = 0;
  bool signInWorks = true;

  @override
  Future<StreamOpening> open({String? after}) async {
    afters.add(after);
    if (script.isEmpty) return const StreamRefused(null);
    return script.removeAt(0)();
  }

  @override
  Future<bool> signIn() async {
    signIns++;
    return signInWorks;
  }
}

final class _Rig {
  _Rig(this.transport, {String? cursor, this.stopAfterSleeps = 3}) {
    client = PushStreamClient(
      transport: transport,
      cursor: cursor,
      onCursor: cursors.add,
      onNotice: notices.add,
      onState: states.add,
      sleep: (d) async {
        sleeps.add(d);
        if (sleeps.length >= stopAfterSleeps) client.stop();
      },
      idleTimeout: const Duration(milliseconds: 200),
    );
  }

  final _Transport transport;
  final int stopAfterSleeps;
  late final PushStreamClient client;
  final cursors = <String>[];
  final notices = <PushNotice>[];
  final states = <PushConnection>[];
  final sleeps = <Duration>[];

  Future<void> run() => client.run().timeout(const Duration(seconds: 5));
}

void main() {
  group('decodeSse', () {
    test('reads a real HTTP body, a stream of Uint8List', () async {
      final body = Stream<Uint8List>.fromIterable([
        Uint8List.fromList(utf8.encode('id: 1\nevent: notice\ndata: x\n\n')),
      ]);
      final frames = await decodeSse(body).toList();
      expect(frames, hasLength(1));
    });

    test('joins multi-line data, keeps the id and the event name', () async {
      final frames = await decodeSse(
        _bytes(['id: 7\nevent: notice\ndata: one\ndata: two\n\n']),
      ).toList();
      expect(frames, hasLength(1));
      final event = frames.single as SseEvent;
      expect(event.id, '7');
      expect(event.event, 'notice');
      expect(event.data, 'one\ntwo');
    });

    test('reports comments and ignores unknown fields', () async {
      final frames = await decodeSse(
        _bytes([': ping\n\n', 'retry: 10\nfoo: bar\ndata: x\n\n']),
      ).toList();
      expect(frames.first, isA<SseComment>());
      final event = frames.last as SseEvent;
      expect(event.data, 'x');
      expect(event.event, 'message');
    });

    test('handles CRLF, a frame split across chunks, and emoji', () async {
      final frames = await decodeSse(
        _bytes(['id: 1\r\nda', 'ta: hé 🎉\r\n', '\r\n']),
      ).toList();
      final event = frames.whereType<SseEvent>().single;
      expect(event.id, '1');
      expect(event.data, 'hé 🎉');
    });

    test('a field with no colon is a name with an empty value', () async {
      final frames = await decodeSse(_bytes(['data\n\n'])).toList();
      expect((frames.single as SseEvent).data, '');
    });

    test('a frame with no data dispatches nothing', () async {
      final frames = await decodeSse(_bytes(['id: 3\n\n'])).toList();
      expect(frames.whereType<SseEvent>(), isEmpty);
    });
  });

  group('PushStreamClient', () {
    test(
      'resumes from the stored cursor and moves it after each notice',
      () async {
        final transport = _Transport([
          () => StreamOpened(_bytes([_notice('5'), _notice('6')])),
          () => StreamOpened(_bytes([_notice('7')])),
        ]);
        final rig = _Rig(transport, cursor: 'c0', stopAfterSleeps: 1);
        await rig.run();

        expect(transport.afters.take(2), ['c0', '6']);
        expect(rig.cursors, ['5', '6', '7']);
        expect(rig.notices.map((n) => n.eventId), ['5', '6', '7']);
        expect(rig.notices.first.kind, 'reply');
        expect(rig.notices.first.sessionId, 's1');
      },
    );

    test('a brand-new client sends no cursor', () async {
      final transport = _Transport([]);
      final rig = _Rig(transport, stopAfterSleeps: 1);
      await rig.run();
      expect(transport.afters.first, isNull);
    });

    test('reconnects after a 401 by logging in again', () async {
      final transport = _Transport([
        () => const StreamRefused(401),
        () => StreamOpened(_bytes([_notice('9')])),
      ]);
      final rig = _Rig(transport, stopAfterSleeps: 1);
      await rig.run();

      expect(transport.signIns, 1);
      expect(rig.notices.single.eventId, '9');
      // Signing in again is not a failure the person needs to see.
      expect(rig.states.take(2), [
        PushConnection.connecting,
        PushConnection.connected,
      ]);
    });

    test('a login that is refused backs off as unreachable', () async {
      final transport = _Transport([
        () => const StreamRefused(401),
        () => const StreamRefused(401),
      ])..signInWorks = false;
      final rig = _Rig(transport, stopAfterSleeps: 1);
      await rig.run();

      expect(transport.signIns, 1);
      expect(rig.states.last, PushConnection.unreachable);
      expect(rig.sleeps.single, const Duration(seconds: 2));
    });

    test('backoff doubles from 2 s and caps at 60 s', () async {
      final rig = _Rig(_Transport([]), stopAfterSleeps: 8);
      await rig.run();
      expect(rig.sleeps.map((d) => d.inSeconds), [2, 4, 8, 16, 32, 60, 60, 60]);
      expect(PushStreamClient.backoff(40), const Duration(seconds: 60));
    });

    test('says unreachable only while it cannot connect', () async {
      final transport = _Transport([
        () => const StreamRefused(null),
        () => const StreamRefused(502),
        () => StreamOpened(_bytes([': ping\n\n'])),
      ]);
      final rig = _Rig(transport);
      await rig.run();
      expect(rig.states.take(3), [
        PushConnection.connecting,
        PushConnection.unreachable,
        PushConnection.connected,
      ]);
    });

    test(
      'a stream that drops is reopened at once, and the backoff resets',
      () async {
        final transport = _Transport([
          () => const StreamRefused(null),
          () => StreamOpened(_bytes([_notice('1')])),
          () => StreamOpened(_bytes([_notice('2')])),
        ]);
        final rig = _Rig(transport, stopAfterSleeps: 2);
        await rig.run();
        // 2 s after the first failure; none between the two good streams; 2 s again once the script runs out.
        expect(rig.sleeps.map((d) => d.inSeconds), [2, 2]);
        expect(transport.afters.take(3), [null, null, '1']);
      },
    );

    test('a silent stream is treated as dead and reopened', () async {
      final silent = StreamController<List<int>>();
      addTearDown(silent.close);
      final transport = _Transport([
        () => StreamOpened(silent.stream),
        () => StreamOpened(_bytes([_notice('4')])),
      ]);
      // The silent stream delivered nothing, so it costs one backoff before the next attempt.
      final rig = _Rig(transport, stopAfterSleeps: 2);
      await rig.run();
      expect(rig.notices.single.eventId, '4');
    });

    test('a 404 (device not registered) waits the longest backoff', () async {
      final rig = _Rig(
        _Transport([() => const StreamRefused(404)]),
        stopAfterSleeps: 1,
      );
      await rig.run();
      expect(rig.sleeps.single, const Duration(seconds: 60));
      expect(rig.states.last, PushConnection.unreachable);
    });

    test(
      'a frame that is not a notice is skipped, the cursor still moves',
      () async {
        final transport = _Transport([
          () => StreamOpened(_bytes(['id: 3\nevent: notice\ndata: {nope\n\n'])),
        ]);
        final rig = _Rig(transport, stopAfterSleeps: 1);
        await rig.run();
        expect(rig.notices, isEmpty);
        expect(rig.cursors, ['3']);
      },
    );

    test('stop ends a stream that is open', () async {
      final open = StreamController<List<int>>();
      addTearDown(open.close);
      final transport = _Transport([() => StreamOpened(open.stream)]);
      final rig = _Rig(transport);
      final running = rig.client.run();
      await pumpEventQueue();
      rig.client.stop();
      await running.timeout(const Duration(seconds: 2));
      expect(transport.afters, hasLength(1));
    });
  });
}
