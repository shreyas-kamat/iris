/// Deleting a profile asks for its name, because it removes data from the
/// server (frame D4).
library;

import 'package:flutter/material.dart';

import '../../design/components/controls.dart';
import '../../design/components/sheet.dart';

/// True when the person typed the name exactly and confirmed.
Future<bool> showDeleteProfileSheet(
  BuildContext context, {
  required String name,
  required String host,
}) async {
  final confirmed = await showIrisSheet<bool>(
    context: context,
    builder: (sheetContext) => _DeleteProfileBody(name: name, host: host),
  );
  return confirmed ?? false;
}

class _DeleteProfileBody extends StatefulWidget {
  const _DeleteProfileBody({required this.name, required this.host});

  final String name;
  final String host;

  @override
  State<_DeleteProfileBody> createState() => _DeleteProfileBodyState();
}

class _DeleteProfileBodyState extends State<_DeleteProfileBody> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IrisSheet(
    title: 'Delete ${widget.name}?',
    subtitle:
        'Its sessions, memory, skills and scheduled jobs are removed from '
        "${widget.host}. This can't be undone.",
    actions: IrisSheetActions(
      secondary: IrisButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(false),
      ),
      primary: IrisButton(
        label: 'Delete',
        tone: IrisButtonTone.danger,
        onPressed: _typed.text == widget.name
            ? () => Navigator.of(context).pop(true)
            : null,
      ),
    ),
    child: IrisField(
      label: 'Type ${widget.name} to confirm',
      controller: _typed,
      mono: true,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
    ),
  );
}
