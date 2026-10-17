/// A new task (frame B5).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/automation/kanban_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/segmented.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/sheet.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../automation_errors.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({this.initialColumn = 'triage', super.key});

  /// The column the board was showing. Only Triage and To do can be created
  /// in; anything else starts in Triage.
  final String initialColumn;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late String _column = KanbanColumns.creatable.contains(widget.initialColumn)
      ? widget.initialColumn
      : 'triage';
  String? _assignee;
  int? _priority;
  bool _saving = false;

  bool get _canCreate => !_saving && _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _step(int by) => setState(() {
    final next = (_priority ?? 0) + by;
    _priority = next < 1 ? null : next;
  });

  Future<void> _pickAssignee() async {
    final profiles = ref.read(profilesProvider).value ?? const [];
    final choice = await showIrisSheet<_Assignee>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Assignee',
        subtitle: 'The profile that works on this task.',
        child: Column(
          children: [
            IrisListRow(
              title: 'None',
              selected: _assignee == null,
              onTap: () =>
                  Navigator.of(sheetContext).pop(const _Assignee(null)),
            ),
            for (final profile in profiles)
              IrisListRow(
                title: profile.name,
                selected: _assignee == profile.name,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_Assignee(profile.name)),
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _assignee = choice.name);
  }

  Future<void> _create() async {
    final repository = await ref.read(kanbanRepositoryProvider.future);
    if (repository == null || !mounted) return;
    setState(() => _saving = true);
    final result = await repository.create(
      TaskDraft(
        title: _title.text,
        body: _body.text,
        status: _column,
        assignee: _assignee,
        priority: _priority,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(kanbanBoardProvider);
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() => _saving = false);
        showIrisToast(context, message: describeWrite(failure), top: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    // Watched so the assignee list is loaded before the sheet asks for it.
    ref.watch(profilesProvider);
    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.sm),
        child: Row(
          children: [
            IrisButton(
              label: 'Cancel',
              tone: IrisButtonTone.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                'New task',
                textAlign: TextAlign.center,
                style: type.heading.copyWith(color: palette.ink),
              ),
            ),
            IrisButton(
              label: 'Create',
              tone: IrisButtonTone.primary,
              busy: _saving,
              onPressed: _canCreate ? () => unawaited(_create()) : null,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.lg, gutter, IrisSpace.xxl),
        children: [
          IrisField(
            label: 'Title',
            hint: 'What needs doing',
            controller: _title,
            autofocus: true,
          ),
          const SizedBox(height: IrisSpace.lg),
          IrisField(
            label: 'Body · optional · Markdown',
            hint: "What needs doing, and how you'll know it's done",
            controller: _body,
            minLines: 4,
            maxLines: 10,
          ),
          const SizedBox(height: IrisSpace.lg),
          IrisLabel('Column', color: palette.inkFaint),
          const SizedBox(height: IrisSpace.sm),
          IrisSegmented<String>(
            values: KanbanColumns.creatable,
            selected: _column,
            labelOf: KanbanColumns.label,
            onChanged: (column) => setState(() => _column = column),
          ),
          const SizedBox(height: IrisSpace.xl),
          IrisSettingsGroup(
            title: 'Details',
            children: [
              IrisSettingsRow(
                label: 'Assignee',
                sub: 'Optional · a profile',
                value: _assignee ?? 'None',
                onTap: () => unawaited(_pickAssignee()),
              ),
              IrisSettingsRow(
                label: 'Priority',
                sub: _priority == null ? 'Optional' : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepButton(
                      icon: Icons.remove,
                      tooltip: 'Less priority',
                      onPressed: _priority == null ? null : () => _step(-1),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        _priority?.toString() ?? '',
                        textAlign: TextAlign.center,
                        style: type.code.copyWith(color: palette.ink),
                      ),
                    ),
                    _StepButton(
                      icon: Icons.add,
                      tooltip: 'More priority',
                      onPressed: () => _step(1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Assignee {
  const _Assignee(this.name);
  final String? name;
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          size: IrisSize.icon,
          color: onPressed == null
              ? context.palette.inkFaint
              : context.palette.ink,
        ),
      ),
    ),
  );
}
