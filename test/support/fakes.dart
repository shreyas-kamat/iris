/// In-memory stand-ins for platform services, shared across tests.
library;

import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

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

/// A gateway that does not know [method].
IrisFailure unknownMethod(String method) => IrisFailure(
  FailureKind.rejected,
  message: 'unknown method: $method',
  endpoint: method,
  cause: const RpcError(code: -32601, message: 'unknown method'),
);
