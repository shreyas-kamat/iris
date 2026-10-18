/// The words a job card and a job's detail use for when it runs.
library;

import '../../data/automation/cron_models.dart';
import '../chat/relative_time.dart';

enum JobStatus { running, paused, failed, active }

JobStatus statusOf(CronJob job) {
  if (job.running) return JobStatus.running;
  if (!job.enabled || job.state == CronState.paused) return JobStatus.paused;
  if (job.lastError != null) return JobStatus.failed;
  return JobStatus.active;
}

/// "42m", "9h 12m", "2d 4h". Never longer than two units.
String durationText(Duration duration) {
  if (duration.inMinutes < 1) return 'under a minute';
  if (duration.inHours < 1) return '${duration.inMinutes}m';
  if (duration.inDays < 1) {
    final minutes = duration.inMinutes % 60;
    return minutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${minutes}m';
  }
  final hours = duration.inHours % 24;
  return hours == 0
      ? '${duration.inDays}d'
      : '${duration.inDays}d ${hours}h';
}

/// The status line under a job's schedule.
String statusLine(CronJob job, DateTime now) {
  final next = job.nextRun;
  final nextText = next == null
      ? null
      : (next.isAfter(now)
            ? 'next in ${durationText(next.difference(now))}'
            : 'due now');
  switch (statusOf(job)) {
    case JobStatus.running:
      return 'running…';
    case JobStatus.paused:
      return 'paused';
    case JobStatus.failed:
      final last = job.lastRun;
      final failed = last == null ? 'failed' : 'failed ${relativeTime(last, now)}';
      return nextText == null ? failed : '$failed · $nextText';
    case JobStatus.active:
      return nextText ?? '';
  }
}
