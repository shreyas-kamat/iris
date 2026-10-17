/// A new profile, or an existing one's name and SOUL (frames D2, D3).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/automation_providers.dart';
import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/automation/profile_repository.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/sheet.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../automation_errors.dart';
import 'delete_profile_sheet.dart';

class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({this.editing, super.key});

  /// The profile being edited; null creates one.
  final String? editing;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  late final _name = TextEditingController(text: widget.editing ?? '');
  final _soul = TextEditingController();
  ProfileStart _start = ProfileStart.blank;
  String _source = 'default';
  bool _mono = true;
  bool _saving = false;
  String? _nameError;

  /// The SOUL as the server holds it; null until loaded, or if it could not
  /// be, so a failed read never turns into an empty overwrite.
  String? _loadedSoul;

  bool get _editing => widget.editing != null;
  bool get _isDefault => widget.editing == 'default';

  bool get _nameChanged =>
      _editing && !_isDefault && _name.text != widget.editing;
  bool get _soulChanged => _loadedSoul != null && _soul.text != _loadedSoul;

  bool get _canSave {
    if (_saving) return false;
    if (!_editing) return ProfileName.isValid(_name.text);
    if (_nameChanged && !ProfileName.isValid(_name.text)) return false;
    return _nameChanged || _soulChanged;
  }

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _nameError = null));
    _soul.addListener(() => setState(() {}));
    if (_editing) unawaited(_loadSoul());
  }

  @override
  void dispose() {
    _name.dispose();
    _soul.dispose();
    super.dispose();
  }

  Future<void> _loadSoul() async {
    final repository = await ref.read(profileRepositoryProvider.future);
    final result = await repository?.soul(widget.editing!);
    if (!mounted) return;
    if (result case Ok(:final value)) {
      setState(() {
        _loadedSoul = value;
        _soul.text = value;
      });
    }
  }

  Future<void> _pickSource() async {
    final profiles = ref.read(profilesProvider).value ?? const <AgentProfile>[];
    final picked = await showIrisSheet<String>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Copy from',
        child: Column(
          children: [
            for (final profile in profiles)
              IrisListRow(
                title: profile.name,
                selected: profile.name == _source,
                onTap: () => Navigator.of(sheetContext).pop(profile.name),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _source = picked);
  }

  Future<void> _save() async {
    final repository = await ref.read(profileRepositoryProvider.future);
    if (repository == null || !mounted) return;
    setState(() => _saving = true);
    Result<void> result;
    var name = widget.editing ?? _name.text;
    if (!_editing) {
      result = await repository.create(
        ProfileDraft(
          name: _name.text,
          start: _start,
          source: _source,
          soul: _soul.text,
        ),
      );
      // The server may ignore the SOUL sent with a create (the live one does),
      // so it is written after the profile exists.
      if (result.isOk && _soul.text.trim().isNotEmpty) {
        final written = await repository.setSoul(name, _soul.text);
        if (written case Err(:final failure) when mounted) {
          // The profile exists now, so a retry would be refused: say so and go on.
          showIrisToast(
            context,
            message:
                'Profile created, but its SOUL was not saved: '
                '${describeWrite(failure)}',
            top: true,
          );
        }
      }
    } else {
      result = const Ok(null);
      if (_nameChanged) {
        result = await repository.rename(widget.editing!, _name.text);
        if (result.isOk) {
          name = _name.text;
          // The profile on screen follows its new name.
          if (ref.read(activeProfileProvider) == widget.editing) {
            ref.read(activeProfileProvider.notifier).select(name);
          }
        }
      }
      if (result.isOk && _soulChanged) {
        result = await repository.setSoul(name, _soul.text);
      }
    }
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(profilesProvider);
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() => _saving = false);
        if (!_editing &&
            failure.kind == FailureKind.rejected &&
            failure.message != null) {
          setState(() => _nameError = failure.message);
        } else {
          showIrisToast(context, message: describeWrite(failure), top: true);
        }
    }
  }

  Future<void> _delete() async {
    final name = widget.editing!;
    final host =
        Uri.tryParse(ref.read(activeServerProvider)?.baseUrl ?? '')?.host ??
        'this server';
    if (!await showDeleteProfileSheet(context, name: name, host: host) ||
        !mounted) {
      return;
    }
    final repository = await ref.read(profileRepositoryProvider.future);
    final result = await repository?.delete(name);
    if (!mounted) return;
    if (result case Err(:final failure)) {
      showIrisToast(context, message: describeWrite(failure), top: true);
      return;
    }
    // A deleted profile cannot stay selected.
    if (ref.read(activeProfileProvider) == name) {
      ref.read(activeProfileProvider.notifier).select('default');
    }
    ref
      ..invalidate(profilesProvider)
      ..invalidate(conversationsProvider);
    Navigator.of(context).pop(true);
    showIrisToast(context, message: 'Deleted ‘$name’');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    final profiles =
        ref.watch(profilesProvider).value ?? const <AgentProfile>[];
    final model = profiles
        .where((p) => p.name == widget.editing)
        .map((p) => p.model)
        .firstOrNull;
    final nameProblem = _nameError ?? ProfileName.problem(_name.text);

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
            IrisButton(
              label: 'Cancel',
              tone: IrisButtonTone.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                _editing ? 'Edit profile' : 'New profile',
                textAlign: TextAlign.center,
                style: type.heading.copyWith(color: palette.ink),
              ),
            ),
            IrisButton(
              label: _editing ? 'Save' : 'Create',
              tone: IrisButtonTone.primary,
              busy: _saving,
              onPressed: _canSave ? () => unawaited(_save()) : null,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.lg,
          gutter,
          IrisSpace.xxl,
        ),
        children: [
          if (_isDefault)
            IrisSettingsGroup(
              title: 'Profile',
              children: [IrisSettingsRow(label: 'Name', value: 'default')],
            )
          else ...[
            IrisField(
              label: 'Name',
              hint: 'work-notes',
              controller: _name,
              mono: true,
              autocorrect: false,
              enableSuggestions: false,
              errorText: nameProblem,
            ),
            if (nameProblem == null) ...[
              const SizedBox(height: IrisSpace.sm),
              Text(
                'Lowercase letters, digits, - and _ only',
                style: type.caption.copyWith(color: palette.inkFaint),
              ),
            ],
          ],
          if (_editing) ...[
            const SizedBox(height: IrisSpace.lg),
            IrisSettingsGroup(
              title: 'From config',
              children: [IrisSettingsRow(label: 'Model', value: model ?? '—')],
            ),
          ] else ...[
            const SizedBox(height: IrisSpace.xl),
            IrisSettingsGroup(
              title: 'Start from',
              children: [
                _StartRow(
                  label: 'Blank',
                  sub: 'Nothing copied',
                  selected: _start == ProfileStart.blank,
                  onTap: () => setState(() => _start = ProfileStart.blank),
                ),
                _StartRow(
                  label: 'Copy',
                  sub: 'Copies config and skills',
                  selected: _start == ProfileStart.copy,
                  onTap: () => setState(() => _start = ProfileStart.copy),
                ),
                _StartRow(
                  label: 'Full copy',
                  sub: 'Also copies memory and sessions',
                  selected: _start == ProfileStart.full,
                  onTap: () => setState(() => _start = ProfileStart.full),
                ),
              ],
            ),
            if (_start != ProfileStart.blank) ...[
              const SizedBox(height: IrisSpace.sm),
              IrisSettingsGroup(
                title: 'Source',
                children: [
                  IrisSettingsRow(
                    label: 'Copy from',
                    value: _source,
                    onTap: () => unawaited(_pickSource()),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: IrisSpace.xl),
          IrisField(
            label: _editing ? 'SOUL.md' : 'SOUL · optional',
            hint: 'Who this profile is and how it should work. Markdown.',
            controller: _soul,
            mono: _mono,
            minLines: 6,
            maxLines: 16,
          ),
          const SizedBox(height: IrisSpace.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monospace',
                  style: type.body.copyWith(color: palette.inkMuted),
                ),
              ),
              IrisSwitch(
                value: _mono,
                semanticLabel: 'Monospace',
                onChanged: (value) => setState(() => _mono = value),
              ),
            ],
          ),
          if (_editing && !_isDefault) ...[
            const SizedBox(height: IrisSpace.xl),
            IrisButton(
              label: 'Delete profile',
              tone: IrisButtonTone.danger,
              expand: true,
              onPressed: () => unawaited(_delete()),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartRow extends StatelessWidget {
  const _StartRow({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IrisSettingsRow(
      label: label,
      sub: sub,
      onTap: onTap,
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: IrisSize.icon,
        color: selected ? palette.accent : palette.lineStrong,
      ),
    );
  }
}
