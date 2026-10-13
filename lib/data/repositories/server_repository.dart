/// Managing the servers Iris knows about.
///
/// One repository owns the whole lifecycle: adding a server, signing in to it,
/// discovering what it supports, keeping a live connection, and forgetting it
/// completely. Splitting these across several objects would mean four places
/// that each know a little about credentials, and the one that forgets to clear
/// them is the bug.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../db/database.dart';
import '../net/capabilities.dart';
import '../net/credentials.dart';
import '../net/server_config.dart';
import '../net/session_auth.dart';

/// How a server is doing, right now.
enum ServerHealth {
  /// Never contacted since the app started.
  unknown,

  /// A request is in flight.
  checking,

  /// Answering normally.
  online,

  /// Reachable but rejecting us. The session expired or the password changed.
  unauthorized,

  /// Not reachable.
  offline,

  /// Reachable, but the certificate is not trusted.
  untrusted,
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

  ServerState copyWith({
    ServerConfig? config,
    ServerHealth? health,
    ServerCapabilities? capabilities,
    IrisFailure? lastError,
    bool clearError = false,
    DateTime? lastSeen,
  }) => ServerState(
    config: config ?? this.config,
    health: health ?? this.health,
    capabilities: capabilities ?? this.capabilities,
    lastError: clearError ? null : (lastError ?? this.lastError),
    lastSeen: lastSeen ?? this.lastSeen,
  );

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

/// The result of trying to reach a server for the first time.
@immutable
final class ConnectionAttempt {
  const ConnectionAttempt({
    required this.requirement,
    this.serverVersion,
    this.failure,
  });

  final AuthRequirement requirement;
  final String? serverVersion;
  final IrisFailure? failure;

  bool get reachable => failure == null;
  bool get needsPassword => requirement == AuthRequirement.password;
}

/// Owns the set of known servers.
final class ServerRepository {
  ServerRepository({
    required IrisDatabase database,
    required CredentialStore credentials,
  }) : _db = database,
       _credentials = credentials;

  static const _log = IrisLog('servers');

  final IrisDatabase _db;
  final CredentialStore _credentials;

  /// Live connections, one per server, created lazily and reused.
  ///
  /// Reused because each carries a cookie jar: rebuilding the connection would
  /// silently discard the session and produce a spurious re-login prompt.
  final Map<String, ServerConnection> _connections = {};

  /// Every known server, newest activity first, as a live query.
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
    allowSelfSignedCertificate: row.allowSelfSigned,
  );

  /// The live connection for [config], creating it if needed.
  ServerConnection connectionFor(ServerConfig config) =>
      _connections.putIfAbsent(config.id, () {
        _log.info('opening connection to ${config.label}');
        return ServerConnection.create(config);
      });

  /// Contacts [baseUrl] without saving anything, to find out what it is.
  ///
  /// Run before a server is added so the wizard can ask for a password only
  /// when one is actually wanted, and can explain an untrusted certificate
  /// rather than failing with a generic network error.
  Future<ConnectionAttempt> testConnection(
    String baseUrl, {
    bool allowSelfSigned = false,
  }) async {
    final normalised = ServerConfig.normaliseBaseUrl(baseUrl);
    final probe = ServerConfig(
      id: 'probe',
      baseUrl: normalised,
      label: 'probe',
      allowSelfSignedCertificate: allowSelfSigned,
    );
    final connection = ServerConnection.create(probe);
    try {
      final result = await connection.auth.probe();
      return switch (result.requirement) {
        AuthRequirement.unknown => ConnectionAttempt(
          requirement: AuthRequirement.unknown,
          failure: IrisFailure(
            // A probe that cannot classify itself is almost always the address
            // being wrong or the certificate being untrusted, and those need
            // different fixes, so the detail is passed through verbatim.
            _looksUntrusted(result.detail)
                ? FailureKind.tls
                : FailureKind.offline,
            message: result.detail,
          ),
        ),
        _ => ConnectionAttempt(
          requirement: result.requirement,
          serverVersion: result.serverVersion,
        ),
      };
    } finally {
      connection.close();
    }
  }

  static bool _looksUntrusted(String? detail) {
    final text = (detail ?? '').toLowerCase();
    return text.contains('certificate') || text.contains('handshake');
  }

  /// Saves a server and signs in if a password was supplied.
  ///
  /// Only persists after authentication succeeds. A server row the user cannot
  /// actually reach is worse than no row: it appears in the switcher and fails
  /// every time it is selected.
  Future<Result<ServerConfig>> addServer({
    required String baseUrl,
    required String label,
    String? password,
    bool allowSelfSigned = false,
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
      requiresPassword: password != null && password.isNotEmpty,
      allowSelfSignedCertificate: allowSelfSigned,
    );

    final connection = ServerConnection.create(config);
    if (password != null && password.isNotEmpty) {
      final signIn = await connection.auth.signIn(password);
      if (signIn case Err(:final failure)) {
        connection.close();
        return Err(failure);
      }
      final stored = await _credentials.write(config.id, password);
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
            allowSelfSigned: Value(config.allowSelfSignedCertificate),
            lastConnectedAt: Value(DateTime.now()),
            position: Value(existing.length),
          ),
        );

    _connections[config.id] = connection;
    _log.info('added ${config.label}');
    return Ok(config);
  }

  /// Re-authenticates using the stored password, after a session expires.
  ///
  /// Returns a specific failure when nothing is stored, so the UI can prompt
  /// for a password instead of retrying an empty sign-in forever.
  Future<Result<void>> refreshSession(ServerConfig config) async {
    if (!config.requiresPassword) return const Ok(null);

    final stored = await _credentials.read(config.id);
    return switch (stored) {
      Err(:final failure) => Err(failure),
      Ok(value: final password) when password == null || password.isEmpty =>
        const Err(
          IrisFailure(
            FailureKind.unauthorized,
            message: 'Sign in to this server again.',
          ),
        ),
      Ok(value: final password) => await connectionFor(
        config,
      ).auth.signIn(password!),
    };
  }

  /// Checks a server and updates what is known about it.
  Future<ServerState> refresh(ServerState current) async {
    final connection = connectionFor(current.config);
    final probe = await connection.auth.probe();

    if (probe.requirement == AuthRequirement.password) {
      // A password-guarded server that rejects us may simply have an expired
      // cookie, which is recoverable without bothering the user.
      final retry = await refreshSession(current.config);
      if (retry.isOk) {
        return _probeCapabilities(connection, current);
      }
      return current.copyWith(
        health: ServerHealth.unauthorized,
        lastError: retry.failureOrNull,
      );
    }

    if (probe.requirement == AuthRequirement.unknown) {
      return current.copyWith(
        health: _looksUntrusted(probe.detail)
            ? ServerHealth.untrusted
            : ServerHealth.offline,
        lastError: IrisFailure(FailureKind.offline, message: probe.detail),
      );
    }

    return _probeCapabilities(connection, current);
  }

  Future<ServerState> _probeCapabilities(
    ServerConnection connection,
    ServerState current,
  ) async {
    final capabilities = await CapabilityProbe(connection.client).run();
    final now = DateTime.now();

    await (_db.update(_db.servers)
          ..where((s) => s.id.equals(current.config.id)))
        .write(
          ServersCompanion(
            capabilitiesJson: Value(
              jsonEncode(capabilities.available.map((c) => c.name).toList()),
            ),
            probedAt: Value(capabilities.probedAt),
            lastConnectedAt: Value(now),
          ),
        );

    return current.copyWith(
      health: ServerHealth.online,
      capabilities: capabilities,
      lastSeen: now,
      clearError: true,
    );
  }

  Future<void> rename(ServerConfig config, String label) =>
      (_db.update(_db.servers)..where((s) => s.id.equals(config.id))).write(
        ServersCompanion(label: Value(label.trim())),
      );

  /// Removes a server and everything belonging to it.
  ///
  /// The credential goes first: if the database write fails halfway, the worst
  /// outcome should be an orphaned row, never an orphaned password.
  Future<void> forget(ServerConfig config) async {
    await _credentials.delete(config.id);
    _connections.remove(config.id)?.close();
    await _db.forgetServer(config.id);
    _log.info('forgot ${config.label}');
  }

  /// Reads back the capabilities recorded on the last successful probe, so the
  /// app can render a usable navigation before the network answers.
  Future<ServerCapabilities> cachedCapabilities(String serverId) async {
    final row = await (_db.select(
      _db.servers,
    )..where((s) => s.id.equals(serverId))).getSingleOrNull();
    if (row == null || row.probedAt == null) {
      return const ServerCapabilities.unknown();
    }
    final names =
        (jsonDecode(row.capabilitiesJson) as List<dynamic>).cast<String>();
    return ServerCapabilities(
      available: {
        for (final capability in ServerCapability.values)
          if (names.contains(capability.name)) capability,
      },
      probedAt: row.probedAt,
      requiresAuth: row.requiresPassword,
    );
  }

  void dispose() {
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
