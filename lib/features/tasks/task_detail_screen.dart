/// One task: what it is, how it went, and where it can go (frame B3).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../data/automation/kanban_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/markdown.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../chat/chat_screen.dart';
import '../chat/relative_time.dart';
import 'move_sheet.dart';
import 'task_actions.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.taskId, this.initial, super.key});

  final String taskId;

  /// The card the person tapped, drawn while the detail loads.
  final KanbanTask? initial;

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    KanbanTask task,
  ) async {
    final columns =
        ref
            .read(kanbanBoardProvider)
            .value
            ?.columns
            .map((c) => c.id)
            .toList() ??
        const [
          'triage',
          'todo',
          'ready',
          'running',
          'blocked',
          'review',
          'done',
        ];
    final picked = await showMoveSheet(context, task: task, columns: columns);
    if (picked == null || !context.mounted) return;
    await moveTask(context, ref, task, picked);
  }

  Future<void> _openSession(
    BuildContext context,
    WidgetRef ref,
    KanbanTask task,
  ) async {
    final chat = await ref.read(activeChatProvider.future);
    if (chat == null || !context.mounted) return;
    await Navigator.of(context).push(
      IrisPageRoute<void>(
        builder: (_) => ChatScreen(
          backend: chat,
          conversationId: task.sessionId,
          title: task.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    final detail = ref.watch(kanbanTaskDetailProvider(taskId));
    final moves = ref.watch(taskMoveOverridesProvider);
    final now = ref.read(clockProvider)();
    final loaded = detail.value;
    var task = loaded?.task ?? initial;
    if (task != null && moves.containsKey(task.id)) {
      task = task.copyWith(status: moves[task.id]);
    }
    final failed = palette.colorFor(AgentState.failed);

    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.sm,
          gutter,
          IrisSpace.sm,
        ),
        child: Row(
          children: [
            IrisCircleButton(
              icon: Icons.arrow_back_ios_new,
              semanticLabel: 'Back',
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
            const SizedBox(width: IrisSpace.md),
            Text(taskId, style: type.code.copyWith(color: palette.inkMuted)),
            const SizedBox(width: IrisSpace.sm),
            if (task != null) IrisChip(KanbanColumns.label(task.status)),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.md,
          gutter,
          IrisSpace.xxl,
        ),
        children: [
          if (task == null)
            const IrisSkeleton(width: 220, height: 20)
          else ...[
            Text(task.title, style: type.title.copyWith(color: palette.ink)),
            const SizedBox(height: IrisSpace.sm),
            Wrap(
              spacing: IrisSpace.md,
              children: [
                if (task.assignee case final who?)
                  Text(
                    who,
                    style: type.codeSmall.copyWith(color: palette.inkMuted),
                  ),
                if (task.priority case final priority?)
                  Text(
                    'priority $priority',
                    style: type.codeSmall.copyWith(color: palette.inkMuted),
                  ),
              ],
            ),
          ],
          if (detail.hasError && loaded == null) ...[
            const SizedBox(height: IrisSpace.lg),
            Text(
              'Could not load this task',
              style: type.body.copyWith(color: palette.inkMuted),
            ),
          ],
          if (loaded != null) ...[
            for (final parent in loaded.parents) ...[
              const SizedBox(height: IrisSpace.md),
              IrisPressable(
                onTap: () => unawaited(
                  Navigator.of(context).push(
                    IrisPageRoute<void>(
                      builder: (_) => TaskDetailScreen(taskId: parent.id),
                    ),
                  ),
                ),
                child: Text(
                  'Parent · ${parent.id} ${parent.title}',
                  style: type.caption.copyWith(color: palette.accent),
                ),
              ),
            ],
            if (loaded.task.body case final body?) ...[
              const SizedBox(height: IrisSpace.lg),
              IrisMarkdown(body),
            ],
            if (loaded.task.latestSummary case final summary?) ...[
              const SizedBox(height: IrisSpace.lg),
              IrisLabel('Latest summary', color: palette.inkFaint),
              const SizedBox(height: IrisSpace.xs),
              Text(summary, style: type.body.copyWith(color: palette.ink)),
            ],
            if (loaded.result case final result?) ...[
              const SizedBox(height: IrisSpace.lg),
              IrisLabel('Result', color: palette.inkFaint),
              const SizedBox(height: IrisSpace.xs),
              IrisMarkdown(result),
            ],
            if (loaded.lastFailure case final failure?) ...[
              const SizedBox(height: IrisSpace.lg),
              IrisCard(
                accent: failed,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IrisLabel('Last failure', color: failed),
                    const SizedBox(height: IrisSpace.xs),
                    Text(
                      failure,
                      style: type.body.copyWith(color: palette.ink),
                    ),
                  ],
                ),
              ),
            ],
            if (loaded.children.isNotEmpty) ...[
              const SizedBox(height: IrisSpace.xl),
              IrisSettingsGroup(
                title: 'Subtasks · ${loaded.children.length}',
                children: [
                  for (final child in loaded.children)
                    IrisSettingsRow(
                      label: child.title,
                      sub: child.id,
                      value: child.status == null
                          ? null
                          : KanbanColumns.label(child.status!),
                      onTap: () => unawaited(
                        Navigator.of(context).push(
                          IrisPageRoute<void>(
                            builder: (_) => TaskDetailScreen(taskId: child.id),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (loaded.comments.isNotEmpty) ...[
              const SizedBox(height: IrisSpace.xl),
              IrisLabel(
                'Comments · ${loaded.comments.length}',
                color: palette.inkFaint,
              ),
              const SizedBox(height: IrisSpace.sm),
              for (final comment in loaded.comments) ...[
                Row(
                  children: [
                    Text(
                      comment.author,
                      style: type.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    if (comment.at case final at?) ...[
                      const SizedBox(width: IrisSpace.sm),
                      Text(
                        relativeTime(at, now),
                        style: type.caption.copyWith(color: palette.inkFaint),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.body,
                  style: type.body.copyWith(color: palette.ink),
                ),
                const SizedBox(height: IrisSpace.md),
              ],
            ],
            if (loaded.runs.isNotEmpty) ...[
              const SizedBox(height: IrisSpace.lg),
              IrisSettingsGroup(
                title: 'Runs · ${loaded.runs.length}',
                children: [
                  for (final run in loaded.runs)
                    IrisSettingsRow(
                      label: run.startedAt == null
                          ? 'Run'
                          : _clock(run.startedAt!, run.endedAt),
                      value: run.outcome,
                    ),
                ],
              ),
            ],
          ],
          if (task != null) ...[
            const SizedBox(height: IrisSpace.xl),
            IrisButton(
              label: 'Move',
              expand: true,
              onPressed: () => unawaited(_move(context, ref, task!)),
            ),
            if (task.sessionId != null) ...[
              const SizedBox(height: IrisSpace.sm),
              IrisButton(
                label: 'Open session',
                tone: IrisButtonTone.primary,
                expand: true,
                onPressed: () => unawaited(_openSession(context, ref, task!)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _clock(DateTime start, DateTime? end) {
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return end == null ? hm(start) : '${hm(start)} → ${hm(end)}';
  }
}
