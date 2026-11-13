/// The Iris plugin group in Settings: whether the hermes-iris plugin is on the server, its version, and the button that
/// installs or updates it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/plugin_providers.dart';
import '../../data/plugin/plugin_installer.dart';
import '../../demo/demo_mode.dart';
import '../../design/components/controls.dart';
import '../../design/components/settings_list.dart';
import '../../design/tokens/metrics.dart';
import '../plugin/plugin_install_panel.dart';

class PluginSettingsSection extends ConsumerWidget {
  const PluginSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The demo has no server to install onto.
    if (ref.watch(demoModeProvider)) return const SizedBox.shrink();
    // Nothing to offer until the server has answered the probe (offline or still asking shows no group).
    final status = ref.watch(pluginStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final install = ref.watch(pluginInstallProvider);
    final release = ref.watch(pluginReleaseProvider);
    final installing = install is PluginInstalling;

    Widget button(String label) => IrisButton(
      label: label,
      tone: IrisButtonTone.primary,
      busy: installing,
      onPressed: () =>
          unawaited(ref.read(pluginInstallProvider.notifier).install()),
    );

    final rows = <Widget>[
      switch (status) {
        PluginAbsent() => const IrisSettingsRow(
          label: 'Iris plugin',
          sub:
              'Generated displays, alerts and saved templates need it on your server',
          value: 'Not installed',
        ),
        PluginInstalled(:final version) => IrisSettingsRow(
          label: 'Iris plugin',
          value: version,
        ),
      },
      switch (status) {
        PluginAbsent() => IrisSettingsRow(
          label: 'Add it to your server',
          sub: 'Hermes marks it as an unreviewed source',
          trailing: button('Install'),
        ),
        PluginInstalled(:final updateTo?) => IrisSettingsRow(
          label: 'Update available',
          trailing: button('Update to $updateTo'),
        ),
        PluginInstalled() => const IrisSettingsRow(label: 'Up to date'),
      },
      if (install is! PluginInstallIdle)
        Padding(
          padding: const EdgeInsets.all(IrisSpace.lg),
          child: PluginInstallPanel(
            state: install,
            release: release,
            onRetry: () =>
                unawaited(ref.read(pluginInstallProvider.notifier).install()),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: IrisSettingsGroup(title: 'Iris plugin', children: rows),
    );
  }
}
