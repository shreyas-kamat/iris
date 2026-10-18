/// One job: its state, its prompt, and what can be done to it (frame A4).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/automation/cron_models.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../automation_errors.dart';
import '../chat/chat_screen.dart';
import '../chat/delete_sheet.dart';
import '../chat/relative_time.dart';
import 'job_actions.dart';
import 'job_form_screen.dart';
import 'schedule_text.dart';

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({required this.initial, super.key});

  final CronJob initial;

  Future<void> _run(BuildContext context, WidgetRef ref, CronJob job) async {
    final repository = await ref.read(cronRepositoryProvider.future);
    final result = await repository?.trigger(job.id);
    if (!context.mounted) return;
    if (result case Err(:final failure)) {
      showIrisToast(context, message: describeWrite(failure), top: true);
      return;
    }
    showIrisToast(context, message: 'Started', top: true);
    ref
      ..invalidate(cronJobsProvider)
      ..invalidate(cronRunsProvider(job.id));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CronJob job) async {
    final saved = await Navigator.of(context).push<CronJob>(
      IrisPageRoute<CronJob>(builder: (_) => JobFormScreen(job: job)),
    );
    if (saved == null) return;
    ref.invalidate(cronJobsProvider);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, CronJob job) async {
    final confirmed = await showDeleteSheet(
      context,
      job.title,
      message:
          'This removes the job from Hermes for good. Chats from past runs stay.',
    );
    if (!confirmed || !context.mounted) return;
    final repository = await ref.read(cronRepositoryProvider.future);
    final result = await repository?.delete(job.id);
    if (!context.mounted) return;
    if (result case Err(:final failure)) {
      showIrisToast(context, message: describeWrite(failure), top: true);
      return;
    }
    ref.invalidate(cronJobsProvider);
    Navigator.of(context).pop();
    showIrisToast(context, message: 'Deleted ‘${job.title}’');
  }

  Future<void> _openRun(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary run,
  ) async {
    final chat = await ref.read(activeChatProvider.future);
    if (chat == null || !context.mounted) return;
    await Navigator.of(context).push(
      IrisPageRoute<void>(
        builder: (_) => ChatScreen(
          backend: chat,
          conversationId: run.id,
          title: run.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    final overrides = ref.watch(cronEnabledOverridesProvider);
    final fromList = ref
        .watch(cronJobsProvider)
        .value
        ?.where((j) => j.id == initial.id)
        .firstOrNull;
    final job = withOverride(fromList ?? initial, overrides);
    final now = ref.read(clockProvider)();
    final runs = ref.watch(cronRunsProvider(job.id));
    final failed = palette.colorFor(AgentState.failed);
    final line = statusLine(job, now);

    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.sm),
        child: Row(
          children: [
            IrisCircleButton(
              icon: Icons.arrow_back_ios_new,
              semanticLabel: 'Back',
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
            const SizedBox(width: IrisSpace.md),
            Expanded(
              child: Text(
                job.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.heading.copyWith(color: palette.ink),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.md, gutter, IrisSpace.xxl),
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceSunken,
                  borderRadius: const BorderRadius.all(IrisRadius.xs),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IrisSpace.sm,
                    vertical: 3,
                  ),
                  child: Text(
                    job.scheduleText,
                    style: type.codeSmall.copyWith(color: palette.inkMuted),
                  ),
                ),
              ),
              const SizedBox(width: IrisSpace.sm),
              Expanded(
                child: Text(
                  line,
                  style: type.caption.copyWith(
                    color: statusOf(job) == JobStatus.failed
                        ? failed
                        : palette.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: IrisSpace.lg),
          IrisSettingsGroup(
            title: 'Status',
            children: [
              IrisSettingsRow(
                label: 'Enabled',
                trailing: IrisSwitch(
                  value: job.enabled,
                  semanticLabel: 'Enabled',
                  onChanged: (enabled) =>
                      unawaited(toggleJob(context, ref, fromList ?? initial, enabled)),
                ),
              ),
            ],
          ),
          if (job.lastError case final error?) ...[
            const SizedBox(height: IrisSpace.lg),
            IrisCard(
              accent: failed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IrisLabel('Last error', color: failed),
                  const SizedBox(height: IrisSpace.xs),
                  Text(error, style: type.body.copyWith(color: palette.ink)),
                ],
              ),
            ),
          ],
          if (job.prompt case final prompt?) ...[
            const SizedBox(height: IrisSpace.lg),
            IrisLabel('Prompt', color: palette.inkFaint),
            const SizedBox(height: IrisSpace.xs),
            Text(prompt, style: type.body.copyWith(color: palette.ink)),
          ],
          if (job.model != null || job.deliver != null) ...[
            const SizedBox(height: IrisSpace.lg),
            IrisSettingsGroup(
              title: 'Run with',
              children: [
                if (job.model case final model?)
                  IrisSettingsRow(label: 'Model', value: model),
                if (job.deliver case final deliver?)
                  IrisSettingsRow(label: 'Delivers to', value: deliver),
              ],
            ),
          ],
          const SizedBox(height: IrisSpace.xl),
          IrisButton(
            label: 'Run now',
            tone: IrisButtonTone.primary,
            expand: true,
            onPressed: () => unawaited(_run(context, ref, job)),
          ),
          const SizedBox(height: IrisSpace.sm),
          IrisButton(
            label: 'Edit',
            expand: true,
            onPressed: () => unawaited(_edit(context, ref, job)),
          ),
          const SizedBox(height: IrisSpace.sm),
          IrisButton(
            label: 'Delete',
            tone: IrisButtonTone.danger,
            expand: true,
            onPressed: () => unawaited(_delete(context, ref, job)),
          ),
          const SizedBox(height: IrisSpace.xl),
          IrisLabel('Past runs', color: palette.inkFaint),
          const SizedBox(height: IrisSpace.sm),
          switch (runs) {
            AsyncData(:final value) when value.isEmpty => Text(
              'No runs yet. Run now starts one.',
              style: type.body.copyWith(color: palette.inkMuted),
            ),
            AsyncData(:final value) => IrisSettingsGroup(
              title: 'Newest first',
              children: [
                for (final run in value)
                  IrisSettingsRow(
                    label: run.title,
                    sub: run.startedAt == null
                        ? null
                        : relativeTime(run.startedAt!, now),
                    onTap: () => unawaited(_openRun(context, ref, run)),
                  ),
              ],
            ),
            AsyncError() => Text(
              "Couldn't load past runs.",
              style: type.body.copyWith(color: palette.inkMuted),
            ),
            _ => const IrisSkeleton(width: 220, height: 16),
          },
        ],
      ),
    );
  }
}
