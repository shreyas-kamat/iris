/// The local mirror of everything Iris has seen.
///
/// The agent runs on the user's machine, which a phone cannot reach from a
/// tunnel, a plane, or a dead spot. Rather than showing a spinner in those
/// moments, Iris keeps a full local copy of every session it has opened and
/// treats the server as the thing that syncs *into* it. Reads come from here
/// first, always; the network updates rows behind the UI.
///
/// Two design rules:
///
/// * **Rows are scoped by server.** The same session id can exist on two
///   different servers and mean different conversations, so every table carries
///   `serverId` and every query filters on it.
/// * **The wire payload is kept alongside the parsed columns.** `rawJson` holds
///   the server's original object, so a field this build ignores is still there
///   after an app update, without a re-fetch or a migration.
library;

import 'package:drift/drift.dart';

part 'database.g.dart';

/// Servers the user has added. Credentials are *not* here — they live in the
/// platform keystore, keyed by [Servers.id].
class Servers extends Table {
  TextColumn get id => text()();
  TextColumn get baseUrl => text()();
  TextColumn get label => text()();
  BoolColumn get requiresPassword =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get allowSelfSigned =>
      boolean().withDefault(const Constant(false))();

  /// Probe results, stored as the JSON list of capability names so a new
  /// capability in a later build does not need a schema migration.
  TextColumn get capabilitiesJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get probedAt => dateTime().nullable()();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();

  /// Ordering in the server switcher.
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Cached session metadata — what the sessions list renders.
class CachedSessions extends Table {
  TextColumn get serverId => text().references(Servers, #id)();
  TextColumn get sessionId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get workspace => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get projectId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  /// Whether the message history has been fetched, as opposed to just the
  /// list row. Distinguishes "no messages" from "not loaded yet".
  BoolColumn get hasFullHistory =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  TextColumn get rawJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {serverId, sessionId};
}

/// Cached messages, ordered within a session by [ordinal].
///
/// Keyed on the server's own ordering rather than a timestamp because messages
/// within one turn frequently share a second, and a stable order matters more
/// than a precise one.
class CachedMessages extends Table {
  TextColumn get serverId => text()();
  TextColumn get sessionId => text()();
  IntColumn get ordinal => integer()();
  TextColumn get role => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get reasoning => text().nullable()();
  TextColumn get attachmentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get toolCallsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  TextColumn get rawJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {serverId, sessionId, ordinal};
}

/// What a queued write is trying to do.
enum OutboxKind {
  sendMessage,
  renameSession,
  deleteSession,
  updateSession,
  approvalResponse,
  cronMutation,
  skillWrite,
  memoryWrite,
}

/// Writes composed while the server was unreachable.
///
/// A message typed on a train is the user's work, not a failed request, so it
/// is durable: it survives an app kill and flushes in order when the server
/// comes back. Ordering is by [id], which is why it is an autoincrement.
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get kind => textEnum<OutboxKind>()();

  /// The request body, verbatim, ready to POST.
  TextColumn get payloadJson => text()();

  /// Correlates with the optimistic row already shown in the transcript, so a
  /// flush updates that message rather than appending a duplicate.
  TextColumn get localId => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// The last failure, kept so the UI can explain why something is stuck
  /// instead of silently retrying forever.
  TextColumn get lastError => text().nullable()();
}

/// Where to resume each session's event stream.
///
/// Persisted rather than held in memory so a run started before the app was
/// killed can be rejoined mid-flight instead of restarted.
class StreamCursors extends Table {
  TextColumn get serverId => text()();
  TextColumn get sessionId => text()();

  /// Opaque `Last-Event-ID`. Never parsed.
  TextColumn get lastEventId => text()();

  /// The `stream_id` of the run this cursor belongs to, so a cursor from a
  /// previous run is not replayed against a new one.
  TextColumn get streamId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {serverId, sessionId};
}

/// A generic cache for the read-mostly panels: skills, crons, memory, models,
/// profiles, workspaces.
///
/// One table rather than six, because these are all "fetch a list, show it,
/// refresh in the background" and none of them need to be queried by anything
/// but their key. Six near-identical tables would be six near-identical
/// migrations every time a panel changes.
class CachedDocuments extends Table {
  TextColumn get serverId => text()();

  /// The API path this came from, which is a natural unique key.
  TextColumn get key => text()();
  TextColumn get bodyJson => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {serverId, key};
}

@DriftDatabase(
  tables: [
    Servers,
    CachedSessions,
    CachedMessages,
    Outbox,
    StreamCursors,
    CachedDocuments,
  ],
)
class IrisDatabase extends _$IrisDatabase {
  IrisDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Cascading deletes keep a removed server from leaving orphaned sessions
      // and messages behind, which would otherwise accumulate silently.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Deletes everything belonging to [serverId].
  ///
  /// Removing a server must remove its data: the cache holds the user's whole
  /// conversation history, and leaving it on disk after they disconnect a
  /// server would be keeping something they asked to be rid of.
  Future<void> forgetServer(String serverId) => transaction(() async {
    await (delete(
      cachedMessages,
    )..where((t) => t.serverId.equals(serverId))).go();
    await (delete(
      cachedSessions,
    )..where((t) => t.serverId.equals(serverId))).go();
    await (delete(outbox)..where((t) => t.serverId.equals(serverId))).go();
    await (delete(
      streamCursors,
    )..where((t) => t.serverId.equals(serverId))).go();
    await (delete(
      cachedDocuments,
    )..where((t) => t.serverId.equals(serverId))).go();
    await (delete(servers)..where((t) => t.id.equals(serverId))).go();
  });
}
