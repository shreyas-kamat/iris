/// Asking before a conversation is deleted for good, and recognising
/// Hermes's refusal to delete one that is replying.
library;

import 'package:flutter/material.dart';

import '../../core/failure.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

/// True when the person confirms. Delete is the failed colour: it cannot be
/// undone.
Future<bool> showDeleteSheet(BuildContext context, String title) async {
  final confirmed = await showIrisSheet<bool>(
    context: context,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      final type = sheetContext.type;
      Widget button(String label, {required bool delete}) => Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(sheetContext).pop(delete),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: delete ? palette.danger : palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: delete
                    ? null
                    : Border.all(color: palette.lineStrong, width: IrisStroke.hairline),
              ),
              child: Text(
                label,
                style: type.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: delete ? palette.onDanger : palette.ink,
                ),
              ),
            ),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete ‘$title’?',
              style: type.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: IrisSpace.xs),
            Text(
              'This removes it from Hermes for good.',
              style: type.body.copyWith(fontSize: 14, color: palette.inkMuted),
            ),
            const SizedBox(height: IrisSpace.lg),
            Row(
              children: [
                button('Cancel', delete: false),
                const SizedBox(width: IrisSpace.sm),
                button('Delete', delete: true),
              ],
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// Whether [failure] is Hermes declining to delete a conversation that is
/// live (error 4023 over RPC, a conflict over REST). The wording varies by
/// version, so the message is matched too.
bool refusedAsLive(IrisFailure failure) {
  if (failure.statusCode == 409 || failure.statusCode == 423) return true;
  final text = (failure.message ?? '').toLowerCase();
  return text.contains('active session') ||
      text.contains('is active') ||
      text.contains('still running') ||
      text.contains('4023');
}
