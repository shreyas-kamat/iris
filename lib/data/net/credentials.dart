/// Where a server's secrets live.
///
/// Not in the database, not in shared preferences, and not a field on the
/// server config that gets passed around and logged. Secrets go to the platform
/// keystore and come back out only at the moment a request needs them.
///
/// The separation is deliberate: a server config is a value object that travels
/// freely through providers, gets printed in diagnostics, and may end up in a
/// crash report. If a password were a field on it, every one of those paths
/// would become a leak.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';

/// Everything secret about one server, kept together so it is written and
/// erased as a unit.
@immutable
final class ServerSecrets {
  const ServerSecrets({
    this.username,
    this.password,
    this.accessClientId,
    this.accessClientSecret,
  });

  factory ServerSecrets.fromJson(Json json) => ServerSecrets(
    username: json['username'].stringOrNull,
    password: json['password'].stringOrNull,
    accessClientId: json['access_client_id'].stringOrNull,
    accessClientSecret: json['access_client_secret'].stringOrNull,
  );

  /// Nothing stored: an open dashboard on a private network.
  static const none = ServerSecrets();

  /// The Hermes dashboard login.
  final String? username;
  final String? password;

  /// A Cloudflare Access service token, for a dashboard published behind
  /// Access. A native app cannot complete Access's browser login on its own
  /// requests, so the token is the only way through.
  final String? accessClientId;
  final String? accessClientSecret;

  bool get hasLogin => _filled(username) && _filled(password);

  bool get hasAccessToken =>
      _filled(accessClientId) && _filled(accessClientSecret);

  bool get isEmpty => !hasLogin && !hasAccessToken;

  static bool _filled(String? value) =>
      value != null && value.trim().isNotEmpty;

  /// The two headers Cloudflare Access reads, or none without a token.
  ///
  /// Callers decide whether the transport is encrypted; see
  /// `ServerConnection.accessHeadersFor`.
  Map<String, String> get accessHeaders => hasAccessToken
      ? {
          'CF-Access-Client-Id': accessClientId!.trim(),
          'CF-Access-Client-Secret': accessClientSecret!.trim(),
        }
      : const {};

  Map<String, Object?> toJson() => {
    'username': username,
    'password': password,
    'access_client_id': accessClientId,
    'access_client_secret': accessClientSecret,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerSecrets &&
          other.username == username &&
          other.password == password &&
          other.accessClientId == accessClientId &&
          other.accessClientSecret == accessClientSecret);

  @override
  int get hashCode =>
      Object.hash(username, password, accessClientId, accessClientSecret);

  /// Never prints a value: this object ends up in test failures and, through
  /// careless string interpolation, potentially in logs.
  @override
  String toString() =>
      'ServerSecrets(login: $hasLogin, accessToken: $hasAccessToken)';
}

/// Reads and writes server secrets.
///
/// An interface rather than a concrete class so tests can substitute an
/// in-memory store. The alternative - tests touching the real platform keystore
/// - either fails in CI where no keystore exists, or leaves credentials on the
/// machine that ran them.
abstract interface class CredentialStore {
  /// [serverId]'s secrets, or [ServerSecrets.none] if nothing is stored.
  Future<Result<ServerSecrets>> read(String serverId);

  /// Replaces [serverId]'s secrets. Writing [ServerSecrets.none] deletes them.
  Future<Result<void>> write(String serverId, ServerSecrets secrets);

  /// Removes [serverId]'s secrets.
  Future<void> delete(String serverId);

  /// Removes every Iris secret.
  Future<void> deleteAll();

  /// The platform keystore.
  factory CredentialStore.platform() = SecureCredentialStore.platform;
}

/// The real store, backed by the platform keystore.
final class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore(this._storage);

  /// Uses each platform's strongest backing.
  ///
  /// Android's defaults in flutter_secure_storage 11 are already AES-GCM with
  /// RSA-OAEP key wrapping in the hardware keystore, so no options are passed.
  ///
  /// iOS is pinned to `first_unlock_this_device`: the secret is readable after
  /// the first unlock following a boot, and never leaves this device. Without
  /// `ThisDevice` it would sync to iCloud Keychain, putting a password for a
  /// machine on the user's home network into Apple's cloud, which is the
  /// opposite of what a self-hosted app is for.
  const SecureCredentialStore.platform()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  static const _log = IrisLog('credentials');

  /// Every key Iris owns starts with this, including the pre-dashboard
  /// `iris.server.password.<id>` keys, so [deleteAll] clears those too.
  static const _prefix = 'iris.server.';

  final FlutterSecureStorage _storage;

  String _keyFor(String serverId) => '${_prefix}secrets.$serverId';

  @override
  Future<Result<ServerSecrets>> read(String serverId) async {
    try {
      final raw = await _storage.read(key: _keyFor(serverId));
      if (raw == null) return const Ok(ServerSecrets.none);
      return Ok(ServerSecrets.fromJson(Json.decode(raw)));
    } on Object catch (error, stackTrace) {
      // A keystore read can fail on a device whose secure hardware is in a bad
      // state. Reported rather than thrown, so the user is asked to sign in
      // again instead of being locked out of the app.
      _log.warn('keystore read failed for $serverId');
      return Err(
        IrisFailure(
          FailureKind.unknown,
          message: 'Could not read the saved sign-in.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> write(String serverId, ServerSecrets secrets) async {
    if (secrets.isEmpty) {
      await delete(serverId);
      return const Ok(null);
    }
    try {
      await _storage.write(
        key: _keyFor(serverId),
        value: jsonEncode(secrets.toJson()),
      );
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      _log.warn('keystore write failed for $serverId');
      return Err(
        IrisFailure(
          FailureKind.unknown,
          message: 'Could not save the sign-in securely.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Removes [serverId]'s secrets, and any pre-dashboard password key.
  ///
  /// Leaving a credential behind for a server the user has deleted is exactly
  /// the kind of residue that makes a privacy-first app untrustworthy.
  @override
  Future<void> delete(String serverId) async {
    try {
      await _storage.delete(key: _keyFor(serverId));
      await _storage.delete(key: '${_prefix}password.$serverId');
    } on Object {
      _log.warn('keystore delete failed for $serverId');
    }
  }

  /// Removes every Iris secret. Used by "forget everything" in Settings.
  @override
  Future<void> deleteAll() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key: key);
      }
    } on Object {
      _log.warn('keystore bulk delete failed');
    }
  }
}
