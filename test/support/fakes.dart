/// In-memory stand-ins for platform services, shared across tests.
library;

import 'package:iris/core/result.dart';
import 'package:iris/data/net/credentials.dart';

/// An in-memory credential store, so tests never touch the real keystore.
final class FakeCredentialStore implements CredentialStore {
  final Map<String, ServerSecrets> entries = {};

  @override
  Future<Result<ServerSecrets>> read(String serverId) async =>
      Ok(entries[serverId] ?? ServerSecrets.none);

  @override
  Future<Result<void>> write(String serverId, ServerSecrets secrets) async {
    entries[serverId] = secrets;
    return const Ok(null);
  }

  @override
  Future<void> delete(String serverId) async {
    entries.remove(serverId);
  }

  @override
  Future<void> deleteAll() async => entries.clear();
}
