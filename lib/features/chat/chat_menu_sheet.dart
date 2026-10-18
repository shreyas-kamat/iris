/// The chat header's ⋯ menu (frames C1, C1·B).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

enum ChatMenuAction {
  rename,
  pin,
  branch,
  archive,
  compress,
  undo,
  export,
  info,
  delete,
}

/// The chosen action, or null when dismissed. Rows that rewrite history are
/// dimmed with a reason while the agent replies, not hidden.
Future<ChatMenuAction?> showChatMenu(
  BuildContext context, {
  required String title,
  required bool pinned,
  required bool replying,
  required bool live,
  required bool canPin,
  required bool canArchive,
  required bool canDelete,
  required bool canUndo,
}) {
  unawaited(IrisHaptics.selection());
  return showIrisSheet<ChatMenuAction>(
    context: context,
    builder: (sheetContext) {
      final palette = sheetContext.palette;

      Widget row(
        ChatMenuAction action,
        String label,
        IconData icon, {
        String? disabledReason,
        bool danger = false,
      }) {
        final enabled = disabledReason == null;
        final tint = danger
            ? palette.colorFor(AgentState.failed)
            : palette.inkMuted;
        return Opacity(
          opacity: enabled ? 1 : 0.55,
          child: IrisListRow(
            title: label,
            subtitle: disabledReason,
            leading: Icon(
              icon,
              size: IrisSize.icon,
              color: enabled ? tint : palette.inkFaint,
            ),
            onTap: enabled
                ? () => Navigator.of(sheetContext).pop(action)
                : null,
          ),
        );
      }

      String? needsIdle() => replying ? 'Stop the reply first' : null;
      String? needsLive() => replying
          ? 'Stop the reply first'
          : (live ? null : 'Not connected yet');

      Widget group(String name, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: IrisSpace.md,
              bottom: IrisSpace.xs,
            ),
            child: IrisLabel(name, color: palette.inkFaint),
          ),
          ...rows,
        ],
      );

      return IrisSheet(
        title: title,
        child: Column(
          children: [
            group('Conversation', [
              row(ChatMenuAction.rename, 'Rename', Icons.edit_outlined),
              if (canPin)
                row(
                  ChatMenuAction.pin,
                  pinned ? 'Unpin' : 'Pin',
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
              row(
                ChatMenuAction.branch,
                'Branch',
                Icons.call_split,
                disabledReason: needsIdle(),
              ),
              if (canArchive)
                row(
                  ChatMenuAction.archive,
                  'Archive',
                  Icons.archive_outlined,
                  disabledReason: needsIdle(),
                ),
            ]),
            group('Context', [
              row(
                ChatMenuAction.compress,
                'Compress',
                Icons.compress,
                disabledReason: needsLive(),
              ),
              row(
                ChatMenuAction.undo,
                'Undo last turn',
                Icons.undo,
                disabledReason:
                    needsLive() ?? (canUndo ? null : 'Nothing to undo'),
              ),
            ]),
            group('Share', [
              row(ChatMenuAction.export, 'Export as Markdown', Icons.ios_share),
            ]),
            group('Info', [
              row(ChatMenuAction.info, 'Session info', Icons.info_outline),
            ]),
            if (canDelete)
              Padding(
                padding: const EdgeInsets.only(top: IrisSpace.md),
                child: row(
                  ChatMenuAction.delete,
                  'Delete',
                  Icons.delete_outline,
                  disabledReason: needsIdle(),
                  danger: true,
                ),
              ),
          ],
        ),
      );
    },
  );
}
