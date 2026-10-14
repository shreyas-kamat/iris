/// Choosing between servers.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/net/server_config.dart';
import '../../data/repositories/server_repository.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'connect_screen.dart';

/// Opens the server list.
Future<void> showServerSwitcher(BuildContext context) => showIrisSheet<void>(
  context: context,
  builder: (context) => const _ServerSwitcherSheet(),
);

class _ServerSwitcherSheet extends ConsumerWidget {
  const _ServerSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider).value ?? const <ServerConfig>[];
    final activeId = ref.watch(activeServerIdProvider);
    final activeState = ref.watch(activeServerStateProvider).value;

    return IrisSheet(
      title: 'Servers',
      subtitle: servers.length == 1
          ? 'One server connected.'
          : '${servers.length} servers.',
      actions: IrisSheetActions(
        primary: IrisButton(
          label: 'Add a server',
          tone: IrisButtonTone.primary,
          onPressed: () => _addServer(context),
        ),
      ),
      child: Column(
        children: [
          for (final server in servers)
            Padding(
              padding: const EdgeInsets.only(bottom: IrisSpace.xs),
              child: IrisListRow(
                title: server.label,
                subtitle: server.baseUrl,
                selected: server.id == activeId,
                leading: _HealthDot(
                  health: server.id == activeId
                      ? (activeState?.health ?? ServerHealth.unknown)
                      // Only the active server is polled, so the others report
                      // honestly rather than showing a stale green dot.
                      : ServerHealth.unknown,
                ),
                trailing: server.isInsecureRemote
                    ? IrisChip.state(
                        'http',
                        AgentState.waiting,
                        context.palette,
                      )
                    : null,
                onTap: () {
                  ref.read(activeServerIdProvider.notifier).select(server.id);
                  Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addServer(BuildContext context) async {
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      PageRouteBuilder<void>(
        pageBuilder: (context, _, _) => ConnectScreen(
          onConnected: (_) => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ),
    );
  }
}

/// A server's status, as the aperture rather than a generic dot.
///
/// Reusing the aperture here means "the thing that tells you how it is going"
/// looks the same in the switcher as it does in the chat header.
class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.health});

  final ServerHealth health;

  @override
  Widget build(BuildContext context) => IrisOrb(
    size: IrisSize.orbSmall,
    semanticLabel: switch (health) {
      ServerHealth.online => 'Online',
      ServerHealth.checking => 'Checking',
      ServerHealth.offline => 'Offline',
      ServerHealth.unauthorized => 'Sign in again',
      ServerHealth.gated => 'Access token needed',
      ServerHealth.untrusted => 'Certificate not trusted',
      ServerHealth.unknown => 'Not checked',
    },
    state: switch (health) {
      ServerHealth.online => AgentState.done,
      ServerHealth.checking => AgentState.thinking,
      ServerHealth.offline || ServerHealth.untrusted => AgentState.failed,
      ServerHealth.unauthorized || ServerHealth.gated => AgentState.waiting,
      ServerHealth.unknown => AgentState.idle,
    },
  );
}
