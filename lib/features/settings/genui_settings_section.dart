/// The Generated displays group in Settings: whether the server has the hermes-iris plugin, and the switch that lets
/// Hermes answer with cards, tables and checklists instead of text alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/genui_providers.dart';
import '../../demo/demo_mode.dart';
import '../../design/components/controls.dart';
import '../../design/components/settings_list.dart';

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
                IrisSettingsRow(
                  label: 'Plugin',
                  value: ref.watch(genUiPluginProvider).value?.version ?? '—',
                ),
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
}
