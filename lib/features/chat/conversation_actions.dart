/// What can be done to a conversation from home: rename it, archive it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

enum ConversationAction { pin, rename, archive, delete }

Future<ConversationAction?> showConversationActions(
  BuildContext context,
  String title, {
  required bool pinned,
}) {
  unawaited(IrisHaptics.selection());
  return showIrisSheet<ConversationAction>(
    context: context,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      return IrisSheet(
        title: title,
        child: Column(
          children: [
            IrisListRow(
              title: pinned ? 'Unpin' : 'Pin',
              leading: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: IrisSize.icon,
                color: palette.inkMuted,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ConversationAction.pin),
            ),
            IrisListRow(
              title: 'Rename',
              leading: Icon(
                Icons.edit_outlined,
                size: IrisSize.icon,
                color: palette.inkMuted,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ConversationAction.rename),
            ),
            IrisListRow(
              title: 'Archive',
              subtitle: 'Hide it from home. You can bring it back.',
              leading: Icon(
                Icons.archive_outlined,
                size: IrisSize.icon,
                color: palette.inkMuted,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ConversationAction.archive),
            ),
            const IrisDivider(),
            IrisListRow(
              title: 'Delete',
              leading: Icon(
                Icons.delete_outline,
                size: IrisSize.icon,
                color: palette.danger,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ConversationAction.delete),
            ),
          ],
        ),
      );
    },
  );
}

/// The new title, or null when the person kept the old one.
Future<String?> showRenameSheet(BuildContext context, String current) =>
    showIrisSheet<String>(
      context: context,
      builder: (sheetContext) => _RenameSheet(current: current),
    );

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.current});

  final String current;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  // Selected, so typing replaces the old title in one go.
  late final _text = TextEditingController(text: widget.current)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.current.length,
    );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final title = _text.text.trim();
    Navigator.of(
      context,
    ).pop(title.isEmpty || title == widget.current ? null : title);
  }

  @override
  Widget build(BuildContext context) => IrisSheet(
    title: 'Rename',
    actions: IrisSheetActions(
      secondary: IrisButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: IrisButton(
        label: 'Save',
        tone: IrisButtonTone.primary,
        onPressed: _save,
      ),
    ),
    child: IrisField(
      controller: _text,
      hint: 'Title',
      autofocus: true,
      onSubmitted: (_) => _save(),
    ),
  );
}
