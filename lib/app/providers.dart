/// Dependency wiring.
///
/// Written by hand rather than generated, because `riverpod_generator` needs a
/// newer Dart SDK than this project's Flutter ships. The cost is the boilerplate
/// below; the benefit is that the graph is readable in one file.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/result.dart';
import '../data/chat/chat_backend.dart';
import '../data/chat/chat_models.dart';
import '../data/db/database.dart';
import '../data/net/capabilities.dart';
import '../data/net/credentials.dart';
import '../data/net/server_config.dart';
import '../data/prefs/preferences_store.dart';
import '../data/repositories/server_repository.dart';
import '../data/rpc/dashboard_session.dart';
import '../data/rpc/rpc_frame.dart';
import '../demo/demo_chat_backend.dart';
import '../demo/demo_mode.dart';
import 'preferences.dart';

/// The on-disk database.
///
/// Overridden in tests with an in-memory executor, which is why this is a
/// provider rather than a singleton.
final databaseProvider = Provider<IrisDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden at startup');
});

/// Opens the database file, creating its directory if needed.
Future<IrisDatabase> openDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final file = p.join(directory.path, 'iris.sqlite');
  return IrisDatabase(NativeDatabase.createInBackground(File(file)));
}

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => CredentialStore.platform(),
);

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final repository = ServerRepository(
    database: ref.watch(databaseProvider),
    credentials: ref.watch(credentialStoreProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Every server the user has added.
final serversProvider = StreamProvider<List<ServerConfig>>(
  (ref) => ref.watch(serverRepositoryProvider).watchServers(),
);

/// Which server the app is currently pointed at.
///
/// Null means none is selected, which is the first-run state and also what
/// happens after the last server is forgotten.
final activeServerIdProvider = NotifierProvider<ActiveServerId, String?>(
  ActiveServerId.new,
);

class ActiveServerId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;

  /// Picks a server automatically when exactly one exists.
  ///
  /// With one server there is no choice to make, and asking the user to make it
  /// on every launch is friction for nothing.
  void selectDefault(List<ServerConfig> servers) {
    if (state != null && servers.any((s) => s.id == state)) return;
    state = servers.length == 1 ? servers.single.id : null;
  }
}

/// The active server's config, or null.
final activeServerProvider = Provider<ServerConfig?>((ref) {
  if (ref.watch(demoModeProvider)) return demoServer;
  final id = ref.watch(activeServerIdProvider);
  if (id == null) return null;
  final servers = ref.watch(serversProvider).value ?? const [];
  for (final server in servers) {
    if (server.id == id) return server;
  }
  return null;
});

/// The live link to the active server.
///
/// Started on first read and released when another server is chosen, so only
/// the server on screen holds a socket open. [activeServerProvider] compares
/// configs by id, so a rewrite of the same server's row — which every
/// capability probe makes — does not restart the link.
final activeSessionProvider = FutureProvider<DashboardSession?>((ref) async {
  if (ref.watch(demoModeProvider)) return null;
  final config = ref.watch(activeServerProvider);
  if (config == null) return null;
  final repository = ref.watch(serverRepositoryProvider);
  switch (await repository.sessionFor(config)) {
    case Err(:final failure):
      throw failure;
    case Ok(:final value):
      ref.onDispose(() => unawaited(repository.release(config.id)));
      unawaited(value.start());
      return value;
  }
});

/// Where the active server's live link is.
final activeLinkProvider = StreamProvider<LinkState>((ref) async* {
  if (ref.watch(demoModeProvider)) {
    yield const LinkState(LinkPhase.live);
    return;
  }
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) {
    yield const LinkState(LinkPhase.idle);
    return;
  }
  yield session.state;
  yield* session.states;
});

/// What the active server was last found to support.
final activeCapabilitiesProvider = StreamProvider<ServerCapabilities>((ref) {
  if (ref.watch(demoModeProvider)) return Stream.value(demoCapabilities);
  final config = ref.watch(activeServerProvider);
  if (config == null) return Stream.value(const ServerCapabilities.unknown());
  return ref.watch(serverRepositoryProvider).watchCapabilities(config.id);
});

/// Health and capabilities for the active server, together.
final activeServerStateProvider = Provider<AsyncValue<ServerState?>>((ref) {
  final config = ref.watch(activeServerProvider);
  if (config == null) return const AsyncData(null);
  final capabilities =
      ref.watch(activeCapabilitiesProvider).value ??
      const ServerCapabilities.unknown();
  return switch (ref.watch(activeLinkProvider)) {
    AsyncData(:final value) => AsyncData(
      ServerState(
        config: config,
        health: ServerHealth.fromLink(value),
        capabilities: capabilities,
        lastError: value.failure,
      ),
    ),
    AsyncError(:final error, :final stackTrace) => AsyncError(
      error,
      stackTrace,
    ),
    _ => const AsyncLoading(),
  };
});

/// The agent profile the conversation list and new chats belong to.
///
/// Remembered per server: a different server has different profiles, so each
/// starts at its own last choice, or its default.
final activeProfileProvider = NotifierProvider<ActiveProfile, String>(
  ActiveProfile.new,
);

class ActiveProfile extends Notifier<String> {
  @override
  String build() {
    final server = ref.watch(activeServerIdProvider);
    if (server == null) return 'default';
    return ref.read(preferencesProvider)[(server, PreferenceKeys.profile)] ??
        'default';
  }

  void select(String profile) {
    state = profile;
    final server = ref.read(activeServerIdProvider);
    if (server == null) return;
    // The default is stored as no key at all, so a server whose default is
    // renamed still opens on its default.
    ref
        .read(preferencesProvider.notifier)
        .set(
          server,
          PreferenceKeys.profile,
          profile == 'default' ? null : profile,
        );
  }
}

/// The chat backend for the active server's live link, scoped to the active
/// profile.
final activeChatProvider = FutureProvider<ChatBackend?>((ref) async {
  final profile = ref.watch(activeProfileProvider);
  final world = ref.watch(demoSessionProvider);
  if (world != null) return DemoChatBackend(world, profile: profile);
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  final chat = DashboardChat(session, profile: profile);
  ref.onDispose(() => unawaited(chat.dispose()));
  return chat;
});

/// The first page of the active profile's conversations, newest first.
///
/// Null until the link is live. Read again each time the link comes back, so
/// a list loaded before a drop catches up.
final conversationsProvider = FutureProvider<ConversationPage?>((ref) async {
  final live = ref.watch(
    activeLinkProvider.select((link) => link.value?.phase == LinkPhase.live),
  );
  if (!live) return null;
  final chat = await ref.watch(activeChatProvider.future);
  if (chat == null) return null;
  return switch (await chat.conversations(0)) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});

/// The active server's agent profiles. Null until the link is live.
final profilesProvider = FutureProvider<List<AgentProfile>?>((ref) async {
  final live = ref.watch(
    activeLinkProvider.select((link) => link.value?.phase == LinkPhase.live),
  );
  if (!live) return null;
  final chat = await ref.watch(activeChatProvider.future);
  if (chat == null) return null;
  final profiles = switch (await chat.profiles()) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
  // A profile remembered from an earlier launch may have been deleted on the
  // server since. Falling back here, after the await, is safe: it is no
  // longer this provider's build, so changing another provider is allowed.
  final active = ref.read(activeProfileProvider);
  if (profiles.isNotEmpty && !profiles.any((p) => p.name == active)) {
    ref.read(activeProfileProvider.notifier).select('default');
  }
  return profiles;
});

/// The wall clock, as a provider so the time-of-day greeting and the relative
/// times on screen can be fixed under test. Without this, a golden of the home
/// screen would depend on what hour it was rendered.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// How often home asks which conversations are replying.
final liveIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

/// Conversations replying right now, by stored id, from the gateway's
/// read-only `session.active_list`. Read when home opens and then on a timer
/// while it is on screen. A server without the call has nothing live: the
/// section just never shows.
final liveChatsProvider = StreamProvider.autoDispose<Map<String, LiveStatus>>((
  ref,
) async* {
  final chat = await ref.watch(activeChatProvider.future);
  if (chat == null) {
    yield const {};
    return;
  }
  final interval = ref.watch(liveIntervalProvider);
  final updates = StreamController<Map<String, LiveStatus>>();
  Timer? next;
  var disposed = false;
  Future<void> poll() async {
    final rows = await chat.activeSessions();
    if (disposed) return;
    updates.add(switch (rows) {
      Ok(:final value) => {
        for (final row in value)
          if (row.replying && row.storedId.isNotEmpty) row.storedId: row,
      },
      Err() => const {},
    });
    // A server without the call will not grow one: stop asking.
    if (rows.failureOrNull?.rpcError?.isMethodNotFound ?? false) return;
    // A timer the provider can cancel, so a disposed screen leaves nothing
    // running behind it.
    next = Timer(interval, () => unawaited(poll()));
  }

  ref.onDispose(() {
    disposed = true;
    next?.cancel();
    unawaited(updates.close());
  });
  unawaited(poll());
  yield* updates.stream;
});
