/// The optional weekly refinement: a Hermes cron job that asks the `iris-refine` skill to look at how displays were
/// used and *propose* changes. Off unless the person turns it on. Turning it off pauses the job and keeps it.
library;

import '../../core/result.dart';
import '../automation/cron_models.dart';
import '../automation/cron_repository.dart';

final class WeeklyRefine {
  WeeklyRefine(this._cron);

  final CronRepository _cron;

  /// How the job is found again; Iris owns this name.
  static const jobName = 'Iris: refine my displays';

  /// Mondays at 09:00, the server's time.
  static const schedule = '0 9 * * 1';

  static const prompt =
      'Refine my Iris displays. Use the iris-refine skill: read how my displays were used, then propose changes, '
      'new templates or retirements with the iris tools. Only propose; I approve in Iris. Reply with a short summary.';

  Future<Result<CronJob?>> _find() async => (await _cron.jobs()).map((jobs) {
    for (final job in jobs) {
      if (job.name == jobName) return job;
    }
    return null;
  });

  Future<Result<bool>> isOn() async =>
      (await _find()).map((job) => job != null && job.enabled);

  /// Makes the job exist and run ([on]) or pause. Returns what is now true.
  Future<Result<bool>> setOn({required bool on}) async {
    final found = await _find();
    if (found case Err(:final failure)) return Err(failure);
    final job = found.valueOrNull;
    if (on) {
      if (job == null) {
        final made = await _cron.create(
          const JobDraft(schedule: schedule, prompt: prompt, name: jobName),
        );
        return made.map((_) => true);
      }
      if (job.enabled) return const Ok(true);
      return (await _cron.setEnabled(job.id, enabled: true)).map((_) => true);
    }
    if (job == null || !job.enabled) return const Ok(false);
    return (await _cron.setEnabled(job.id, enabled: false)).map((_) => false);
  }
}
