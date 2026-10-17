/// What a person can do to a job from a card or its detail.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../core/result.dart';
import '../../data/automation/cron_models.dart';
import '../../design/components/toast.dart';
import '../automation_errors.dart';

/// Pauses or resumes [job]. The switch changes at once; if Hermes refuses, it
/// changes back and a toast says why.
Future<void> toggleJob(
  BuildContext context,
  WidgetRef ref,
  CronJob job,
  // ignore: avoid_positional_boolean_parameters
  bool enabled,
) async {
  final overrides = ref.read(cronEnabledOverridesProvider.notifier);
  overrides.set(job.id, enabled);
  final repository = await ref.read(cronRepositoryProvider.future);
  final result = await repository?.setEnabled(job.id, enabled: enabled);
  if (result case Err(:final failure)) {
    overrides.clear(job.id);
    if (context.mounted) {
      showIrisToast(context, message: describeWrite(failure), top: true);
    }
    return;
  }
  // Keep the optimistic value until the list has caught up, so the switch does
  // not flick back for a poll.
  ref.invalidate(cronJobsProvider);
  try {
    await ref.read(cronJobsProvider.future);
  } on Object {
    // A failed refresh is the list's own business.
  }
  overrides.clear(job.id);
}

/// [job] with any pending pause or resume applied.
CronJob withOverride(CronJob job, Map<String, bool> overrides) =>
    overrides.containsKey(job.id)
    ? job.copyWith(enabled: overrides[job.id])
    : job;
