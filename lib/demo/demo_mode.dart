/// Whether the app is showing the demo, and how to leave it.
///
/// Held in memory only: the demo is a look around, so a fresh launch always
/// starts at the welcome screen.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/net/capabilities.dart';
import '../data/net/server_config.dart';
import 'demo_automation.dart';
import 'demo_world.dart';

/// The demo's world while it is shown; null otherwise.
final demoSessionProvider = NotifierProvider<DemoSession, DemoWorld?>(
  DemoSession.new,
);

class DemoSession extends Notifier<DemoWorld?> {
  DemoWorld? _world;

  @override
  DemoWorld? build() {
    ref.onDispose(() => unawaited(_world?.dispose()));
    return null;
  }

  void enter() {
    if (state != null) return;
    state = _world = DemoWorld(clock: ref.read(clockProvider));
  }

  void leave() {
    final world = _world;
    if (world == null) return;
    _world = null;
    state = null;
    unawaited(world.dispose());
  }
}

final demoModeProvider = Provider<bool>(
  (ref) => ref.watch(demoSessionProvider) != null,
);

/// The server the demo pretends to be. Its address is never contacted.
const demoServer = ServerConfig(
  id: 'demo',
  baseUrl: 'https://demo.iris',
  label: 'Demo',
);

final demoCapabilities = ServerCapabilities(
  available: const {
    ServerCapability.profiles,
    ServerCapability.sessionSearch,
    ServerCapability.cronJobs,
    ServerCapability.kanban,
  },
  probedAt: DateTime(2026, 10, 15),
  serverVersion: 'demo',
);

/// The demo's jobs, tasks and profile tools. One per demo visit.
final demoAutomationProvider = Provider<DemoAutomation>((ref) {
  final world = ref.watch(demoSessionProvider);
  if (world == null) throw StateError('No demo is running');
  return DemoAutomation(world, clock: ref.read(clockProvider));
});

/// Leaves the demo from anywhere: back to the bottom of the stack, where the
/// gate then shows the welcome screen.
void leaveDemo(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  Navigator.of(context).popUntil((route) => route.isFirst);
  // After the frame that reveals the screen underneath, not in the same tap:
  // changing the switch as that screen is revealed rebuilds its providers
  // mid-build, which Riverpod asserts against.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => container.read(demoSessionProvider.notifier).leave(),
  );
}
