/// Decides what the app shows at launch.
///
/// Three states, and the distinction between the second and third matters: no
/// servers at all means onboarding, while several servers and none chosen means
/// a choice. Collapsing them would either re-onboard someone who is already set
/// up, or present a picker to someone with nothing to pick.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/net/server_config.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'welcome_screen.dart';

class ServerGate extends ConsumerWidget {
  const ServerGate({required this.connected, super.key});

  /// What to show once a server is selected and usable.
  final WidgetBuilder connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);

    return servers.when(
      loading: () => const _Booting(),
      // A database that will not open is not something the user can fix by
      // retrying, so it says what happened rather than spinning.
      error: (error, _) => _Unrecoverable(detail: '$error'),
      data: (list) {
        if (list.isEmpty) {
          return const WelcomeScreen();
        }

        // Deferred: selecting during build would mutate a provider mid-frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(activeServerIdProvider.notifier).selectDefault(list);
        });

        final active = ref.watch(activeServerProvider);
        if (active == null) return _ChooseServer(servers: list);
        return connected(context);
      },
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) => const IrisScaffold(
    body: Center(child: IrisOrb(state: AgentState.thinking, size: 32)),
  );
}

class _Unrecoverable extends StatelessWidget {
  const _Unrecoverable({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) => IrisScaffold(
    body: IrisEmptyState(
      icon: const IrisOrb(state: AgentState.failed, size: 40),
      title: 'Iris could not start',
      message:
          'The local database would not open. Reinstalling the app will clear '
          'it, but any cached conversations will be lost.',
      action: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IrisSpace.lg),
        child: Text(
          detail,
          textAlign: TextAlign.center,
          style: context.type.codeSmall.copyWith(
            color: context.palette.inkMuted,
          ),
        ),
      ),
    ),
  );
}

class _ChooseServer extends ConsumerWidget {
  const _ChooseServer({required this.servers});

  final List<ServerConfig> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IrisScaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(IrisSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const IrisOrb(state: AgentState.idle, size: 40),
            const SizedBox(height: IrisSpace.lg),
            Text(
              'Which agent?',
              textAlign: TextAlign.center,
              style: context.type.display,
            ),
            const SizedBox(height: IrisSpace.xl),
            for (final server in servers)
              Padding(
                padding: const EdgeInsets.only(bottom: IrisSpace.xs),
                child: IrisListRow(
                  title: server.label,
                  subtitle: server.baseUrl,
                  onTap: () => ref
                      .read(activeServerIdProvider.notifier)
                      .select(server.id),
                ),
              ),
            const SizedBox(height: IrisSpace.lg),
            IrisButton(
              label: 'Add another',
              onPressed: () => Navigator.of(context).push<void>(
                PageRouteBuilder<void>(
                  pageBuilder: (context, _, _) =>
                      const WelcomeScreen(showDemo: false),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
