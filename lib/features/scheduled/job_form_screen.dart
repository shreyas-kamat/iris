/// A new or edited cron job (frames A5, A5·E).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/automation/cron_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/sheet.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../automation_errors.dart';

class JobFormScreen extends ConsumerStatefulWidget {
  const JobFormScreen({this.job, super.key});

  /// The job being edited; null creates one.
  final CronJob? job;

  @override
  ConsumerState<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends ConsumerState<JobFormScreen> {
  static const scheduleHint =
      '30m · every 2h · every monday 9am · 0 9 * * * · or a date';

  late final _name = TextEditingController(text: widget.job?.name ?? '');
  late final _schedule = TextEditingController(
    text: widget.job == null
        ? ''
        : (widget.job!.schedule.isNotEmpty
              ? widget.job!.schedule
              : widget.job!.scheduleText),
  );
  late final _prompt = TextEditingController(text: widget.job?.prompt ?? '');
  final _scheduleFocus = FocusNode();

  late String? _model = widget.job?.model;
  late String? _provider = widget.job?.provider;
  late String? _deliver = widget.job?.deliver;
  String? _scheduleError;
  bool _saving = false;

  /// Taken in [initState]: a `late final` initialiser would run on first read,
  /// after the person had already typed.
  late final String _initial;

  String _signature() =>
      '${_name.text}|${_schedule.text}|${_prompt.text}|$_model|$_provider|$_deliver';

  bool get _dirty => _signature() != _initial;

  bool get _canSave =>
      !_saving &&
      _schedule.text.trim().isNotEmpty &&
      _prompt.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initial = _signature();
    for (final controller in [_name, _schedule, _prompt]) {
      controller.addListener(() {
        if (!mounted) return;
        setState(() {
          // Typing again clears what the server said about the old text.
          if (controller == _schedule) _scheduleError = null;
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _schedule.dispose();
    _prompt.dispose();
    _scheduleFocus.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showIrisSheet<bool>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Discard changes?',
        subtitle: 'What you typed here will be lost.',
        actions: IrisSheetActions(
          secondary: IrisButton(
            label: 'Keep editing',
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
          primary: IrisButton(
            label: 'Discard',
            tone: IrisButtonTone.danger,
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final repository = await ref.read(cronRepositoryProvider.future);
    if (repository == null || !mounted) return;
    setState(() {
      _saving = true;
      _scheduleError = null;
    });
    final draft = JobDraft(
      name: _name.text,
      schedule: _schedule.text,
      prompt: _prompt.text,
      model: _model,
      provider: _provider,
      deliver: _deliver,
    );
    final existing = widget.job;
    final result = existing == null
        ? await repository.create(draft)
        : await repository.update(existing.id, draft);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        setState(() => _saving = false);
        if (failure.kind == FailureKind.rejected && failure.message != null) {
          // Hermes says which part it could not read; the schedule is where
          // that nearly always is, so the message sits under it.
          setState(() => _scheduleError = failure.message);
          _scheduleFocus.requestFocus();
        } else {
          showIrisToast(context, message: describeWrite(failure), top: true);
        }
    }
  }

  Future<void> _pickModel() async {
    final chat = await ref.read(activeChatProvider.future);
    if (chat == null || !mounted) return;
    final options = (await chat.modelOptions()).valueOrNull;
    if (!mounted) return;
    if (options == null) {
      showIrisToast(context, message: "Couldn't load the model list");
      return;
    }
    final choice = await showIrisSheet<_ModelChoice>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Model',
        subtitle: 'Used for every run of this job.',
        child: Column(
          children: [
            IrisListRow(
              title: 'Profile default',
              selected: _model == null,
              onTap: () => Navigator.of(sheetContext).pop(
                const _ModelChoice(null, null),
              ),
            ),
            for (final provider in options.usable) ...[
              Padding(
                padding: const EdgeInsets.only(top: IrisSpace.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IrisLabel(provider.name),
                ),
              ),
              for (final model in provider.models)
                IrisListRow(
                  title: model,
                  selected: _model == model && _provider == provider.slug,
                  onTap: () => Navigator.of(sheetContext).pop(
                    _ModelChoice(model, provider.slug),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _model = choice.model;
      _provider = choice.provider;
    });
  }

  Future<void> _pickDeliver(List<DeliveryTarget> targets) async {
    final choice = await showIrisSheet<_DeliverChoice>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Deliver to',
        subtitle: "Where each run's reply is sent.",
        child: Column(
          children: [
            IrisListRow(
              title: 'Nowhere',
              selected: _deliver == null,
              onTap: () =>
                  Navigator.of(sheetContext).pop(const _DeliverChoice(null)),
            ),
            for (final target in targets)
              IrisListRow(
                title: target.name,
                selected: _deliver == target.id,
                onTap: () => Navigator.of(sheetContext).pop(
                  _DeliverChoice(target.id),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _deliver = choice.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    final targets = ref.watch(deliveryTargetsProvider).value ?? const [];
    final deliverName = targets
        .where((t) => t.id == _deliver)
        .map((t) => t.name)
        .firstOrNull;
    return IrisScaffold(
      onBack: _cancel,
      header: Padding(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.sm),
        child: Row(
          children: [
            IrisButton(
              label: 'Cancel',
              tone: IrisButtonTone.ghost,
              onPressed: () => unawaited(_cancel()),
            ),
            Expanded(
              child: Text(
                widget.job == null ? 'New job' : 'Edit job',
                textAlign: TextAlign.center,
                style: type.heading.copyWith(color: palette.ink),
              ),
            ),
            IrisButton(
              label: 'Save',
              tone: IrisButtonTone.primary,
              busy: _saving,
              onPressed: _canSave ? () => unawaited(_save()) : null,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.lg, gutter, IrisSpace.xxl),
        children: [
          IrisField(
            label: 'Name · optional',
            hint: 'Weekly planning digest',
            controller: _name,
          ),
          const SizedBox(height: IrisSpace.lg),
          IrisField(
            label: 'Schedule',
            hint: 'every monday 9am',
            controller: _schedule,
            focusNode: _scheduleFocus,
            mono: true,
            autocorrect: false,
            enableSuggestions: false,
            errorText: _scheduleError,
          ),
          const SizedBox(height: IrisSpace.sm),
          Text(
            scheduleHint,
            style: type.codeSmall.copyWith(color: palette.inkFaint),
          ),
          const SizedBox(height: IrisSpace.lg),
          IrisField(
            label: 'Prompt',
            hint: 'What should Hermes do on each run?',
            controller: _prompt,
            minLines: 4,
            maxLines: 10,
          ),
          const SizedBox(height: IrisSpace.xl),
          IrisSettingsGroup(
            title: 'Run with',
            children: [
              IrisSettingsRow(
                label: 'Model',
                value: _model ?? 'Profile default',
                onTap: () => unawaited(_pickModel()),
              ),
              if (targets.isNotEmpty)
                IrisSettingsRow(
                  label: 'Deliver to',
                  sub: "Where each run's reply is sent",
                  value: deliverName ?? _deliver ?? 'Nowhere',
                  onTap: () => unawaited(_pickDeliver(targets)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelChoice {
  const _ModelChoice(this.model, this.provider);
  final String? model;
  final String? provider;
}

class _DeliverChoice {
  const _DeliverChoice(this.id);
  final String? id;
}
