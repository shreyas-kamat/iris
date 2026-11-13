/// The one-time offer after login: what the Iris plugin adds and a single tap to put it on the server.
///
/// Nothing is installed without the tap. "Not now" is remembered per server so the offer does not come back; Settings
/// keeps the same install one tap away.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/plugin_providers.dart';
import '../../data/plugin/plugin_installer.dart';
import '../../data/plugin/plugin_release.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'plugin_install_panel.dart';

class PluginOnboardingScreen extends ConsumerWidget {
  const PluginOnboardingScreen({super.key});

  /// What the plugin adds, in the words the person will see in the app.
  static const _gains = [
    (
      icon: Icons.dashboard_customize_outlined,
      title: 'Generated displays',
      line: 'Cards, tables and checklists drawn natively instead of plain text',
    ),
    (
      icon: Icons.notifications_none,
      title: 'Alerts',
      line:
          'Your own words on your lock screen when a reply lands, an approval waits, or a job finishes',
    ),
    (
      icon: Icons.bookmarks_outlined,
      title: 'Study and templates',
      line: 'Saved displays and the learning loop',
    ),
  ];

  void _leave(BuildContext context, WidgetRef ref) {
    ref.read(pluginOnboardedProvider.notifier).markSeen();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.iris;
    final palette = theme.palette;
    final window = context.window;
    final state = ref.watch(pluginInstallProvider);
    final release = ref.watch(pluginReleaseProvider);
    final installing = state is PluginInstalling;
    final done = state is PluginInstallDone;

    void install() =>
        unawaited(ref.read(pluginInstallProvider.notifier).install());

    return IrisScaffold(
      onBack: installing ? null : () => _leave(context, ref),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: window.gutter),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: window.isCramped ? IrisSpace.lg : IrisSpace.huge,
              ),
              const IrisOrb(state: AgentState.idle, size: 40),
              const SizedBox(height: IrisSpace.lg),
              Text('Get more from Iris', style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                'Add the Iris plugin to your Hermes server.',
                style: theme.typography.body.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: IrisSpace.xl),
              for (final gain in _gains)
                Padding(
                  padding: const EdgeInsets.only(bottom: IrisSpace.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        gain.icon,
                        size: IrisSize.icon,
                        color: palette.accent,
                      ),
                      const SizedBox(width: IrisSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(gain.title, style: theme.typography.heading),
                            const SizedBox(height: IrisSpace.xxs),
                            Text(
                              gain.line,
                              style: theme.typography.caption.copyWith(
                                color: palette.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (done)
                Text(
                  _doneLine(state.result),
                  style: theme.typography.heading.copyWith(
                    color: palette.accent,
                  ),
                )
              else
                PluginInstallPanel(
                  state: state,
                  release: release,
                  onRetry: install,
                ),
              const SizedBox(height: IrisSpace.xl),
            ],
          ),
        ),
      ),
      footer: Padding(
        padding: EdgeInsets.fromLTRB(
          window.gutter,
          IrisSpace.sm,
          window.gutter,
          IrisSpace.lg,
        ),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (done)
                IrisButton(
                  label: 'Continue',
                  tone: IrisButtonTone.primary,
                  expand: true,
                  onPressed: () => _leave(context, ref),
                )
              else ...[
                // After a failure the panel's own "Try again" is the way forward.
                if (state is! PluginInstallFailed)
                  IrisButton(
                    label: 'Install on my server',
                    tone: IrisButtonTone.primary,
                    expand: true,
                    busy: installing,
                    onPressed: install,
                  ),
                IrisButton(
                  label: 'Not now',
                  tone: IrisButtonTone.ghost,
                  expand: true,
                  onPressed: installing ? null : () => _leave(context, ref),
                ),
                IrisButton(
                  label: 'What does this install?',
                  tone: IrisButtonTone.ghost,
                  expand: true,
                  onPressed: () => unawaited(_explain(context, release)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _doneLine(PluginInstallResult result) =>
      result.installedVersion == null
      ? 'Installed'
      : 'Installed v${result.installedVersion}';

  Future<void> _explain(BuildContext context, PluginRelease release) {
    return showIrisSheet<void>(
      context: context,
      builder: (context) {
        final theme = context.iris;
        final muted = theme.typography.body.copyWith(
          color: theme.palette.inkMuted,
        );
        return IrisSheet(
          title: 'What this installs',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              IrisSpace.lg,
              0,
              IrisSpace.lg,
              IrisSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Source: github.com/${release.repo}', style: muted),
                const SizedBox(height: IrisSpace.sm),
                Text(
                  'Version: ${release.version} (${release.tag})',
                  style: muted,
                ),
                const SizedBox(height: IrisSpace.sm),
                Text(
                  'Adds files to your server. Hermes marks it as an unreviewed source.',
                  style: muted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
