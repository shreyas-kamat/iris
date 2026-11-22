/// What an install is doing, shown under the button that started it: progress, the reason it failed, and the command to
/// run on the server instead. Shared by the Settings row and the onboarding screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/plugin_providers.dart';
import '../../data/plugin/plugin_release.dart';
import '../../design/components/controls.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

class PluginInstallPanel extends StatelessWidget {
  const PluginInstallPanel({
    required this.state,
    required this.release,
    required this.onRetry,
    super.key,
  });

  final PluginInstallState state;
  final PluginRelease release;

  /// Runs the install again after a failure.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return switch (state) {
      PluginInstallIdle() => const SizedBox.shrink(),
      PluginInstalling(:final stillRunning) => Text(
        stillRunning
            ? 'Still installing on your server. This can take a few minutes.'
            : 'Installing…',
        style: type.caption.copyWith(color: palette.inkMuted),
      ),
      PluginInstallDone(:final result) => Text(
        result.staleVersion != null
            ? 'Installed, but your server still reports ${result.staleVersion}. '
                  'Restart the Hermes dashboard on your server to load ${release.version}.'
            : result.installedVersion == null
            ? 'Installed'
            : 'Installed version ${result.installedVersion}',
        style: type.caption.copyWith(color: palette.inkMuted),
      ),
      PluginInstallFailed(:final result) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.error ?? 'The install failed.',
            style: type.caption.copyWith(
              color: palette.colorFor(AgentState.failed),
            ),
          ),
          // Without a released commit the command would have nothing to pin, so it is not offered.
          if (result.showCommand && release.released) ...[
            const SizedBox(height: IrisSpace.sm),
            Text(
              'Or run this on your server:',
              style: type.caption.copyWith(color: palette.inkMuted),
            ),
            const SizedBox(height: IrisSpace.xs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: const BorderRadius.all(IrisRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.all(IrisSpace.md),
                child: SelectableText(
                  release.fallbackCommand,
                  style: type.codeSmall.copyWith(color: palette.ink),
                ),
              ),
            ),
            const SizedBox(height: IrisSpace.sm),
            IrisButton(
              label: 'Copy command',
              onPressed: () => unawaited(
                Clipboard.setData(ClipboardData(text: release.fallbackCommand)),
              ),
            ),
          ],
          const SizedBox(height: IrisSpace.sm),
          IrisButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    };
  }
}
