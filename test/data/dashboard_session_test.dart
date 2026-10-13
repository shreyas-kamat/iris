/// The live link: ticket, socket, re-login, backoff and the cases that must
/// not retry.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

/// Polls [condition] for up to a second.
Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition never became true');
}

void main() {
  late FakeHttp http;
  late List<(Uri, Map<String, String>)> opened;
  late List<FakeWireSocket> sockets;

  setUp(() {
    http = FakeHttp();
    opened = [];
    sockets = [];
  });

  DashboardSession sessionFor({
    ServerSecrets secrets = ServerSecrets.none,
    String baseUrl = 'https://h.example',
  }) {
    final connection = ServerConnection.create(
      ServerConfig(id: 's', baseUrl: baseUrl, label: 'H'),
      secrets: secrets,
      adapter: http,
    );
    final session = DashboardSession(
      http: connection,
      backoff: (_) => Duration.zero,
      connector: (uri, headers) async {
        opened.add((uri, headers));
        final socket = FakeWireSocket();
        sockets.add(socket);
        return socket;
      },
    );
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
    return session;
  }

  void ticketsInOrder(List<String> tickets) {
    var next = 0;
    http.on(
      'POST',
      '/api/auth/ws-ticket',
      (_) => FakeReply.json({'ticket': tickets[next++]}),
    );
  }

  test('connects over wss with a fresh ticket', () async {
    ticketsInOrder(['t1']);
    final session = sessionFor();
    await session.start();
    expect(session.state.phase, LinkPhase.live);
    expect(
      opened.single.$1,
      Uri.parse('wss://h.example/api/ws?ticket=t1'),
    );
  });

  test('sends the Access token on the socket', () async {
    ticketsInOrder(['t1']);
    await sessionFor(
      secrets: const ServerSecrets(
        accessClientId: 'id.access',
        accessClientSecret: 'shh',
      ),
    ).start();
    expect(opened.single.$2['CF-Access-Client-Id'], 'id.access');
    expect(opened.single.$2['CF-Access-Client-Secret'], 'shh');
  });

  test('never sends the Access token over ws://', () async {
    ticketsInOrder(['t1']);
    await sessionFor(
      baseUrl: 'http://192.168.1.20:9119',
      secrets: const ServerSecrets(
        accessClientId: 'id.access',
        accessClientSecret: 'shh',
      ),
    ).start();
    expect(
      opened.single.$1,
      Uri.parse('ws://192.168.1.20:9119/api/ws?ticket=t1'),
    );
    expect(opened.single.$2, isEmpty);
  });

  test('an expired session signs in again with the stored login', () async {
    var signedIn = false;
    http
      ..on('POST', '/auth/password-login', (_) {
        signedIn = true;
        return FakeReply.json({'ok': true});
      })
      ..on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => signedIn
            ? FakeReply.json({'ticket': 't2'})
            : FakeReply.json({'detail': 'Not authenticated'}, status: 401),
      );
    final session = sessionFor(
      secrets: const ServerSecrets(username: 'me', password: 'pw'),
    );
    await session.start();
    expect(session.state.phase, LinkPhase.live);
    expect(opened.single.$1.queryParameters['ticket'], 't2');
    expect(http.to('/auth/password-login').single.data, {
      'provider': 'basic',
      'username': 'me',
      'password': 'pw',
    });
  });

  test('without a stored login an expired session asks to sign in', () async {
    http.on(
      'POST',
      '/api/auth/ws-ticket',
      (_) => FakeReply.json({'detail': 'Not authenticated'}, status: 401),
    );
    final session = sessionFor();
    await session.start();
    expect(session.state.phase, LinkPhase.needsSignIn);
    expect(opened, isEmpty);
  });

  test('an access proxy blocks without retrying', () async {
    http.on('POST', '/api/auth/ws-ticket', (_) => FakeReply.cloudflareLogin());
    final session = sessionFor();
    await session.start();
    expect(session.state.phase, LinkPhase.blocked);
    expect(session.state.failure?.kind, FailureKind.accessGate);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(http.to('/api/auth/ws-ticket'), hasLength(1));
  });

  test('a dropped socket reconnects with a new ticket', () async {
    ticketsInOrder(['t1', 't2']);
    final session = sessionFor();
    await session.start();
    await sockets.single.serverCloses();
    await eventually(
      () => opened.length == 2 && session.state.phase == LinkPhase.live,
    );
    expect(opened.last.$1.queryParameters['ticket'], 't2');
  });

  test('events are forwarded from the live socket', () async {
    ticketsInOrder(['t1']);
    final session = sessionFor();
    await session.start();
    final next = session.events.first;
    sockets.single.serverSends({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready'},
    });
    expect((await next).type, 'gateway.ready');
  });

  test('a call before the link is live fails as offline', () async {
    final result = await sessionFor().call('ping');
    expect(result.failureOrNull?.kind, FailureKind.offline);
  });

  test('dispose closes the socket and stops reconnecting', () async {
    ticketsInOrder(['t1', 't2']);
    final session = sessionFor();
    await session.start();
    await session.dispose();
    expect(sockets.single.closeCode, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opened, hasLength(1));
  });

  test('backoff doubles to a five second ceiling', () {
    expect(DashboardSession.defaultBackoff(0), const Duration(seconds: 1));
    expect(DashboardSession.defaultBackoff(2), const Duration(seconds: 4));
    expect(DashboardSession.defaultBackoff(9), const Duration(seconds: 5));
  });

  test('announces it can answer server requests once the gateway is ready', () async {
    ticketsInOrder(['t1']);
    final session = sessionFor();
    await session.start();
    sockets.single.serverSends({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready'},
    });
    await eventually(() => sockets.single.sent.isNotEmpty);
    final frame = sockets.single.lastSent;
    expect(frame['method'].stringOrNull, 'client.capabilities');
    expect(frame['params']['server_requests'].boolOrNull, isTrue);
  });

  test('a clarify request reaches the session and can be answered', () async {
    ticketsInOrder(['t1']);
    final session = sessionFor();
    await session.start();
    final next = session.serverRequests.first;
    sockets.single.serverSends({
      'jsonrpc': '2.0',
      'id': 'srq-1',
      'method': 'clarify',
      'params': {'session_id': 'r1', 'question': 'Which?'},
    });
    expect((await next).method, 'clarify');
    expect(session.replyToServerRequest('srq-1', {'answer': 'A'}), isTrue);
    expect(sockets.single.lastSent['result']['answer'].stringOrNull, 'A');
  });
}
