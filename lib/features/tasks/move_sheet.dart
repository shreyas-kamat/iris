/// Choosing a column to move a task to (frame B4).
library;

import 'package:flutter/material.dart';

import '../../data/automation/kanban_models.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

/// The chosen column id, or null when the sheet was dismissed or the current
/// column was tapped. Columns Hermes sets itself are shown but do not respond.
Future<String?> showMoveSheet(
  BuildContext context, {
  required KanbanTask task,
  required List<String> columns,
}) => showIrisSheet<String>(
  context: context,
  builder: (sheetContext) {
    final palette = sheetContext.palette;
    return IrisSheet(
      title: 'Move ${task.id}',
      subtitle: task.title,
      child: Column(
        children: [
          for (final id in columns)
            Builder(
              builder: (context) {
                final locked = KanbanColumns.isSystemSet(id);
                final current = id == task.status;
                return Opacity(
                  opacity: locked ? 0.55 : 1,
                  child: IrisListRow(
                    title: KanbanColumns.label(id),
                    subtitle: locked ? 'Set by Hermes' : null,
                    selected: current,
                    leading: locked
                        ? Icon(
                            Icons.lock_outline,
                            size: IrisSize.iconSmall,
                            color: palette.inkMuted,
                          )
                        : null,
                    onTap: locked
                        ? null
                        : () => Navigator.of(
                            sheetContext,
                          ).pop(current ? null : id),
                  ),
                );
              },
            ),
        ],
      ),
    );
  },
);
