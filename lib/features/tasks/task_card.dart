/// One task on the board (frames B1, B1·B).
library;

import 'package:flutter/material.dart';

import '../../data/automation/kanban_models.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

/// "4m", "1h 12m": a run clock. Under a minute reads "<1m".
String elapsedText(DateTime startedAt, DateTime now) {
  final elapsed = now.difference(startedAt);
  if (elapsed.inMinutes < 1) return '<1m';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
  final minutes = elapsed.inMinutes % 60;
  return minutes == 0
      ? '${elapsed.inHours}h'
      : '${elapsed.inHours}h ${minutes}m';
}

/// `needs_input` as "needs input". The wording is the server's, not Iris's.
String blockKindText(String kind) => kind.replaceAll('_', ' ');

class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.now,
    required this.onOpen,
    super.key,
  });

  final KanbanTask task;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final started = task.startedAt;
    final blockKind = task.status == 'blocked' ? task.blockKind : null;
    final meta = type.codeSmall.copyWith(fontSize: 11, color: palette.inkFaint);
    return IrisPressable(
      onTap: onOpen,
      semanticLabel:
          '${task.title}, ${KanbanColumns.label(task.status)}'
          '${blockKind == null ? '' : ', ${blockKindText(blockKind)}'}',
      child: IrisCard(
        padding: const EdgeInsets.symmetric(
          horizontal: IrisSpace.lg,
          vertical: IrisSpace.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.running) ...[
                  const IrisOrb(state: AgentState.working, size: 22),
                  const SizedBox(width: IrisSpace.sm),
                ],
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                ),
                if (task.running && started != null) ...[
                  const SizedBox(width: IrisSpace.sm),
                  Text(
                    elapsedText(started, now),
                    style: type.codeSmall.copyWith(
                      color: palette.colorFor(AgentState.working),
                    ),
                  ),
                ],
              ],
            ),
            if (blockKind != null) ...[
              const SizedBox(height: IrisSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: blockKind == 'needs_input'
                    ? IrisChip.state(
                        blockKindText(blockKind),
                        AgentState.waiting,
                        palette,
                      )
                    : IrisChip(blockKindText(blockKind)),
              ),
            ],
            if (task.latestSummary case final summary?) ...[
              const SizedBox(height: IrisSpace.sm),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: palette.inkMuted),
              ),
            ],
            if (task.progress case final progress?) ...[
              const SizedBox(height: IrisSpace.xs),
              Text(
                '${progress.done} of ${progress.total} subtasks',
                style: type.caption.copyWith(color: palette.inkMuted),
              ),
            ],
            const SizedBox(height: IrisSpace.sm),
            Wrap(
              spacing: IrisSpace.md,
              runSpacing: IrisSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(task.id, style: meta),
                if (task.assignee case final who?) Text(who, style: meta),
                if (task.priority case final priority?)
                  Text('p$priority', style: meta),
                if (task.commentCount > 0)
                  Text(
                    '${task.commentCount} ${task.commentCount == 1 ? 'comment' : 'comments'}',
                    style: meta,
                  ),
                if (task.warningCount > 0)
                  Text(
                    '${task.warningCount} ${task.warningCount == 1 ? 'warning' : 'warnings'}',
                    style: meta.copyWith(
                      color: palette.colorFor(AgentState.waiting),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
