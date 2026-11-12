/// The Displays screen: the profile and the display templates the person has approved, each drawn with its sample, to
/// rename or retire, with the way to review new proposals and to study again.
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
import 'study_review_screen.dart';
import 'study_screen.dart';

class DisplaysScreen extends ConsumerStatefulWidget {
  const DisplaysScreen({super.key});

  @override
  ConsumerState<DisplaysScreen> createState() => _DisplaysScreenState();
}

class _DisplaysScreenState extends ConsumerState<DisplaysScreen> {
  GenUiApi? _api;
  bool _loading = true;
  bool _busy = false;
  WorkProfile? _profile;
  List<UiTemplate> _approved = const [];

  /// Proposals the person has not looked at yet.
  int _waiting = 0;
  int _changes = 0;
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
    final all = await api.templates();
    if (!mounted) return;
    setState(() {
      _loading = false;
      final found = profile.valueOrNull;
      _profile = found != null && found.status == PersonalStatus.approved
          ? found
          : null;
      final templates = all.valueOrNull ?? const <UiTemplate>[];
      _approved = [
        for (final t in templates)
          if (t.status == PersonalStatus.approved) t,
      ];
      _waiting = templates
          .where((t) => t.status == PersonalStatus.proposed)
          .length;
      _changes = templates
          .where(
            (t) => t.status == PersonalStatus.approved && t.proposal != null,
          )
          .length;
      _message = all is Err<List<UiTemplate>>
          ? 'Could not load your displays.'
          : null;
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

  Future<void> _retire(UiTemplate template) async {
    unawaited(IrisHaptics.selection());
    final ok = await _run(
      (api) => api.saveTemplate(template.id, status: PersonalStatus.retired),
    );
    if (ok) {
      setState(
        () => _approved = [
          for (final t in _approved)
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
        () => _approved = [
          for (final t in _approved) t.id == template.id ? saved.single : t,
        ],
      );
    }
  }

  /// Opens [screen] and reloads when it closes: a review or a study changes what is approved.
  Future<void> _open(WidgetBuilder screen) async {
    await Navigator.of(context).push(IrisPageRoute<void>(builder: screen));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final gutter = context.window.gutter;
    final theme = context.iris;
    final palette = context.palette;
    final type = context.type;
    final nothing = !_loading && _profile == null && _approved.isEmpty;
    return IrisScaffold(
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
                'Displays',
                style: theme.typography.serif.copyWith(fontSize: 34, height: 1),
              ),
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
            if (_loading)
              const IrisSkeleton(height: 120)
            else ...[
              if (_waiting + _changes > 0) ...[
                _Waiting(
                  proposals: _waiting,
                  changes: _changes,
                  onTap: () =>
                      unawaited(_open((_) => const StudyReviewScreen())),
                ),
                const SizedBox(height: IrisSpace.md),
              ],
              if (nothing)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: IrisSpace.xl),
                  child: Column(
                    children: [
                      Text('No displays yet', style: type.title),
                      const SizedBox(height: IrisSpace.xs),
                      Text(
                        'Let Hermes study your work and propose some.',
                        style: type.body.copyWith(color: palette.inkMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (_profile case final profile?) ...[
                IrisCard(
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
                          children: [
                            for (final chip in profile.chips) IrisChip(chip),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: IrisSpace.md),
              ],
              for (final template in _approved) ...[
                _DisplayCard(
                  key: ValueKey('display-${template.id}-${template.rev}'),
                  template: template,
                  busy: _busy,
                  onRename: () => unawaited(_rename(template)),
                  onRetire: () => unawaited(_retire(template)),
                ),
                const SizedBox(height: IrisSpace.md),
              ],
              const SizedBox(height: IrisSpace.sm),
              IrisButton(
                label: nothing ? 'Study my work' : 'Study again',
                tone: nothing
                    ? IrisButtonTone.primary
                    : IrisButtonTone.secondary,
                expand: true,
                onPressed: () => unawaited(
                  _open(
                    (_) => Builder(
                      builder: (studyContext) => StudyScreen(
                        onReview: () => unawaited(
                          Navigator.of(studyContext).push(
                            IrisPageRoute<void>(
                              builder: (_) => const StudyReviewScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "3 proposals waiting for you", "1 change waiting for you" or both: the badge that opens the review. A change is a
/// revision of a display the person already kept.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.proposals,
    required this.changes,
    required this.onTap,
  });

  final int proposals;
  final int changes;
  final VoidCallback onTap;

  static String _count(int n, String noun) =>
      n == 1 ? '1 $noun' : '$n ${noun}s';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final what = [
      if (proposals > 0) _count(proposals, 'proposal'),
      if (changes > 0) _count(changes, 'change'),
    ].join(' and ');
    final text = '$what waiting for you';
    return IrisPressable(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: text,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accentQuiet,
            borderRadius: const BorderRadius.all(IrisRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(IrisSpace.md),
            child: Row(
              children: [
                Expanded(child: Text(text, style: context.type.body)),
                Icon(Icons.chevron_right, color: palette.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisplayCard extends StatelessWidget {
  const _DisplayCard({
    required this.template,
    required this.busy,
    required this.onRename,
    required this.onRetire,
    super.key,
  });

  final UiTemplate template;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onRetire;

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
          OpenUiView(
            code: template.expanded(),
            fallback: template.name,
            maxHeight: 220,
          ),
          const SizedBox(height: IrisSpace.md),
          Row(
            children: [
              Expanded(
                child: IrisButton(
                  key: ValueKey('rename-${template.id}'),
                  label: 'Rename',
                  expand: true,
                  onPressed: busy ? null : onRename,
                ),
              ),
              const SizedBox(width: IrisSpace.sm),
              Expanded(
                child: IrisButton(
                  key: ValueKey('retire-${template.id}'),
                  label: 'Retire',
                  tone: IrisButtonTone.ghost,
                  expand: true,
                  onPressed: busy ? null : onRetire,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
