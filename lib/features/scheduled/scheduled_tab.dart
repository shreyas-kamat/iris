/// Home's Scheduled tab (frames A2, A3).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../data/automation/cron_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'job_actions.dart';
import 'job_card.dart';
import 'job_detail_screen.dart';
import 'job_form_screen.dart';

/// The floating Ask bar plus its fade: the list's last card scrolls clear of it.
const double _barClearance = 130;

class ScheduledTab extends ConsumerWidget {
  const ScheduledTab({super.key});

  Future<void> _newJob(BuildContext context, WidgetRef ref) async {
    final saved = await Navigator.of(context).push<CronJob>(
      IrisPageRoute<CronJob>(builder: (_) => const JobFormScreen()),
    );
    if (saved != null) ref.invalidate(cronJobsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final gutter = context.window.gutter;
    final jobs = ref.watch(cronJobsProvider);
    final overrides = ref.watch(cronEnabledOverridesProvider);
    final profile = ref.watch(activeProfileProvider);
    final now = ref.read(clockProvider)();
    final list = jobs.value;

    if (list == null) {
      if (jobs.hasError) {
        final error = jobs.error;
        return IrisEmptyState(
          title: 'Could not load scheduled jobs',
          message: error is IrisFailure
              ? error.message ?? error.kind.name
              : '$error',
          action: IrisButton(
            label: 'Try again',
            onPressed: () => ref.invalidate(cronJobsProvider),
          ),
        );
      }
      return ListView(
        padding: EdgeInsets.all(gutter),
        children: [
          for (var i = 0; i < 4; i++) ...[
            const IrisSkeleton(width: double.infinity, height: 72),
            const SizedBox(height: IrisSpace.sm),
          ],
        ],
      );
    }

    if (list.isEmpty) {
      return IrisEmptyState(
        title: 'No scheduled jobs on $profile',
        message: 'Jobs run a prompt on a schedule and keep each run as a chat.',
        icon: const IrisOrb(state: AgentState.idle, size: 72, glow: false),
        action: IrisButton(
          label: 'New job',
          tone: IrisButtonTone.primary,
          onPressed: () => unawaited(_newJob(context, ref)),
        ),
      );
    }

    return RefreshIndicator(
      color: palette.accent,
      backgroundColor: palette.surfaceRaised,
      onRefresh: () async {
        ref.invalidate(cronJobsProvider);
        try {
          await ref.read(cronJobsProvider.future);
        } on Object {
          // The list shows its own error.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.md, gutter, _barClearance),
        children: [
          Row(
            children: [
              IrisLabel('${list.length} ${list.length == 1 ? 'job' : 'jobs'}'),
              if (jobs.isLoading) ...[
                const SizedBox(width: IrisSpace.sm),
                const IrisOrb(state: AgentState.loading, size: 16),
                const SizedBox(width: IrisSpace.xs),
                const IrisLabel('Refreshing', small: true),
              ],
              const Spacer(),
              IrisButton(
                label: 'New job',
                tone: IrisButtonTone.ghost,
                icon: const Icon(Icons.add),
                onPressed: () => unawaited(_newJob(context, ref)),
              ),
            ],
          ),
          const SizedBox(height: IrisSpace.sm),
          for (final raw in list) ...[
            Builder(
              builder: (context) {
                final job = withOverride(raw, overrides);
                return JobCard(
                  job: job,
                  now: now,
                  onToggle: (enabled) =>
                      unawaited(toggleJob(context, ref, raw, enabled)),
                  onOpen: () => unawaited(
                    Navigator.of(context).push(
                      IrisPageRoute<void>(
                        builder: (_) => JobDetailScreen(initial: raw),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: IrisSpace.sm),
          ],
        ],
      ),
    );
  }
}
