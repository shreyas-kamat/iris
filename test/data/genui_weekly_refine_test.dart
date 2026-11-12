/// The optional weekly refinement: one cron job on the person's profile, off unless they turn it on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/genui/weekly_refine.dart';

import '../support/fake_automation.dart';

void main() {
  late FakeCronRepository cron;
  late WeeklyRefine weekly;

  setUp(() {
    cron = FakeCronRepository();
    weekly = WeeklyRefine(cron);
  });

  CronJob ours({bool enabled = true}) => fakeJob(
    'w1',
    name: WeeklyRefine.jobName,
    enabled: enabled,
    state: enabled ? CronState.active : CronState.paused,
  );

  test(
    'it is off when no such job exists, and nothing is created by asking',
    () async {
      cron.jobsResult = Ok([fakeJob('other', name: 'Morning brief')]);
      expect((await weekly.isOn()).valueOrNull, isFalse);
      expect(cron.calls, ['jobs']);
    },
  );

  test('it is on when the job exists and is enabled', () async {
    cron.jobsResult = Ok([fakeJob('other'), ours()]);
    expect((await weekly.isOn()).valueOrNull, isTrue);
  });

  test('a paused job counts as off', () async {
    cron.jobsResult = Ok([ours(enabled: false)]);
    expect((await weekly.isOn()).valueOrNull, isFalse);
  });

  test('turning it on creates a weekly job that names the skill', () async {
    final result = await weekly.setOn(on: true);
    expect(result.valueOrNull, isTrue);
    expect(cron.calls, ['jobs', 'create']);
    final draft = cron.drafts.single;
    expect(draft.name, WeeklyRefine.jobName);
    expect(draft.schedule, '0 9 * * 1');
    expect(draft.prompt, contains('iris-refine'));
    expect(draft.prompt, contains('propose'));
    expect(draft.deliver, isNull);
  });

  test(
    'turning it on resumes a paused job instead of making a second',
    () async {
      cron.jobsResult = Ok([ours(enabled: false)]);
      expect((await weekly.setOn(on: true)).valueOrNull, isTrue);
      expect(cron.calls, ['jobs', 'setEnabled w1 true']);
    },
  );

  test('turning it on when it is already on does nothing more', () async {
    cron.jobsResult = Ok([ours()]);
    expect((await weekly.setOn(on: true)).valueOrNull, isTrue);
    expect(cron.calls, ['jobs']);
  });

  test('turning it off pauses the job and keeps it', () async {
    cron.jobsResult = Ok([ours()]);
    expect((await weekly.setOn(on: false)).valueOrNull, isFalse);
    expect(cron.calls, ['jobs', 'setEnabled w1 false']);
  });

  test('turning it off with no job does nothing', () async {
    expect((await weekly.setOn(on: false)).valueOrNull, isFalse);
    expect(cron.calls, ['jobs']);
  });

  test('a failure is returned, not thrown', () async {
    cron.jobsResult = const Err(
      IrisFailure(FailureKind.offline, message: 'down'),
    );
    expect((await weekly.isOn()).isErr, isTrue);
    expect((await weekly.setOn(on: true)).isErr, isTrue);
    expect(cron.calls.where((c) => c == 'create'), isEmpty);

    cron.jobsResult = const Ok([]);
    cron.writeResult = const Err(
      IrisFailure(FailureKind.offline, message: 'down'),
    );
    expect((await weekly.setOn(on: true)).isErr, isTrue);
  });
}
