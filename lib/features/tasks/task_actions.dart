/// Moving a task: shown at once, rolled back if Hermes refuses.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../core/result.dart';
import '../../data/automation/kanban_models.dart';
import '../../design/components/toast.dart';
import '../automation_errors.dart';

Future<void> moveTask(
  BuildContext context,
  WidgetRef ref,
  KanbanTask task,
  String status,
) async {
  // Hermes owns these columns, and moving to where a task already is does
  // nothing.
  if (KanbanColumns.isSystemSet(status) || status == task.status) return;
  final overrides = ref.read(taskMoveOverridesProvider.notifier);
  overrides.set(task.id, status);
  final repository = await ref.read(kanbanRepositoryProvider.future);
  final result = await repository?.move(task.id, status);
  if (result case Err(:final failure)) {
    overrides.clear(task.id);
    if (context.mounted) {
      showIrisToast(context, message: describeWrite(failure), top: true);
    }
    return;
  }
  // Keep the move on screen until the board has caught up with it.
  ref
    ..invalidate(kanbanBoardProvider)
    ..invalidate(kanbanTaskDetailProvider(task.id));
  try {
    await ref.read(kanbanBoardProvider.future);
  } on Object {
    // A failed refresh is the board's own business.
  }
  overrides.clear(task.id);
}

/// [board] with every pending move applied.
KanbanBoard withMoves(KanbanBoard board, Map<String, String> moves) {
  var shown = board;
  for (final entry in moves.entries) {
    shown = shown.moved(entry.key, entry.value);
  }
  return shown;
}
