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
import '../data/repositories/server_repository.dart';
import '../data/rpc/dashboard_session.dart';

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

/// The chat backend for the active server's live link.
final activeChatProvider = FutureProvider<ChatBackend?>((ref) async {
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  final chat = DashboardChat(session);
  ref.onDispose(() => unawaited(chat.dispose()));
  return chat;
});

/// Recent conversations on the active server, newest first.
///
/// Null until the link is live, because `session.list` needs the socket. Read
/// again each time the link comes back, so a list loaded before a drop
/// catches up.
final conversationsProvider = FutureProvider<List<ConversationSummary>?>((
  ref,
) async {
  final live = ref.watch(
    activeLinkProvider.select(
      (link) => link.value?.phase == LinkPhase.live,
    ),
  );
  if (!live) return null;
  final chat = await ref.watch(activeChatProvider.future);
  if (chat == null) return null;
  return switch (await chat.conversations()) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});
