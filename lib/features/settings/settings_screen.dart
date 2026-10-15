/// Settings: the agent, the look of the app, and the server.
///
/// Every row here does something. Settings that would promise a feature the
/// app does not have yet are left out rather than shown as "coming soon", so
/// nothing on this screen is a dead end.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme_controller.dart';
import '../../app/usage.dart';
import '../../data/chat/chat_models.dart';
import '../../data/net/capabilities.dart';
import '../../data/rpc/dashboard_session.dart';
import '../../demo/demo_mode.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../chat/profile_picker.dart';
import '../home/link_status_screen.dart';
import '../servers/server_switcher.dart';
import 'usage_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    final link =
        ref.watch(activeLinkProvider).value ??
        const LinkState(LinkPhase.connecting);
    final capabilities =
        ref.watch(activeCapabilitiesProvider).value ??
        const ServerCapabilities.unknown();
    final profile = ref.watch(activeProfileProvider);
    final profiles =
        ref.watch(profilesProvider).value ?? const <AgentProfile>[];
    final preference = ref.watch(themeControllerProvider);
    final theme = context.iris;
    final palette = theme.palette;
    final (state, headline, _) = describeLink(link);

    // The model shown is the active profile's. A profile not in the list
    // (the list has not loaded yet) shows a dash rather than another profile's
    // model.
    AgentProfile? activeProfile;
    for (final candidate in profiles) {
      if (candidate.name == profile) activeProfile = candidate;
    }
    final hasChoice = profiles.length > 1;

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
                'Settings',
                style: theme.typography.serif.copyWith(fontSize: 38, height: 1),
              ),
            ),
            const SizedBox(height: 22),
            _ConnectionCard(
              orbState: state,
              headline: headline,
              host: server == null ? null : Uri.tryParse(server.baseUrl)?.host,
              version: capabilities.serverVersion,
              palette: palette,
              onTap: () => unawaited(
                Navigator.of(context).push(
                  IrisPageRoute<void>(builder: (_) => const LinkStatusScreen()),
                ),
              ),
            ),
            const SizedBox(height: 22),
            IrisSettingsGroup(
              title: 'Agent',
              children: [
                IrisSettingsRow(
                  label: 'Profile',
                  value: profile,
                  onTap: hasChoice
                      ? () => unawaited(showProfilePicker(context, ref))
                      : null,
                ),
                IrisSettingsRow(
                  label: 'Default model',
                  value: activeProfile?.model ?? '—',
                ),
              ],
            ),
            const SizedBox(height: 22),
            IrisSettingsGroup(
              title: 'Appearance',
              children: [
                IrisSettingsRow(
                  label: 'Skin',
                  value: preference.skin.label,
                  onTap: () =>
                      unawaited(_pickSkin(context, ref, preference.skin)),
                ),
                IrisSettingsRow(
                  label: 'Brightness',
                  value: preference.mode.label,
                  onTap: () =>
                      unawaited(_pickBrightness(context, ref, preference.mode)),
                ),
                IrisSettingsRow(
                  label: 'Match browser skin',
                  sub: "Use the skin picked in Hermes's web UI",
                  trailing: IrisSwitch(
                    value: preference.followServerSkin,
                    semanticLabel: 'Match browser skin',
                    onChanged: (follow) => ref
                        .read(themeControllerProvider.notifier)
                        .setFollowServerSkin(follow: follow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            IrisSettingsGroup(
              title: 'Home',
              children: [
                IrisSettingsRow(
                  label: 'Usage on home',
                  sub: 'What is left',
                  value: usageSummary(
                    ref.watch(usageSelectionProvider),
                    ref.watch(usageOptionsProvider).value,
                  ),
                  onTap: () => unawaited(
                    Navigator.of(context).push(
                      IrisPageRoute<void>(
                        builder: (_) => const UsageSettingsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (ref.watch(demoModeProvider))
              IrisSettingsGroup(
                title: 'Demo',
                children: [
                  IrisSettingsRow(
                    label: 'Leave demo',
                    sub: 'Connect your own Hermes server',
                    onTap: () => leaveDemo(context),
                  ),
                ],
              )
            else
              IrisSettingsGroup(
                title: 'Server',
                children: [
                  IrisSettingsRow(
                    label: 'Servers',
                    value: server?.label ?? 'None',
                    onTap: () => unawaited(showServerSwitcher(context)),
                  ),
                  IrisSettingsRow(
                    label: 'Connection details',
                    onTap: () => unawaited(
                      Navigator.of(context).push(
                        IrisPageRoute<void>(
                          builder: (_) => const LinkStatusScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Lets the person pick a skin. Choosing one applies it straight away and
  /// closes the sheet, which is how the rest of the app's pickers behave.
  static Future<void> _pickSkin(
    BuildContext context,
    WidgetRef ref,
    IrisSkin current,
  ) => showIrisSheet<void>(
    context: context,
    builder: (sheetContext) => IrisSheet(
      title: 'Skin',
      child: Column(
        children: [
          for (final skin in IrisSkin.values)
            IrisListRow(
              title: skin.label,
              selected: skin == current,
              onTap: () {
                ref.read(themeControllerProvider.notifier).setSkin(skin);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    ),
  );

  static Future<void> _pickBrightness(
    BuildContext context,
    WidgetRef ref,
    BrightnessMode current,
  ) => showIrisSheet<void>(
    context: context,
    builder: (sheetContext) => IrisSheet(
      title: 'Brightness',
      child: Column(
        children: [
          for (final mode in BrightnessMode.values)
            IrisListRow(
              title: mode.label,
              selected: mode == current,
              onTap: () {
                ref.read(themeControllerProvider.notifier).setMode(mode);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    ),
  );
}

/// The link at a glance, at the top of settings. Tapping it opens the full
/// connection detail.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.orbState,
    required this.headline,
    required this.host,
    required this.version,
    required this.palette,
    required this.onTap,
  });

  final AgentState orbState;
  final String headline;
  final String? host;
  final String? version;
  final IrisPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final parts = [
      if (host != null && host!.isNotEmpty) host!,
      if (version != null) 'hermes $version',
    ];
    return IrisPressable(
      onTap: onTap,
      ensureTapTarget: false,
      child: Container(
        padding: const EdgeInsets.all(IrisSpace.lg),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.line, width: IrisStroke.hairline),
        ),
        child: Row(
          children: [
            IrisOrb(state: orbState, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    style: type.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  if (parts.isNotEmpty) ...[
                    const SizedBox(height: IrisSpace.xs - 1),
                    Text(
                      parts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.codeSmall.copyWith(
                        fontSize: 11.5,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
