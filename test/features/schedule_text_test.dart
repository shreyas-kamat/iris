import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/features/scheduled/schedule_text.dart';

import '../support/fake_automation.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);

  group('durationText', () {
    test('minutes, hours with minutes, days with hours', () {
      expect(durationText(const Duration(seconds: 20)), 'under a minute');
      expect(durationText(const Duration(minutes: 42)), '42m');
      expect(durationText(const Duration(hours: 9, minutes: 12)), '9h 12m');
      expect(durationText(const Duration(hours: 3)), '3h');
      expect(durationText(const Duration(days: 2, hours: 4)), '2d 4h');
    });
  });

  group('statusOf', () {
    test('running beats everything', () {
      expect(
        statusOf(fakeJob('a', state: CronState.running, lastError: 'x')),
        JobStatus.running,
      );
    });

    test('paused beats failed', () {
      expect(
        statusOf(fakeJob('a', enabled: false, lastError: 'x')),
        JobStatus.paused,
      );
    });

    test('a last error on an enabled job is failed', () {
      expect(statusOf(fakeJob('a', lastError: 'boom')), JobStatus.failed);
    });

    test('otherwise active', () {
      expect(statusOf(fakeJob('a')), JobStatus.active);
    });
  });

  group('statusLine', () {
    test('next run', () {
      expect(
        statusLine(
          fakeJob('a', nextRun: now.add(const Duration(hours: 9, minutes: 12))),
          now,
        ),
        'next in 9h 12m',
      );
    });

    test('paused', () {
      expect(statusLine(fakeJob('a', enabled: false), now), 'paused');
    });

    test('running', () {
      expect(
        statusLine(fakeJob('a', state: CronState.running), now),
        'running…',
      );
    });

    test('failed names when, and the next run if known', () {
      expect(
        statusLine(
          fakeJob(
            'a',
            lastError: 'boom',
            lastRun: now.subtract(const Duration(hours: 2)),
            nextRun: now.add(const Duration(hours: 21, minutes: 40)),
          ),
          now,
        ),
        'failed 2h ago · next in 21h 40m',
      );
    });

    test('failed with no last run still says failed', () {
      expect(statusLine(fakeJob('a', lastError: 'boom'), now), 'failed');
    });

    test('a next run already past reads as due', () {
      expect(
        statusLine(
          fakeJob('a', nextRun: now.subtract(const Duration(minutes: 5))),
          now,
        ),
        'due now',
      );
    });

    test('no next run is an empty line, not a crash', () {
      expect(statusLine(fakeJob('a'), now), '');
    });
  });
}
