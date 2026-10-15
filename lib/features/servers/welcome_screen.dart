/// The first screen: how this phone reaches the Hermes server, or a look at
/// Iris without one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/net/connection_mode.dart';
import '../../data/net/server_config.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'connect_screen.dart';
import 'connection_mode_copy.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({this.showDemo = true, this.onConnected, super.key});

  /// Whether to offer the demo. Off when adding a second server.
  final bool showDemo;

  /// Called once a server is saved and reachable.
  final ValueChanged<ServerConfig>? onConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.iris;
    final window = context.window;
    final palette = theme.palette;

    void open(ConnectionMode mode) => unawaited(
      Navigator.of(context).push<void>(
        IrisPageRoute<void>(
          builder: (_) => ConnectScreen(
            mode: mode,
            onConnected: (server) {
              // Back to the bottom of the stack, where the gate now shows home.
              Navigator.of(context).popUntil((route) => route.isFirst);
              onConnected?.call(server);
            },
          ),
        ),
      ),
    );

    return IrisScaffold(
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
              Text('Connect to your agent', style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                'How does this phone reach your Hermes server?',
                style: theme.typography.body.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: IrisSpace.xl),
              for (final mode in ConnectionMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: IrisSpace.xs),
                  child: IrisListRow(
                    title: mode.title,
                    subtitle: mode.line,
                    leading: Icon(
                      mode.icon,
                      size: IrisSize.icon,
                      color: palette.accent,
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: palette.lineStrong,
                    ),
                    onTap: () => open(mode),
                  ),
                ),
              const SizedBox(height: IrisSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
