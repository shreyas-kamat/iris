/// Review of what a study proposed: the profile and each template, drawn live with its made-up sample, to keep, rename
/// or drop. Nothing is used by the agent until it is kept.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/genui_providers.dart';
import '../../core/result.dart';
import '../../data/genui/genui_api.dart';
import '../../data/genui/personal_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../chat/chat_controller.dart';
import 'render/open_ui_view.dart';

class StudyReviewScreen extends ConsumerStatefulWidget {
  const StudyReviewScreen({super.key});

  @override
  ConsumerState<StudyReviewScreen> createState() => _StudyReviewScreenState();
}

class _StudyReviewScreenState extends ConsumerState<StudyReviewScreen> {
  GenUiApi? _api;
  bool _loading = true;
  bool _busy = false;
  WorkProfile? _profile;
  List<UiTemplate> _templates = const [];

  /// Why the last change was refused, in the plugin's words.
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = await ref.read(genUiApiProvider.future);
    if (!mounted) return;
    _api = api;
    if (api == null) {
      setState(() => _loading = false);
      return;
    }
    final profile = await api.workProfile();
    final templates = await api.templates(status: PersonalStatus.proposed);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final found = profile.valueOrNull;
      _profile = found != null && found.status == PersonalStatus.proposed
          ? found
          : null;
      _templates = templates.valueOrNull ?? const [];
      if (profile is Err<WorkProfile?> && templates is Err<List<UiTemplate>>) {
        _message = 'Could not load what Hermes proposed.';
      }
    });
  }

  /// Runs one change; true when the plugin took it. A refusal is shown and nothing changes.
  Future<bool> _run(
    Future<Result<Object?>> Function(GenUiApi api) change,
  ) async {
    final api = _api;
    if (api == null || _busy) return false;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await change(api);
    if (!mounted) return false;
    setState(() {
      _busy = false;
      if (result case Err(:final failure)) {
        _message = ChatController.describe(failure);
      }
    });
    return result is Ok;
  }

  Future<void> _setProfile(PersonalStatus status) async {
    unawaited(IrisHaptics.selection());
    if (await _run((api) => api.saveWorkProfile(status: status))) {
      setState(() => _profile = null);
    }
  }

  Future<void> _setTemplate(UiTemplate template, PersonalStatus status) async {
    unawaited(IrisHaptics.selection());
    if (await _run((api) => api.saveTemplate(template.id, status: status))) {
      setState(
        () => _templates = [
          for (final t in _templates)
            if (t.id != template.id) t,
        ],
      );
    }
  }

  Future<void> _rename(UiTemplate template) async {
    final name = await showIrisSheet<String>(
      context: context,
      builder: (_) => RenameTemplateSheet(current: template.name),
    );
    if (name == null || name.trim().isEmpty || name.trim() == template.name) {
      return;
    }
    final saved = <UiTemplate>[];
    final ok = await _run((api) async {
      final result = await api.saveTemplate(template.id, name: name.trim());
      if (result case Ok(:final value)) saved.add(value);
      return result;
    });
    if (ok && saved.isNotEmpty) {
      setState(
        () => _templates = [
          for (final t in _templates) t.id == template.id ? saved.single : t,
        ],
      );
    }
  }

  Future<void> _keepAll() async {
    unawaited(IrisHaptics.selection());
    if (_profile != null) await _setProfile(PersonalStatus.approved);
    for (final template in List.of(_templates)) {
      if (!mounted || _message != null) return;
      await _setTemplate(template, PersonalStatus.approved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gutter = context.window.gutter;
    final theme = context.iris;
    final palette = context.palette;
    final type = context.type;
    final empty = !_loading && _profile == null && _templates.isEmpty;
    return IrisScaffold(
      onBack: () => unawaited(Navigator.of(context).maybePop()),
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.sm,
          gutter,
          IrisSpace.sm,
        ),
        child: Row(
          children: [
            IrisCircleButton(
              icon: Icons.arrow_back_ios_new,
              semanticLabel: 'Back',
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.xs, gutter, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.xs),
              child: Text(
                'What Hermes found',
                style: theme.typography.serif.copyWith(fontSize: 34, height: 1),
              ),
            ),
            const SizedBox(height: IrisSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.xs),
              child: Text(
                'These are drawn with made-up sample data. Nothing is used '
                'until you keep it.',
                style: type.body.copyWith(color: palette.inkMuted),
              ),
            ),
            const SizedBox(height: IrisSpace.lg),
            if (_loading)
              const IrisSkeleton(height: 120)
            else if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: IrisSpace.xl),
                child: Text(
                  'Nothing left to review',
                  style: type.title,
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              IrisButton(
                label: 'Keep all',
                tone: IrisButtonTone.primary,
                busy: _busy,
                onPressed: _keepAll,
              ),
              const SizedBox(height: IrisSpace.lg),
              if (_message case final message?)
                Padding(
                  padding: const EdgeInsets.only(bottom: IrisSpace.md),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      style: type.body.copyWith(color: palette.danger),
                    ),
                  ),
                ),
              if (_profile case final profile?) ...[
                _ProfileCard(
                  profile: profile,
                  busy: _busy,
                  onKeep: () => unawaited(_setProfile(PersonalStatus.approved)),
                  onDrop: () => unawaited(_setProfile(PersonalStatus.retired)),
                ),
                const SizedBox(height: IrisSpace.md),
              ],
              for (final template in _templates) ...[
                _TemplateCard(
                  key: ValueKey('template-${template.id}-${template.rev}'),
                  template: template,
                  busy: _busy,
                  onKeep: () => unawaited(
                    _setTemplate(template, PersonalStatus.approved),
                  ),
                  onRename: () => unawaited(_rename(template)),
                  onDrop: () =>
                      unawaited(_setTemplate(template, PersonalStatus.retired)),
                ),
                const SizedBox(height: IrisSpace.md),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.busy,
    required this.onKeep,
    required this.onDrop,
  });

  final WorkProfile profile;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return IrisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IrisLabel('Your profile'),
          const SizedBox(height: IrisSpace.sm),
          Text(profile.summary, style: type.body),
          if (profile.chips.isNotEmpty) ...[
            const SizedBox(height: IrisSpace.sm),
            Wrap(
              spacing: IrisSpace.xs,
              runSpacing: IrisSpace.xs,
              children: [for (final chip in profile.chips) IrisChip(chip)],
            ),
          ],
          const SizedBox(height: IrisSpace.md),
          _Actions(
            keepKey: const ValueKey('keep-profile'),
            dropKey: const ValueKey('drop-profile'),
            busy: busy,
            onKeep: onKeep,
            onDrop: onDrop,
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.busy,
    required this.onKeep,
    required this.onRename,
    required this.onDrop,
    super.key,
  });

  final UiTemplate template;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback onRename;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final isKit = template.kind == TemplateKind.replyKit;
    return IrisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(template.name, style: type.title)),
              IrisChip(isKit ? 'Reply kit' : 'Display'),
            ],
          ),
          if (template.when.isNotEmpty) ...[
            const SizedBox(height: IrisSpace.xs),
            Text(
              template.when,
              style: type.body.copyWith(color: palette.inkMuted),
            ),
          ],
          const SizedBox(height: IrisSpace.md),
          if (isKit) ...[
            const IrisLabel('Docks above the composer'),
            const SizedBox(height: IrisSpace.xs),
          ],
          OpenUiView(
            code: template.expanded(),
            fallback: template.name,
            maxHeight: 280,
          ),
          const SizedBox(height: IrisSpace.md),
          _Actions(
            keepKey: ValueKey('keep-${template.id}'),
            dropKey: ValueKey('drop-${template.id}'),
            renameKey: ValueKey('rename-${template.id}'),
            busy: busy,
            onKeep: onKeep,
            onRename: onRename,
            onDrop: onDrop,
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.keepKey,
    required this.dropKey,
    required this.busy,
    required this.onKeep,
    required this.onDrop,
    this.renameKey,
    this.onRename,
  });

  final Key keepKey;
  final Key dropKey;
  final Key? renameKey;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback? onRename;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      IrisButton(
        key: keepKey,
        label: 'Keep',
        tone: IrisButtonTone.primary,
        expand: true,
        onPressed: busy ? null : onKeep,
      ),
      if (onRename != null)
        IrisButton(
          key: renameKey,
          label: 'Rename',
          expand: true,
          onPressed: busy ? null : onRename,
        ),
      IrisButton(
        key: dropKey,
        label: 'Drop',
        tone: IrisButtonTone.ghost,
        expand: true,
        onPressed: busy ? null : onDrop,
      ),
    ];
    return Row(
      children: [
        for (final (i, button) in buttons.indexed) ...[
          if (i > 0) const SizedBox(width: IrisSpace.sm),
          Expanded(child: button),
        ],
      ],
    );
  }
}

/// Asks for a new name for a template; pops with the text, or null when cancelled.
class RenameTemplateSheet extends StatefulWidget {
  const RenameTemplateSheet({required this.current, super.key});

  final String current;

  @override
  State<RenameTemplateSheet> createState() => _RenameTemplateSheetState();
}

class _RenameTemplateSheetState extends State<RenameTemplateSheet> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IrisSheet(
    title: 'Rename',
    subtitle: 'The name you see in Displays. Hermes keeps using the same one.',
    actions: IrisSheetActions(
      secondary: IrisButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: IrisButton(
        label: 'Save',
        tone: IrisButtonTone.primary,
        onPressed: () => Navigator.of(context).pop(_controller.text),
      ),
    ),
    child: IrisField(controller: _controller, autofocus: true),
  );
}
