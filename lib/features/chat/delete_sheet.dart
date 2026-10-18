/// Asking before a conversation is deleted for good, and recognising
/// Hermes's refusal to delete one that is replying.
library;

import 'package:flutter/material.dart';

import '../../core/failure.dart';
import '../../design/components/controls.dart';
import '../../design/components/sheet.dart';

/// True when the person confirms. Delete is the failed colour: it cannot be
/// undone.
Future<bool> showDeleteSheet(
  BuildContext context,
  String title, {
  String message = 'This removes it from Hermes for good.',
}) async {
  final confirmed = await showIrisSheet<bool>(
    context: context,
    builder: (sheetContext) => IrisSheet(
      title: 'Delete ‘$title’?',
      subtitle: message,
      actions: IrisSheetActions(
        secondary: IrisButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(sheetContext).pop(false),
        ),
        primary: IrisButton(
          label: 'Delete',
          tone: IrisButtonTone.danger,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
      child: const SizedBox.shrink(),
    ),
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
