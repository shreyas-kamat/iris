/// Finding out what a dashboard wants, signing in, and minting tickets.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/dashboard_auth.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;
  late ServerConnection connection;

  setUp(() {
    http = FakeHttp();
    connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'H'),
      adapter: http,
    );
  });

  tearDown(() => connection.close());

  group('probe', () {
    test('a password provider means a login is needed', () async {
      http
        ..on(
          'GET',
          '/api/auth/providers',
          (_) => FakeReply.json({
            'providers': [
              {'name': 'basic', 'supports_password': true},
            ],
          }),
        )
        ..on('GET', '/api/status', (_) => FakeReply.json({'version': '0.9.1'}));
      final probe = await connection.auth.probe();
      expect(probe.access, DashboardAccess.password);
      expect(probe.version, '0.9.1');
    });

    test('Cloudflare Access in front reads as an access gate', () async {
      http.on('GET', '/api/auth/providers', (_) => FakeReply.cloudflareLogin());
      expect(
        (await connection.auth.probe()).access,
        DashboardAccess.accessGate,
      );
    });

    test('a same-origin redirect means browser-only sign-in', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => const FakeReply(302, headers: {'location': '/login'}),
      );
      expect(
        (await connection.auth.probe()).access,
        DashboardAccess.browserOnly,
      );
    });

    test('no providers means an open dashboard', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.json({'providers': <Object>[]}),
      );
      expect((await connection.auth.probe()).access, DashboardAccess.open);
    });

    test('OAuth-only providers mean browser-only sign-in', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.json({
          'providers': [
            {'name': 'google', 'supports_password': false},
          ],
        }),
      );
      expect(
        (await connection.auth.probe()).access,
        DashboardAccess.browserOnly,
      );
    });

    test('an HTML page is not a dashboard', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.html('<html>router admin</html>'),
      );
      expect((await connection.auth.probe()).access, DashboardAccess.notHermes);
    });

    test('an older dashboard without auth routes is open', () async {
      http.on('GET', '/api/status', (_) => FakeReply.json({'version': '0.7'}));
      final probe = await connection.auth.probe();
      expect(probe.access, DashboardAccess.open);
      expect(probe.version, '0.7');
    });

    test('a host answering 404 everywhere is not a dashboard', () async {
      final probe = await connection.auth.probe();
      expect(probe.access, DashboardAccess.notHermes);
    });
  });

  group('signIn', () {
    test('sends the basic provider with both fields', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => FakeReply.json({'ok': true}),
      );
      final result = await connection.auth.signIn(
        username: 'me',
        password: 'pw',
      );
      expect(result.isOk, isTrue);
      expect(http.requests.single.data, {
        'provider': 'basic',
        'username': 'me',
        'password': 'pw',
      });
    });

    test('a same-origin redirect after login is a success', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => const FakeReply(303, headers: {'location': '/'}),
      );
      expect(
        (await connection.auth.signIn(username: 'me', password: 'pw')).isOk,
        isTrue,
      );
    });

    test('a 401 is an unauthorized failure', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => FakeReply.json({'detail': 'Invalid credentials'}, status: 401),
      );
      final result = await connection.auth.signIn(
        username: 'me',
        password: 'no',
      );
      expect(result.failureOrNull?.kind, FailureKind.unauthorized);
    });

    test('the session cookie rides the ticket request', () async {
      http
        ..on(
          'POST',
          '/auth/password-login',
          (_) => FakeReply.json(
            {'ok': true},
            headers: {'set-cookie': 'hermes_session=abc; Path=/; HttpOnly'},
          ),
        )
        ..on(
          'POST',
          '/api/auth/ws-ticket',
          (_) => FakeReply.json({'ticket': 't1'}),
        );
      await connection.auth.signIn(username: 'me', password: 'pw');
      final ticket = await connection.auth.mintTicket();
      expect(ticket.valueOrNull, 't1');
      final cookie = http.to('/api/auth/ws-ticket').single.headers['cookie'];
      expect('$cookie', contains('hermes_session=abc'));
    });
  });

  group('mintTicket', () {
    test('an empty ticket is malformed', () async {
      http.on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => FakeReply.json({'ticket': '  '}),
      );
      expect(
        (await connection.auth.mintTicket()).failureOrNull?.kind,
        FailureKind.malformed,
      );
    });

    test('a redirect to the login page means the session expired', () async {
      http.on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => const FakeReply(302, headers: {'location': '/login'}),
      );
      expect(
        (await connection.auth.mintTicket()).failureOrNull?.kind,
        FailureKind.unauthorized,
      );
    });

    test('an access gate stays an access gate', () async {
      http.on('POST', '/api/auth/ws-ticket', (_) => FakeReply.cloudflareLogin());
      expect(
        (await connection.auth.mintTicket()).failureOrNull?.kind,
        FailureKind.accessGate,
      );
    });
  });
}
