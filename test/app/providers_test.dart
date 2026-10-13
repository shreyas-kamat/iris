/// The provider graph around the live link.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/repositories/server_repository.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';
import '../support/fakes.dart';

void main() {
  test('a capability refresh does not reopen the socket', () async {
    final db = IrisDatabase(NativeDatabase.memory());
    final http = FakeHttp()
      ..on('POST', '/api/auth/ws-ticket', (_) => FakeReply.json({'ticket': 't'}))
      ..on('GET', '/api/status', (_) => FakeReply.json({'version': '1'}));
    var opened = 0;
    final repository = ServerRepository(
      database: db,
      credentials: FakeCredentialStore(),
      connect: (config, {required secrets}) =>
          ServerConnection.create(config, secrets: secrets, adapter: http),
      connector: (uri, headers) async {
        opened++;
        return FakeWireSocket();
      },
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        serverRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() async {
      container.dispose();
      repository.dispose();
      await db.close();
    });

    final added = await repository.addServer(
      baseUrl: 'https://h.example',
      label: 'H',
    );
    // The server list is a stream; until its first emission the active server
    // resolves to null and no session is created. Riverpod 3 pauses a provider
    // nobody listens to, so listen as a screen would before awaiting it.
    final servers = container.listen(serversProvider, (_, _) {});
    addTearDown(servers.close);
    await container.read(serversProvider.future);
    container.read(activeServerIdProvider.notifier).select(added.valueOrNull!.id);
    // Keep the link alive the way a screen would.
    final link = container.listen(activeLinkProvider, (_, _) {});
    addTearDown(link.close);

    final session = await container.read(activeSessionProvider.future);
    for (var i = 0; i < 100 && session?.state.phase != LinkPhase.live; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // Wait for the probe triggered by going live to write the servers row.
    for (var i = 0; i < 100; i++) {
      final caps = await repository.cachedCapabilities(added.valueOrNull!.id);
      if (caps.hasProbed) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(session?.state.phase, LinkPhase.live);
    expect(opened, 1, reason: 'rewriting the servers row must not restart the link');
    expect(
      container.read(activeServerStateProvider).value?.health,
      ServerHealth.online,
    );
  });

  test('conversations wait for a live link', () async {
    final backend = FakeChatBackend()
      ..conversationsResult = const Ok([
        ConversationSummary(id: 'a', title: 'A'),
      ]);
    addTearDown(backend.close);
    final link = StreamController<LinkState>();
    addTearDown(link.close);
    final container = ProviderContainer(
      overrides: [
        activeLinkProvider.overrideWith((ref) => link.stream),
        activeChatProvider.overrideWith((ref) async => backend),
      ],
    );
    addTearDown(container.dispose);
    final listening = container.listen(conversationsProvider, (_, _) {});
    addTearDown(listening.close);

    link.add(const LinkState(LinkPhase.connecting));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await container.read(conversationsProvider.future), isNull);

    link.add(const LinkState(LinkPhase.live));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final list = await container.read(conversationsProvider.future);
    expect(list?.single.id, 'a');
  });
}
