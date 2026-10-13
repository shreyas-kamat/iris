/// The REST boundary in front of a dashboard that may sit behind Cloudflare
/// Access.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/api_client.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;

  setUp(() => http = FakeHttp());

  ServerConnection connect(
    String baseUrl, {
    ServerSecrets secrets = ServerSecrets.none,
  }) {
    final connection = ServerConnection.create(
      ServerConfig(id: 's', baseUrl: baseUrl, label: 'S'),
      secrets: secrets,
      adapter: http,
    );
    addTearDown(connection.close);
    return connection;
  }

  const token = ServerSecrets(
    accessClientId: 'abc.access',
    accessClientSecret: 'shh',
  );

  test('the Access token rides every https request', () async {
    http.on('GET', '/api/status', (_) => FakeReply.json({'version': '1'}));
    await connect('https://h.example', secrets: token).client.get('/api/status');
    final headers = http.requests.single.headers;
    expect(headers['CF-Access-Client-Id'], 'abc.access');
    expect(headers['CF-Access-Client-Secret'], 'shh');
  });

  test('the Access token is never sent over http', () async {
    http.on('GET', '/api/status', (_) => FakeReply.json({'version': '1'}));
    await connect(
      'http://192.168.1.20:9119',
      secrets: token,
    ).client.get('/api/status');
    final headers = http.requests.single.headers;
    expect(headers.containsKey('CF-Access-Client-Id'), isFalse);
    expect(headers.containsKey('CF-Access-Client-Secret'), isFalse);
  });

  test('an Access login redirect is an access gate, not a success', () async {
    http.on('GET', '/api/status', (_) => FakeReply.cloudflareLogin());
    final result = await connect('https://h.example').client.get('/api/status');
    expect(result.failureOrNull?.kind, FailureKind.accessGate);
    expect(http.requests, hasLength(1), reason: 'redirects are not followed');
  });

  test('any other redirect is a rejection carrying its status', () async {
    http.on(
      'GET',
      '/api/status',
      (_) => const FakeReply(302, headers: {'location': '/login'}),
    );
    final result = await connect('https://h.example').client.get('/api/status');
    expect(result.failureOrNull?.kind, FailureKind.rejected);
    expect(result.failureOrNull?.statusCode, 302);
  });

  test('a FastAPI detail message is surfaced', () async {
    http.on(
      'POST',
      '/auth/password-login',
      (_) => FakeReply.json({'detail': 'Invalid credentials'}, status: 401),
    );
    final result = await connect(
      'https://h.example',
    ).client.post('/auth/password-login', body: {'username': 'x'});
    expect(result.failureOrNull?.kind, FailureKind.unauthorized);
    expect(result.failureOrNull?.message, 'Invalid credentials');
  });

  group('isAccessGate', () {
    test('recognises the challenge header on any status', () {
      expect(
        ApiClient.isAccessGate(401, challenge: 'Cloudflare-Access realm=x'),
        isTrue,
      );
    });

    test('recognises a cdn-cgi access path on a custom domain', () {
      expect(
        ApiClient.isAccessGate(
          302,
          location: 'https://auth.example.com/cdn-cgi/access/login/h',
        ),
        isTrue,
      );
    });

    test('ignores a same-origin redirect', () {
      expect(ApiClient.isAccessGate(302, location: '/login'), isFalse);
    });
  });
}
