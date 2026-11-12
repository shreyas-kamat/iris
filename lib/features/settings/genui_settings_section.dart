/// The Generated displays group in Settings: whether the server has the hermes-iris plugin, and the switch that lets
/// Hermes answer with cards, tables and checklists instead of text alone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/genui_providers.dart';
import '../../data/genui/genui_models.dart';
import '../../demo/demo_mode.dart';
import '../../design/components/controls.dart';
import '../../design/components/settings_list.dart';
import '../../design/platform/platform_feel.dart';
import '../genui/displays_screen.dart';
import '../genui/study_review_screen.dart';
import '../genui/study_screen.dart';

class GenUiSettingsSection extends ConsumerWidget {
  const GenUiSettingsSection({super.key});

  /// Where the plugin lives and how it is switched on. Short, because Settings is not a manual; the repository README
  /// has the rest.
  static const installHelp =
      'Copy server/hermes-iris from the Iris repository to '
      '~/.hermes/plugins/iris on your server, run "hermes plugins enable '
      'iris", then restart the dashboard.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The demo has no server to draw for.
    if (ref.watch(demoModeProvider)) return const SizedBox.shrink();
    final installed = ref.watch(genUiAvailableProvider);
    final plugin = ref.watch(genUiPluginProvider).value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: IrisSettingsGroup(
        title: 'Generated displays',
        children: installed
            ? [
                IrisSettingsRow(
                  label: 'Generated displays',
                  sub: 'Let Hermes answer with cards, tables and checklists',
                  trailing: IrisSwitch(
                    value: ref.watch(genUiEnabledProvider),
                    semanticLabel: 'Generated displays',
                    onChanged: (on) => ref
                        .read(genUiEnabledProvider.notifier)
                        .set(enabled: on),
                  ),
                ),
                if (ref.watch(genUiEnabledProvider)) ...[
                  _studyRow(context, plugin),
                  _displaysRow(context, plugin),
                  _refineRow(ref, plugin),
                ],
                IrisSettingsRow(label: 'Plugin', value: plugin?.version ?? '—'),
              ]
            : const [
                IrisSettingsRow(
                  label: 'Generated displays',
                  value: 'Not installed',
                ),
                IrisSettingsRow(label: 'How to install', sub: installHelp),
              ],
      ),
    );
  }

  /// Starting a study needs a plugin that stores profiles and templates; an older one is told to update.
  Widget _studyRow(BuildContext context, GenUiCapabilities? plugin) {
    if (plugin == null) return const SizedBox.shrink();
    if (!plugin.has('templates')) {
      return const IrisSettingsRow(
        label: 'Study my work',
        sub: 'Update the hermes-iris plugin on your server to use this',
      );
    }
    return IrisSettingsRow(
      label: 'Study my work',
      sub: 'Let Hermes learn what you do and propose displays for it',
      onTap: () => unawaited(
        Navigator.of(context).push(
          IrisPageRoute<void>(
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
    );
  }

  /// The optional weekly refinement, off until switched on. Needs a plugin that has the refine tools.
  Widget _refineRow(WidgetRef ref, GenUiCapabilities? plugin) {
    if (plugin == null || !plugin.has('refine')) return const SizedBox.shrink();
    return IrisSettingsRow(
      label: 'Refine every week',
      sub:
          'Hermes looks at how your displays were used and proposes changes. You approve them.',
      trailing: IrisSwitch(
        value: ref.watch(weeklyRefineProvider).value ?? false,
        semanticLabel: 'Refine every week',
        onChanged: (on) =>
            unawaited(ref.read(weeklyRefineProvider.notifier).set(on: on)),
      ),
    );
  }

  /// What the person has kept, from a plugin that stores templates.
  Widget _displaysRow(BuildContext context, GenUiCapabilities? plugin) {
    if (plugin == null || !plugin.has('templates')) {
      return const SizedBox.shrink();
    }
    return IrisSettingsRow(
      label: 'Displays',
      sub: 'The displays and reply kits you have kept',
      onTap: () => unawaited(
        Navigator.of(
          context,
        ).push(IrisPageRoute<void>(builder: (_) => const DisplaysScreen())),
      ),
    );
  }
}
