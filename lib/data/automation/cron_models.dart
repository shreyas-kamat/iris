/// Scheduled agent runs: the jobs on a profile.
library;

import '../../core/json.dart';

/// Whether a job is scheduled, paused, or currently executing.
enum CronState {
  active,
  paused,
  running,
  failed,
  unknown;

  static CronState parse(String? value, {bool? enabled}) {
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
    if (enabled != null) {
      return enabled ? CronState.active : CronState.paused;
    }
    return CronState.unknown;
  }
}

/// A cron job registered on a profile.
final class CronJob {
  const CronJob({
    required this.id,
    required this.schedule,
    required this.enabled,
    required this.state,
    this.name,
    this.prompt,
    this.scheduleDisplay,
    this.model,
    this.provider,
    this.deliver,
    this.nextRun,
    this.lastRun,
    this.lastError,
  });

  /// Returns `null` when the row has no id: nothing can be paused or deleted
  /// without one, so it is dropped rather than shown as a dead card.
  static CronJob? fromJsonOrNull(Json json) {
    final id = json.any(['id', 'job_id']).stringOrNull;
    if (id == null || id.isEmpty) return null;
    final schedule = json['schedule'];
    final String expr;
    final String? display;
    if (schedule.isMap) {
      expr = schedule['expr'].string();
      display = schedule['display'].stringOrNull;
    } else {
      expr = schedule.string(json['cron'].string());
      display = null;
    }
    final enabled = json['enabled'].boolOrNull;
    final lastError = json['last_error'].stringOrNull;
    return CronJob(
      id: id,
      name: _clean(json['name'].stringOrNull),
      prompt: _clean(json['prompt'].stringOrNull),
      schedule: expr,
      scheduleDisplay: _clean(display ?? json['schedule_display'].stringOrNull),
      enabled: enabled ?? true,
      state: CronState.parse(json['state'].stringOrNull, enabled: enabled),
      model: _clean(json['model'].stringOrNull),
      provider: _clean(json['provider'].stringOrNull),
      deliver: _clean(json['deliver'].stringOrNull),
      nextRun: json['next_run_at'].dateTimeOrNull,
      lastRun: json['last_run_at'].dateTimeOrNull,
      lastError: _clean(lastError),
    );
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final String id;
  final String? name;
  final String? prompt;

  /// The raw cron expression, or whatever text the server stores.
  final String schedule;

  /// Hermes's own reading of the schedule ("every monday 9am"), when sent.
  final String? scheduleDisplay;
  final bool enabled;
  final CronState state;
  final String? model;
  final String? provider;
  final String? deliver;
  final DateTime? nextRun;
  final DateTime? lastRun;
  final String? lastError;

  /// The name, else the first line of the prompt, else the id.
  String get title {
    if (name case final name?) return name;
    final first = prompt?.split('\n').first.trim();
    return first == null || first.isEmpty ? id : first;
  }

  /// What the schedule chip shows: Hermes's reading if it sent one, else the
  /// expression, verbatim. Iris never translates a schedule itself.
  String get scheduleText => scheduleDisplay ?? schedule;

  bool get running => state == CronState.running;

  CronJob copyWith({bool? enabled}) => CronJob(
    id: id,
    name: name,
    prompt: prompt,
    schedule: schedule,
    scheduleDisplay: scheduleDisplay,
    enabled: enabled ?? this.enabled,
    state: enabled == null
        ? state
        : (enabled ? CronState.active : CronState.paused),
    model: model,
    provider: provider,
    deliver: deliver,
    nextRun: nextRun,
    lastRun: lastRun,
    lastError: lastError,
  );
}

/// What the job form sends. [model], [provider] and [deliver] are absent when
/// the person left them on the profile's defaults.
final class JobDraft {
  const JobDraft({
    required this.schedule,
    required this.prompt,
    this.name,
    this.model,
    this.provider,
    this.deliver,
  });

  final String schedule;
  final String prompt;
  final String? name;
  final String? model;
  final String? provider;
  final String? deliver;

  Map<String, Object?> toCreateBody() => {
    'schedule': schedule.trim(),
    'prompt': prompt.trim(),
    if (_present(name)) 'name': name!.trim(),
    if (_present(model)) 'model': model!.trim(),
    if (_present(provider)) 'provider': provider!.trim(),
    if (_present(deliver)) 'deliver': deliver!.trim(),
  };

  /// An update sends every field, with `''` for one that was cleared, so
  /// "Profile default" and "Nowhere" really reset what was set before. Not
  /// `null`: `ApiClient` drops null fields, and Hermes keeps a field the body
  /// leaves out. Hermes reads `''` as unset (a cleared `deliver` as `local`).
  Map<String, Object?> toUpdateBody() => {
    'schedule': schedule.trim(),
    'prompt': prompt.trim(),
    'name': _present(name) ? name!.trim() : '',
    'model': _present(model) ? model!.trim() : '',
    'provider': _present(provider) ? provider!.trim() : '',
    'deliver': _present(deliver) ? deliver!.trim() : '',
  };

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;
}

/// Where a job's reply can be sent.
final class DeliveryTarget {
  const DeliveryTarget({required this.id, required this.name});

  static DeliveryTarget? fromJsonOrNull(Json json) {
    final id = json['id'].stringOrNull;
    if (id == null || id.isEmpty) return null;
    return DeliveryTarget(id: id, name: json['name'].string(id));
  }

  final String id;
  final String name;
}
