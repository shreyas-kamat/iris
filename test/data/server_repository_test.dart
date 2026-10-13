/// Server lifecycle, against an in-memory database and a stubbed server.
///
/// The cases that matter here are the ones involving credentials: that a
/// password is never written before it is known to work, and that forgetting a
/// server actually removes it. A leaked credential is not something a user can
/// discover by using the app, so it has to be asserted.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/repositories/server_repository.dart';

import '../support/fakes.dart';

void main() {
  late IrisDatabase db;
  late FakeCredentialStore credentials;
  late ServerRepository repository;

  setUp(() {
    db = IrisDatabase(NativeDatabase.memory());
    credentials = FakeCredentialStore();
    repository = ServerRepository(database: db, credentials: credentials);
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  /// Inserts a server directly, bypassing the network that `addServer` needs.
  Future<String> seedServer({
    String label = 'Home',
    String baseUrl = 'https://hermes.example.com',
    bool requiresPassword = false,
    String? password,
  }) async {
    final id = 'srv-${label.toLowerCase()}';
    await db
        .into(db.servers)
        .insert(
          ServersCompanion.insert(
            id: id,
            baseUrl: baseUrl,
            label: label,
            requiresPassword: Value(requiresPassword),
          ),
        );
    if (password != null) await credentials.write(id, ServerSecrets(password: password));
    return id;
  }

  group('url normalisation', () {
    test('a bare host gets https, not http', () {
      // Defaulting to http on a guessed address would silently put a password
      // on the wire in the clear.
      expect(
        ServerConfig.normaliseBaseUrl('hermes.example.com'),
        'https://hermes.example.com',
      );
    });

    test('an explicit scheme is respected', () {
      expect(
        ServerConfig.normaliseBaseUrl('http://192.168.1.10:8787'),
        'http://192.168.1.10:8787',
      );
    });

    test('trailing slashes are stripped so paths do not double up', () {
      expect(
        ServerConfig.normaliseBaseUrl('https://example.com///'),
        'https://example.com',
      );
    });

    test('whitespace from a paste is removed', () {
      expect(
        ServerConfig.normaliseBaseUrl('  https://example.com  '),
        'https://example.com',
      );
    });
  });

  group('listing', () {
    test('an empty install has no servers', () async {
      expect(await repository.listServers(), isEmpty);
    });

    test('servers are returned in their stored order', () async {
      await seedServer();
      await seedServer(label: 'Work', baseUrl: 'https://work.example.com');
      final servers = await repository.listServers();
      expect(servers.map((s) => s.label), ['Home', 'Work']);
    });

    test('the watch stream emits on change', () async {
      final emissions = repository.watchServers();
      await seedServer();
      await expectLater(
        emissions,
        emitsThrough(
          predicate<List<Object?>>(
            (list) => list.length == 1,
            'a list containing the new server',
          ),
        ),
      );
    });
  });

  group('adding', () {
    test('an empty address is rejected before any network call', () async {
      final result = await repository.addServer(baseUrl: '  ', label: 'x');
      expect(result.failureOrNull?.kind, FailureKind.rejected);
      expect(await repository.listServers(), isEmpty);
    });

    test('a duplicate address is refused', () async {
      await seedServer();
      final result = await repository.addServer(
        baseUrl: 'hermes.example.com',
        label: 'Again',
      );
      expect(result.failureOrNull?.kind, FailureKind.rejected);
      expect(
        result.failureOrNull?.message,
        contains('already'),
        reason: 'the message must say why, not just fail',
      );
    });

    test('a duplicate is caught after normalisation, not before', () async {
      // "example.com" and "https://example.com/" are the same server; a naive
      // string compare would let the second one through.
      await seedServer();
      final result = await repository.addServer(
        baseUrl: 'https://hermes.example.com/',
        label: 'Again',
      );
      expect(result.isErr, isTrue);
    });
  });

  group('credentials', () {
    test('refreshing without a stored password asks for sign-in', () async {
      final id = await seedServer(requiresPassword: true);
      final config = (await repository.listServers()).single;
      expect(config.id, id);

      final result = await repository.refreshSession(config);
      expect(result.failureOrNull?.kind, FailureKind.unauthorized);
      expect(result.failureOrNull?.message, contains('Sign in'));
    });

    test('an open server needs no session refresh', () async {
      await seedServer();
      final config = (await repository.listServers()).single;
      expect((await repository.refreshSession(config)).isOk, isTrue);
    });

    test('forgetting a server removes its password', () async {
      final id = await seedServer(requiresPassword: true, password: 'hunter2');
      expect(credentials.entries, contains(id));

      final config = (await repository.listServers()).single;
      await repository.forget(config);

      expect(
        credentials.entries,
        isNot(contains(id)),
        reason: 'a credential for a deleted server is residue',
      );
      expect(await repository.listServers(), isEmpty);
    });

    test('forgetting a server removes its cached conversations', () async {
      final id = await seedServer();
      await db
          .into(db.cachedSessions)
          .insert(
            CachedSessionsCompanion.insert(serverId: id, sessionId: 'abc'),
          );
      expect(await db.select(db.cachedSessions).get(), hasLength(1));

      await repository.forget((await repository.listServers()).single);
      expect(
        await db.select(db.cachedSessions).get(),
        isEmpty,
        reason: 'disconnecting a server must not leave its history on disk',
      );
    });
  });

  group('capabilities', () {
    test('an unprobed server reports unknown, not empty', () async {
      // The distinction matters: unknown means "try it", empty means "this
      // server does not have that feature".
      final id = await seedServer();
      final capabilities = await repository.cachedCapabilities(id);
      expect(capabilities.hasProbed, isFalse);
      expect(capabilities.has(ServerCapability.crons), isTrue);
    });

    test('a stored probe is read back by name', () async {
      final id = await seedServer();
      await (db.update(db.servers)..where((s) => s.id.equals(id))).write(
        ServersCompanion(
          capabilitiesJson: const Value('["crons","skills"]'),
          probedAt: Value(DateTime.now()),
        ),
      );

      final capabilities = await repository.cachedCapabilities(id);
      expect(capabilities.hasProbed, isTrue);
      expect(capabilities.confirmed(ServerCapability.crons), isTrue);
      expect(capabilities.confirmed(ServerCapability.skills), isTrue);
      expect(capabilities.confirmed(ServerCapability.memory), isFalse);
    });

    test('a capability name this build does not know is ignored', () async {
      // A newer server reporting a feature Iris has never heard of must not
      // crash the read.
      final id = await seedServer();
      await (db.update(db.servers)..where((s) => s.id.equals(id))).write(
        ServersCompanion(
          capabilitiesJson: const Value('["crons","time_travel"]'),
          probedAt: Value(DateTime.now()),
        ),
      );
      final capabilities = await repository.cachedCapabilities(id);
      expect(capabilities.confirmed(ServerCapability.crons), isTrue);
    });
  });
}
