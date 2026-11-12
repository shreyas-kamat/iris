/// What the person did with a display (used, expanded, dismissed, not useful): sent to the plugin in small batches,
/// best effort, and never in the way of the chat.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/genui/genui_api.dart';
import 'package:iris/data/genui/signals.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_genui_api.dart';
import '../support/fake_http.dart';

void main() {
  group('sendSignals', () {
    late FakeHttp http;
    setUp(() => http = FakeHttp());

    DashboardGenUiApi api() {
      final connection = ServerConnection.create(
        const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
        adapter: http,
      );
      addTearDown(connection.close);
      return DashboardGenUiApi(connection.client);
    }

    test('posts the batch with only ids and the signal name', () async {
      http.on(
        'POST',
        '/api/plugins/iris/feedback',
        (_) => FakeReply.json({'ok': true, 'accepted': 2}),
      );
      final sent = await api().sendSignals(const [
        SignalEvent(
          DisplaySignal.used,
          surface: 's1',
          template: 'deploy',
          session: 'sess',
        ),
        SignalEvent(DisplaySignal.notUseful, surface: 's2'),
      ]);
      expect(sent.isOk, isTrue);
      expect(http.requests.single.data, {
        'signals': [
          {
            'signal': 'used',
            'surface': 's1',
            'template': 'deploy',
            'session': 'sess',
          },
          {'signal': 'not_useful', 'surface': 's2'},
        ],
      });
    });

    test('a refusal comes back as a failure, not a throw', () async {
      http.on(
        'POST',
        '/api/plugins/iris/feedback',
        (_) => FakeReply.json({
          'ok': false,
          'errors': ['nope'],
        }, status: 422),
      );
      final sent = await api().sendSignals(const [
        SignalEvent(DisplaySignal.used, surface: 's1'),
      ]);
      expect(sent, isA<Err<void>>());
    });
  });

  group('SignalReporter', () {
    late FakeGenUiApi fake;
    late SignalReporter reporter;

    setUp(() {
      fake = FakeGenUiApi();
      reporter = SignalReporter(api: () async => fake);
      addTearDown(reporter.dispose);
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('waits for ten signals before sending', (tester) async {
      for (var i = 0; i < 9; i++) {
        reporter.record(DisplaySignal.expanded, surface: 's$i');
      }
      await settle(tester);
      expect(fake.signalBatches, isEmpty);

      reporter.record(DisplaySignal.expanded, surface: 's9');
      await settle(tester);
      expect(fake.signalBatches, hasLength(1));
      expect(fake.signalBatches.single, hasLength(10));
    });

    testWidgets('sends what is queued after twenty seconds', (tester) async {
      reporter.record(DisplaySignal.dismissed, surface: 's1', session: 'a');
      await tester.pump(const Duration(seconds: 19));
      expect(fake.signalBatches, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      expect(fake.signalBatches, hasLength(1));
      expect(fake.signalBatches.single.single.signal, DisplaySignal.dismissed);
      expect(fake.signalBatches.single.single.session, 'a');
    });

    testWidgets('has no timer running while nothing is queued', (tester) async {
      reporter.record(DisplaySignal.dismissed, surface: 's1');
      await tester.pump(const Duration(seconds: 21));
      // The test ends without a pending timer: the harness would fail it otherwise.
      expect(fake.signalBatches, hasLength(1));
    });

    testWidgets('a surface is "used" once per session', (tester) async {
      reporter.record(DisplaySignal.used, surface: 's1', session: 'a');
      reporter.record(DisplaySignal.used, surface: 's1', session: 'a');
      reporter.record(DisplaySignal.used, surface: 's1', session: 'b');
      reporter.record(DisplaySignal.expanded, surface: 's1', session: 'a');
      reporter.record(DisplaySignal.expanded, surface: 's1', session: 'a');
      await reporter.flush();
      final sent = fake.signalBatches.single;
      expect(sent.map((e) => e.signal.wire), [
        'used',
        'used',
        'expanded',
        'expanded',
      ]);
    });

    testWidgets('drops a batch the server refused and carries on', (
      tester,
    ) async {
      fake.signalResult = const Err(IrisFailure(FailureKind.rejected));
      reporter.record(DisplaySignal.expanded, surface: 's1');
      await reporter.flush();
      expect(fake.signalBatches, hasLength(1));

      fake.signalResult = const Ok(null);
      reporter.record(DisplaySignal.expanded, surface: 's2');
      await reporter.flush();
      expect(fake.signalBatches, hasLength(2));
      expect(fake.signalBatches.last.single.surface, 's2');
    });

    testWidgets('never throws, even when the api throws or is missing', (
      tester,
    ) async {
      final throwing = SignalReporter(api: () async => throw StateError('x'));
      addTearDown(throwing.dispose);
      throwing.record(DisplaySignal.expanded, surface: 's1');
      await throwing.flush();

      final missing = SignalReporter(api: () async => null);
      addTearDown(missing.dispose);
      missing.record(DisplaySignal.expanded, surface: 's1');
      await missing.flush();
    });

    testWidgets('sends what is left when it is closed', (tester) async {
      reporter.record(DisplaySignal.expanded, surface: 's1');
      reporter.dispose();
      await settle(tester);
      expect(fake.signalBatches, hasLength(1));
      // Recording after that does nothing.
      reporter.record(DisplaySignal.expanded, surface: 's2');
      await settle(tester);
      expect(fake.signalBatches, hasLength(1));
    });
  });
}
