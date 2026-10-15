/// Managing the servers Iris knows about.
///
/// One repository owns the whole lifecycle: adding a dashboard, keeping its
/// secrets, its HTTP connection and its live link, discovering what it
/// supports, and forgetting it completely. Splitting these across several
/// objects would mean several places that each know a little about
/// credentials, and the one that forgets to clear them is the bug.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../db/database.dart';
import '../net/capabilities.dart';
import '../net/connection_mode.dart';
import '../net/credentials.dart';
import '../net/dashboard_auth.dart';
import '../net/server_config.dart';
import '../net/server_connection.dart';
import '../rpc/dashboard_session.dart';
import '../rpc/wire_socket.dart';

/// How a server is doing, right now.
enum ServerHealth {
  /// Not contacted since the app started.
  unknown,

  /// Connecting.
  checking,

  /// The live link is open.
  online,

  /// The saved login no longer works.
  unauthorized,

  /// An access proxy wants a (different) service token.
  gated,

  /// Not reachable at the moment; Iris keeps trying.
  offline,

  /// Reachable, but the certificate is not trusted.
  untrusted;

  /// What a live-link state means for the status shown beside a server.
  static ServerHealth fromLink(LinkState link) => switch (link.phase) {
    LinkPhase.idle => ServerHealth.unknown,
    LinkPhase.connecting => ServerHealth.checking,
    LinkPhase.live => ServerHealth.online,
    LinkPhase.retrying => ServerHealth.offline,
    LinkPhase.needsSignIn => ServerHealth.unauthorized,
    LinkPhase.blocked =>
      link.failure?.kind == FailureKind.tls
          ? ServerHealth.untrusted
          : ServerHealth.gated,
  };
}

/// A server plus everything currently known about it.
@immutable
final class ServerState {
  const ServerState({
    required this.config,
    this.health = ServerHealth.unknown,
    this.capabilities = const ServerCapabilities.unknown(),
    this.lastError,
    this.lastSeen,
  });

  final ServerConfig config;
  final ServerHealth health;
  final ServerCapabilities capabilities;
  final IrisFailure? lastError;
  final DateTime? lastSeen;

  bool get isUsable => health == ServerHealth.online;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerState &&
          other.config == config &&
          other.health == health &&
          other.lastSeen == lastSeen);

  @override
  int get hashCode => Object.hash(config, health, lastSeen);
}

/// Builds the HTTP side of a server. Replaced in tests.
typedef ServerConnectionFactory =
    ServerConnection Function(
      ServerConfig config, {
      required ServerSecrets secrets,
    });

/// Owns the set of known servers.
final class ServerRepository {
  ServerRepository({
    required IrisDatabase database,
    required CredentialStore credentials,
    ServerConnectionFactory? connect,
    WireConnector? connector,
  }) : _db = database,
       _credentials = credentials,
       _connect =
           connect ??
           ((config, {required secrets}) =>
               ServerConnection.create(config, secrets: secrets)),
       _connector = connector;

  static const _log = IrisLog('servers');

  final IrisDatabase _db;
  final CredentialStore _credentials;
  final ServerConnectionFactory _connect;
  final WireConnector? _connector;

  /// HTTP connections, one per server, kept because each carries a cookie
  /// jar: rebuilding one would discard the session and force a new login.
  final Map<String, ServerConnection> _connections = {};

  /// Live links, one per server that something is currently watching.
  final Map<String, DashboardSession> _sessions = {};
  final Map<String, StreamSubscription<LinkState>> _watchers = {};

  /// Every known server, in switcher order, as a live query.
  Stream<List<ServerConfig>> watchServers() =>
      (_db.select(_db.servers)..orderBy([
            (s) => OrderingTerm(expression: s.position),
            (s) => OrderingTerm(
              expression: s.lastConnectedAt,
              mode: OrderingMode.desc,
            ),
          ]))
          .watch()
          .map((rows) => rows.map(_toConfig).toList(growable: false));

  Future<List<ServerConfig>> listServers() async {
    final rows = await (_db.select(
      _db.servers,
    )..orderBy([(s) => OrderingTerm(expression: s.position)])).get();
    return rows.map(_toConfig).toList(growable: false);
  }

  static ServerConfig _toConfig(Server row) => ServerConfig(
    id: row.id,
    baseUrl: row.baseUrl,
    label: row.label,
    requiresPassword: row.requiresPassword,
    usesAccessToken: row.usesAccessToken,
    allowSelfSignedCertificate: row.allowSelfSigned,
    mode: ConnectionMode.fromStoredName(row.connectionMode),
  );

  /// Looks at [baseUrl] without saving anything, so the connect screen asks
  /// only for what this dashboard wants.
  Future<DashboardProbe> testConnection(
    String baseUrl, {
    bool allowSelfSigned = false,
    ServerSecrets secrets = ServerSecrets.none,
  }) async {
    final normalised = ServerConfig.normaliseBaseUrl(baseUrl);
    if (normalised.isEmpty) {
      return const DashboardProbe(
        access: DashboardAccess.unreachable,
        failure: IrisFailure(
          FailureKind.rejected,
          message: 'Enter a server address.',
        ),
      );
    }
    final probe = _connect(
      ServerConfig(
        id: 'probe',
        baseUrl: normalised,
        label: 'probe',
        allowSelfSignedCertificate: allowSelfSigned,
      ),
      secrets: secrets,
    );
    try {
      return await probe.auth.probe();
    } finally {
      probe.close();
    }
  }

  /// Saves a dashboard once its whole sign-in chain is proven.
  ///
  /// A server row the user cannot actually reach is worse than no row: it
  /// appears in the switcher and fails every time it is selected. So the login
  /// and a ticket mint both have to succeed first, and secrets are written only
  /// after that.
  Future<Result<ServerConfig>> addServer({
    required String baseUrl,
    required String label,
    ServerSecrets secrets = ServerSecrets.none,
    bool allowSelfSigned = false,
    ConnectionMode? mode,
  }) async {
    final normalised = ServerConfig.normaliseBaseUrl(baseUrl);
    if (normalised.isEmpty) {
      return const Err(
        IrisFailure(FailureKind.rejected, message: 'Enter a server address.'),
      );
    }

    final existing = await listServers();
    if (existing.any((s) => s.baseUrl == normalised)) {
      return const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'That server has already been added.',
        ),
      );
    }

    final config = ServerConfig(
      id: _newId(),
      baseUrl: normalised,
      label: label.trim().isEmpty ? _labelFromUrl(normalised) : label.trim(),
      requiresPassword: secrets.hasLogin,
      usesAccessToken: secrets.hasAccessToken,
      allowSelfSignedCertificate: allowSelfSigned,
      mode: mode,
    );

    final connection = _connect(config, secrets: secrets);
    final proven = await _prove(connection, secrets);
    if (proven case Err(:final failure)) {
      connection.close();
      return Err(failure);
    }
    if (!secrets.isEmpty) {
      final stored = await _credentials.write(config.id, secrets);
      if (stored case Err(:final failure)) {
        connection.close();
        return Err(failure);
      }
    }

    await _db
        .into(_db.servers)
        .insert(
          ServersCompanion.insert(
            id: config.id,
            baseUrl: config.baseUrl,
            label: config.label,
            requiresPassword: Value(config.requiresPassword),
            usesAccessToken: Value(config.usesAccessToken),
            allowSelfSigned: Value(config.allowSelfSignedCertificate),
            connectionMode: Value(mode?.storedName),
            lastConnectedAt: Value(DateTime.now()),
            position: Value(existing.length),
          ),
        );

    _connections[config.id] = connection;
    _log.info('added ${config.label}');
    return Ok(config);
  }

  /// Signs in if a login was given, then mints a ticket: the one request that
  /// proves the whole chain — access proxy, login, and the dashboard's
  /// willingness to open a live connection.
  static Future<Result<void>> _prove(
    ServerConnection connection,
    ServerSecrets secrets,
  ) async {
    if (secrets.hasLogin) {
      final signedIn = await connection.auth.signIn(
        username: secrets.username!.trim(),
        password: secrets.password!,
      );
      if (signedIn case Err(:final failure)) return Err(failure);
    }
    return (await connection.auth.mintTicket()).map((_) {});
  }

  /// The HTTP side of [config], built once with its stored secrets.
  Future<Result<ServerConnection>> connectionFor(ServerConfig config) async {
    if (_connections[config.id] case final existing?) return Ok(existing);
    final secrets = await _credentials.read(config.id);
    switch (secrets) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        // Checked again after the await: two callers can race to here.
        return Ok(
          _connections.putIfAbsent(config.id, () {
            _log.info('opening ${config.label}');
            return _connect(config, secrets: value);
          }),
        );
    }
  }

  /// The live link to [config], created once and kept until [release].
  ///
  /// Each time the link goes live the capability probe re-runs, so a plugin
  /// installed on the server since last time shows up without a restart.
  Future<Result<DashboardSession>> sessionFor(ServerConfig config) async {
    if (_sessions[config.id] case final existing?) return Ok(existing);
    final connection = await connectionFor(config);
    switch (connection) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (_sessions[config.id] case final raced?) return Ok(raced);
        final session = DashboardSession(http: value, connector: _connector);
        _sessions[config.id] = session;
        _watchers[config.id] = session.states.listen((state) {
          if (state.phase == LinkPhase.live) {
            unawaited(refreshCapabilities(config));
          }
        });
        return Ok(session);
    }
  }

  /// Stops [serverId]'s live link. Its sign-in is kept for next time.
  Future<void> release(String serverId) async {
    await _watchers.remove(serverId)?.cancel();
    await _sessions.remove(serverId)?.dispose();
  }

  /// Re-probes what [config] supports and records it.
  Future<void> refreshCapabilities(ServerConfig config) async {
    final connection = await connectionFor(config);
    if (connection case Ok(:final value)) {
      final capabilities = await CapabilityProbe(value.client).run();
      await (_db.update(
        _db.servers,
      )..where((s) => s.id.equals(config.id))).write(
        ServersCompanion(
          capabilitiesJson: Value(
            jsonEncode(capabilities.available.map((c) => c.name).toList()),
          ),
          probedAt: Value(capabilities.probedAt),
          serverVersion: Value(capabilities.serverVersion),
          lastConnectedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// What [serverId] was last found to support, as a live query.
  Stream<ServerCapabilities> watchCapabilities(String serverId) =>
      (_db.select(_db.servers)..where((s) => s.id.equals(serverId)))
          .watchSingleOrNull()
          .map(_capabilitiesOf);

  /// Reads back the last probe, so navigation renders before the network
  /// answers.
  Future<ServerCapabilities> cachedCapabilities(String serverId) async =>
      _capabilitiesOf(
        await (_db.select(
          _db.servers,
        )..where((s) => s.id.equals(serverId))).getSingleOrNull(),
      );

  static ServerCapabilities _capabilitiesOf(Server? row) {
    if (row == null || row.probedAt == null) {
      return const ServerCapabilities.unknown();
    }
    final names = {
      for (final name in Json.decode(row.capabilitiesJson).list)
        ?name.stringOrNull,
    };
    return ServerCapabilities(
      available: {
        for (final capability in ServerCapability.values)
          if (names.contains(capability.name)) capability,
      },
      probedAt: row.probedAt,
      serverVersion: row.serverVersion,
      requiresAuth: row.requiresPassword,
    );
  }

  Future<void> rename(ServerConfig config, String label) =>
      (_db.update(_db.servers)..where((s) => s.id.equals(config.id))).write(
        ServersCompanion(label: Value(label.trim())),
      );

  /// Removes a server and everything belonging to it.
  ///
  /// The secrets go first: if the database write fails halfway, the worst
  /// outcome should be an orphaned row, never an orphaned password.
  Future<void> forget(ServerConfig config) async {
    await _credentials.delete(config.id);
    await release(config.id);
    _connections.remove(config.id)?.close();
    await _db.forgetServer(config.id);
    _log.info('forgot ${config.label}');
  }

  void dispose() {
    for (final watcher in _watchers.values) {
      unawaited(watcher.cancel());
    }
    _watchers.clear();
    for (final session in _sessions.values) {
      unawaited(session.dispose());
    }
    _sessions.clear();
    for (final connection in _connections.values) {
      connection.close();
    }
    _connections.clear();
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// A default name derived from the address, so the user does not have to
  /// invent one to get started.
  static String _labelFromUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.isEmpty ? 'Server' : host;
  }
}
