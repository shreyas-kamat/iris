/// Scheduled agent runs — the Tasks panel.
library;

import '../../core/json.dart';

/// Whether a job is scheduled, paused, or currently executing.
enum CronState {
  active,
  paused,
  running,
  failed,
  unknown;

  static CronState parse(String? value, {bool? paused}) {
    switch (value?.trim().toLowerCase()) {
      case 'running' || 'executing' || 'in_progress':
        return CronState.running;
      case 'paused' || 'disabled' || 'inactive' || 'stopped':
        return CronState.paused;
      case 'failed' || 'error':
        return CronState.failed;
      case 'active' || 'enabled' || 'scheduled' || 'ok' || 'idle':
        return CronState.active;
    }
    if (paused != null) return paused ? CronState.paused : CronState.active;
    return CronState.unknown;
  }
}

/// A cron job registered on the agent.
final class CronJob {
  const CronJob({
    required this.id,
    required this.name,
    required this.schedule,
    required this.state,
    this.prompt,
    this.model,
    this.deliver,
    this.skills = const [],
    this.lastRun,
    this.nextRun,
    this.lastStatus,
  });

  /// Returns `null` when the row has no id — nothing can be run or deleted
  /// without one, so it is dropped rather than shown as a dead entry.
  static CronJob? fromJsonOrNull(Json json) {
    final id = json.any(['id', 'job_id', 'name']).stringOrNull;
    if (id == null || id.isEmpty) return null;
    return CronJob(
      id: id,
      name: json.any(['name', 'title', 'id']).string(id),
      schedule: json.any(['schedule', 'cron', 'expression']).string(),
      state: CronState.parse(
        json.any(['status', 'state']).stringOrNull,
        paused: json.any(['paused', 'disabled']).boolOrNull,
      ),
      prompt: json.any(['prompt', 'command', 'task']).stringOrNull,
      model: json['model'].stringOrNull,
      deliver: json.any(['deliver', 'delivery', 'notify']).stringOrNull,
      skills: json['skills'].list
          .map((skill) => skill.string())
          .where((skill) => skill.isNotEmpty)
          .toList(growable: false),
      lastRun: json.any(['last_run', 'last_run_at', 'lastRun']).dateTimeOrNull,
      nextRun: json.any(['next_run', 'next_run_at', 'nextRun']).dateTimeOrNull,
      lastStatus: json.any(['last_status', 'result']).stringOrNull,
    );
  }

  final String id;
  final String name;

  /// The raw cron expression. Iris shows it verbatim alongside a human reading
  /// rather than replacing it, because an approximate translation of someone's
  /// schedule is worse than no translation.
  final String schedule;
  final CronState state;
  final String? prompt;
  final String? model;
  final String? deliver;
  final List<String> skills;
  final DateTime? lastRun;
  final DateTime? nextRun;
  final String? lastStatus;
}

/// One captured output from a past run.
final class CronOutput {
  const CronOutput({required this.filename, required this.content, this.at});

  static CronOutput? fromJsonOrNull(Json json) {
    final filename = json.any(['filename', 'file', 'name']).stringOrNull;
    if (filename == null || filename.isEmpty) return null;
    return CronOutput(
      filename: filename,
      content: json.any(['content', 'output', 'text']).string(),
      at: json.any(['at', 'timestamp', 'created_at', 'mtime']).dateTimeOrNull,
    );
  }

  final String filename;
  final String content;
  final DateTime? at;
}
