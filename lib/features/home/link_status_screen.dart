/// Phase 1's home: the state of the live link, and nothing else yet.
///
/// Chat replaces this in Phase 2. Until then it is the one place that shows
/// whether Iris actually holds a connection, which has to be verified on a
/// device before anything is built on top of it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../data/net/capabilities.dart';
import '../../data/rpc/dashboard_session.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../servers/server_switcher.dart';

/// The orb state, headline and explanation for [link].
(AgentState, String, String) describeLink(LinkState link) {
  final tls = link.failure?.kind == FailureKind.tls;
  return switch (link.phase) {
    LinkPhase.idle || LinkPhase.connecting => (
      AgentState.loading,
      'Connecting',
      'Opening a live connection to the dashboard.',
    ),
    LinkPhase.live => (
      AgentState.done,
      'Connected',
      'Iris holds a live connection to your agent.',
    ),
    LinkPhase.retrying => (
      AgentState.offline,
      'Reconnecting',
      'The connection dropped. Trying again in '
          '${link.retryIn?.inSeconds ?? 1}s.',
    ),
    LinkPhase.needsSignIn => (
      AgentState.failed,
      'Sign-in needed',
      'The dashboard no longer accepts the saved login. Remove this server and '
          'add it again with the current password.',
    ),
    LinkPhase.blocked => (
      AgentState.failed,
      tls ? 'Certificate not trusted' : 'Blocked by Cloudflare Access',
      tls
          ? 'The server’s certificate changed or is not trusted. Remove and '
                're-add the server to review it.'
          : 'The access proxy turned Iris away. Check the service token and the '
                'application’s Service Auth policy.',
    ),
  };
}

class LinkStatusScreen extends ConsumerWidget {
  const LinkStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    final link =
        ref.watch(activeLinkProvider).value ??
        const LinkState(LinkPhase.connecting);
    final capabilities =
        ref.watch(activeCapabilitiesProvider).value ??
        const ServerCapabilities.unknown();
    final theme = context.iris;
    final palette = theme.palette;
    final (state, headline, detail) = describeLink(link);
    final stuck = switch (link.phase) {
      LinkPhase.retrying || LinkPhase.needsSignIn || LinkPhase.blocked => true,
      _ => false,
    };

    return IrisScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: context.window.gutter),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: IrisSpace.huge),
              IrisOrb(state: state, size: 40),
              const SizedBox(height: IrisSpace.lg),
              Text(headline, style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                detail,
                style: theme.typography.body.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: IrisSpace.xl),
              IrisListRow(
                title: server?.label ?? 'No server',
                subtitle: server?.baseUrl,
                onTap: () => unawaited(showServerSwitcher(context)),
              ),
              if (capabilities.serverVersion case final version?) ...[
                const SizedBox(height: IrisSpace.sm),
                IrisChip.state('Hermes $version', AgentState.done, palette),
              ],
              const SizedBox(height: IrisSpace.lg),
              const IrisLabel('On this server'),
              const SizedBox(height: IrisSpace.sm),
              Wrap(
                spacing: IrisSpace.xs,
                runSpacing: IrisSpace.xs,
                children: [
                  for (final capability in ServerCapability.values)
                    IrisChip.state(
                      capability.label,
                      capabilities.confirmed(capability)
                          ? AgentState.done
                          : AgentState.idle,
                      palette,
                    ),
                ],
              ),
              if (stuck) ...[
                const SizedBox(height: IrisSpace.xl),
                IrisButton(
                  label: 'Try again now',
                  tone: IrisButtonTone.primary,
                  expand: true,
                  onPressed: () => unawaited(
                    ref.read(activeSessionProvider).value?.reconnectNow(),
                  ),
                ),
              ],
              const SizedBox(height: IrisSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
