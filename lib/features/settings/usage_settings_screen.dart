/// Which providers' usage home shows: a Main, an optional Secondary, and any
/// others. Only providers that report usage are offered.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/usage.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

const _profileLabel = "Profile's provider";

/// The provider's display name, or the slug when the gateway did not list it.
String _nameOf(String slug, ModelOptions? options) {
  if (slug == usageFollowsProfile) return _profileLabel;
  for (final provider in options?.providers ?? const <ModelProvider>[]) {
    if (provider.slug == slug) return provider.name;
  }
  return slug;
}

/// What the Settings row shows: the main choice, and how many more.
String usageSummary(List<String> selection, ModelOptions? options) {
  if (selection.isEmpty) return _profileLabel;
  final main = _nameOf(selection.first, options);
  return selection.length == 1 ? main : '$main + ${selection.length - 1}';
}

class UsageSettingsScreen extends ConsumerWidget {
  const UsageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(usageSelectionProvider);
    final options = ref.watch(usageOptionsProvider).value;
    final reporting = [
      for (final provider in options?.providers ?? const <ModelProvider>[])
        if (provider.usage != null) provider,
    ];
    final notifier = ref.read(usageSelectionProvider.notifier);
    void replaceAt(int index, String? slug) {
      final next = [...selection];
      if (slug == null) {
        if (index < next.length) next.removeAt(index);
      } else if (index < next.length) {
        next[index] = slug;
      } else {
        next.add(slug);
      }
      notifier.setAll(next);
    }

    Future<void> pick(
      int index, {
      required bool allowProfile,
      required bool allowNone,
    }) async {
      unawaited(IrisHaptics.selection());
      final chosen = await showIrisSheet<String>(
        context: context,
        builder: (sheetContext) => IrisSheet(
          title: index == 0
              ? 'Main'
              : index == 1
              ? 'Secondary'
              : 'Add provider',
          child: Column(
            children: [
              if (allowProfile)
                IrisListRow(
                  title: _profileLabel,
                  subtitle: 'The provider behind the active profile',
                  selected:
                      index < selection.length &&
                      selection[index] == usageFollowsProfile,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(usageFollowsProfile),
                ),
              if (allowNone)
                IrisListRow(
                  title: 'None',
                  selected: index >= selection.length,
                  onTap: () => Navigator.of(sheetContext).pop(''),
                ),
              for (final provider in reporting)
                IrisListRow(
                  title: provider.name,
                  selected:
                      index < selection.length &&
                      selection[index] == provider.slug,
                  onTap: () => Navigator.of(sheetContext).pop(provider.slug),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      replaceAt(index, chosen.isEmpty ? null : chosen);
    }

    final theme = context.iris;
    final others = selection.length > 2
        ? selection.sublist(2)
        : const <String>[];
    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          context.window.gutter,
          IrisSpace.sm,
          context.window.gutter,
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
        padding: EdgeInsets.fromLTRB(
          context.window.gutter,
          IrisSpace.xs,
          context.window.gutter,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.xs),
              child: Text(
                'Usage on home',
                style: theme.typography.serif.copyWith(fontSize: 34, height: 1),
              ),
            ),
            const SizedBox(height: 22),
            IrisSettingsGroup(
              title: 'Shown on home',
              children: [
                IrisSettingsRow(
                  label: 'Main',
                  value: _nameOf(selection.first, options),
                  onTap: () => unawaited(
                    pick(0, allowProfile: true, allowNone: false),
                  ),
                ),
                IrisSettingsRow(
                  label: 'Secondary',
                  value: selection.length > 1
                      ? _nameOf(selection[1], options)
                      : 'None',
                  onTap: () => unawaited(
                    pick(1, allowProfile: true, allowNone: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            IrisAnimatedSize(
              child: selection.length < 2
                  ? const SizedBox(width: double.infinity)
                  : IrisSettingsGroup(
                      title: 'Others',
                      children: [
                        for (final (i, slug) in others.indexed)
                          IrisSettingsRow(
                            label: _nameOf(slug, options),
                            trailing: IrisPressable(
                              onTap: () {
                                unawaited(IrisHaptics.selection());
                                replaceAt(i + 2, null);
                              },
                              semanticLabel:
                                  'Remove ${_nameOf(slug, options)}',
                              child: Icon(
                                Icons.remove_circle_outline,
                                size: IrisSize.icon,
                                color: theme.palette.inkMuted,
                              ),
                            ),
                          ),
                        IrisSettingsRow(
                          label: 'Add provider',
                          onTap: () => unawaited(
                            pick(
                              selection.length,
                              allowProfile: false,
                              allowNone: false,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (reporting.isEmpty) ...[
              const SizedBox(height: IrisSpace.md),
              Text(
                'No provider on this server reports usage yet. Signed-in '
                'subscription providers such as OpenAI Codex and Anthropic '
                'do; numbers arrive a few seconds after the first look.',
                style: theme.typography.caption.copyWith(
                  color: theme.palette.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
