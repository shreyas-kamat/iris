/// Home's Tasks tab: column chips, then the selected column's cards
/// (frames B1, B2).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../data/automation/kanban_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'task_actions.dart';
import 'task_card.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';

const double _barClearance = 130;

class TasksTab extends ConsumerStatefulWidget {
  const TasksTab({super.key});

  @override
  ConsumerState<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends ConsumerState<TasksTab> {
  /// The column the person picked; null follows the first that has cards.
  String? _picked;

  Future<void> _newTask(String column) async {
    await Navigator.of(context).push<bool>(
      IrisPageRoute<bool>(
        builder: (_) => TaskFormScreen(initialColumn: column),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gutter = context.window.gutter;
    final async = ref.watch(kanbanBoardProvider);
    final moves = ref.watch(taskMoveOverridesProvider);
    final now = ref.read(clockProvider)();
    final raw = async.value;

    if (raw == null) {
      if (async.hasError) {
        final error = async.error;
        return IrisEmptyState(
          title: 'Could not load tasks',
          message: error is IrisFailure
              ? error.message ?? error.kind.name
              : '$error',
          action: IrisButton(
            label: 'Try again',
            onPressed: () => ref.invalidate(kanbanBoardProvider),
          ),
        );
      }
      return ListView(
        padding: EdgeInsets.all(gutter),
        children: [
          for (var i = 0; i < 3; i++) ...[
            const IrisSkeleton(width: double.infinity, height: 84),
            const SizedBox(height: IrisSpace.sm),
          ],
        ],
      );
    }

    final board = withMoves(raw, moves);
    if (board.columns.isEmpty) {
      return IrisEmptyState(
        title: 'No tasks yet',
        message: 'Tasks you add, and ones Hermes creates, show up here.',
        icon: const IrisOrb(state: AgentState.idle, size: 72, glow: false),
        action: IrisButton(
          label: 'New task',
          tone: IrisButtonTone.primary,
          onPressed: () => unawaited(_newTask('triage')),
        ),
      );
    }

    final selected =
        board.column(_picked ?? '') ??
        board.columns.firstWhere(
          (column) => column.tasks.isNotEmpty,
          orElse: () => board.columns.first,
        );
    final systemSet = KanbanColumns.isSystemSet(selected.id);

    return RefreshIndicator(
      color: palette.accent,
      backgroundColor: palette.surfaceRaised,
      onRefresh: () async {
        ref.invalidate(kanbanBoardProvider);
        try {
          await ref.read(kanbanBoardProvider.future);
        } on Object {
          // The board shows its own error.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, IrisSpace.md, 0, _barClearance),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Row(
              children: [
                for (final column in board.columns) ...[
                  _ColumnChip(
                    label: column.label,
                    count: column.tasks.length,
                    selected: column.id == selected.id,
                    onTap: () {
                      unawaited(IrisHaptics.selection());
                      setState(() => _picked = column.id);
                    },
                  ),
                  const SizedBox(width: IrisSpace.sm),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              IrisSpace.lg,
              gutter,
              IrisSpace.sm,
            ),
            child: Row(
              children: [
                // Wraps rather than overflows beside the button on a narrow phone.
                Expanded(
                  child: IrisLabel(
                    systemSet
                        ? '${selected.label} · set by Hermes'
                        : '${selected.label} · ${selected.tasks.length}',
                  ),
                ),
                IrisButton(
                  label: 'New task',
                  tone: IrisButtonTone.ghost,
                  icon: const Icon(Icons.add),
                  onPressed: () => unawaited(_newTask(selected.id)),
                ),
              ],
            ),
          ),
          if (selected.tasks.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: IrisEmptyState(
                title: 'Nothing in ${selected.label}',
                message: systemSet
                    ? 'Hermes moves tasks here. You can’t add one yourself.'
                    : 'Tasks you move or add here show up in this column.',
                icon: const IrisOrb(
                  state: AgentState.idle,
                  size: 72,
                  glow: false,
                ),
                action: systemSet
                    ? null
                    : IrisButton(
                        label: 'New task',
                        tone: IrisButtonTone.primary,
                        onPressed: () => unawaited(_newTask(selected.id)),
                      ),
              ),
            )
          else
            for (final task in selected.tasks)
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.sm),
                child: TaskCard(
                  task: task,
                  now: now,
                  onOpen: () => unawaited(
                    Navigator.of(context).push(
                      IrisPageRoute<void>(
                        builder: (_) =>
                            TaskDetailScreen(taskId: task.id, initial: task),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ColumnChip extends StatelessWidget {
  const _ColumnChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: '$label, $count${selected ? ', selected' : ''}',
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: IrisSpace.md),
        decoration: BoxDecoration(
          color: selected ? palette.ink : palette.surface,
          borderRadius: const BorderRadius.all(IrisRadius.full),
          border: Border.all(
            color: selected ? palette.ink : palette.line,
            width: IrisStroke.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: type.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: selected ? palette.inkInverse : palette.inkMuted,
              ),
            ),
            const SizedBox(width: IrisSpace.xs + 2),
            Text(
              '$count',
              style: type.codeSmall.copyWith(
                fontSize: 11,
                color: (selected ? palette.inkInverse : palette.inkMuted)
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
