/// Where a server's password lives.
///
/// Not in the database, not in shared preferences, and not a field on the
/// server config that gets passed around and logged. Credentials go to the
/// platform keystore and come back out only at the moment a request needs them.
///
/// The separation is deliberate: a server config is a value object that travels
/// freely through providers, gets printed in diagnostics, and may end up in a
/// crash report. If the password were a field on it, every one of those paths
/// would become a leak.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../../core/result.dart';

/// Reads and writes server secrets.
///
/// An interface rather than a concrete class so tests can substitute an
/// in-memory store. The alternative - tests touching the real platform keystore
/// - either fails in CI where no keystore exists, or leaves credentials on the
/// machine that ran them.
abstract interface class CredentialStore {
  /// The password for [serverId], or `null` if the server has none.
  Future<Result<String?>> read(String serverId);

  Future<Result<void>> write(String serverId, String password);

  /// Removes [serverId]'s password.
  Future<void> delete(String serverId);

  /// Removes every Iris credential.
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
  /// RSA-OAEP key wrapping in the hardware keystore, so no options are passed;
  /// the older `encryptedSharedPreferences` flag no longer exists because weak
  /// storage is no longer an option to opt out of.
  ///
  /// iOS is pinned to `first_unlock_this_device`: the credential is readable
  /// after the first unlock following a boot, and never leaves this device.
  /// Without `ThisDevice` it would sync to iCloud Keychain, putting a password
  /// for a machine on the user's home network into Apple's cloud, which is the
  /// opposite of what a self-hosted app is for.
  const SecureCredentialStore.platform()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  static const _log = IrisLog('credentials');
  static const _prefix = 'iris.server.password.';

  final FlutterSecureStorage _storage;

  String _keyFor(String serverId) => '$_prefix$serverId';

  /// The password for [serverId], or `null` if the server has none.
  @override
  Future<Result<String?>> read(String serverId) async {
    try {
      return Ok(await _storage.read(key: _keyFor(serverId)));
    } on Object catch (error, stackTrace) {
      // A keystore read can fail on a device whose secure hardware is in a bad
      // state. Treated as "no credential" rather than as a crash, so the user
      // is asked to sign in again instead of being locked out of the app.
      _log.warn('keystore read failed for $serverId');
      return Err(
        IrisFailure(
          FailureKind.unknown,
          message: 'Could not read the saved password.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> write(String serverId, String password) async {
    try {
      await _storage.write(key: _keyFor(serverId), value: password);
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      _log.warn('keystore write failed for $serverId');
      return Err(
        IrisFailure(
          FailureKind.unknown,
          message: 'Could not save the password securely.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Removes [serverId]'s password.
  ///
  /// Called when a server is forgotten. Leaving a credential behind for a
  /// server the user has deleted is exactly the kind of residue that makes a
  /// privacy-first app untrustworthy.
  @override
  Future<void> delete(String serverId) async {
    try {
      await _storage.delete(key: _keyFor(serverId));
    } on Object {
      _log.warn('keystore delete failed for $serverId');
    }
  }

  /// Removes every Iris credential. Used by "forget everything" in Settings.
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
