/// What a server's secrets look like, and that they never print themselves.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/net/credentials.dart';

void main() {
  const full = ServerSecrets(
    username: 'me',
    password: 'pw',
    accessClientId: 'abc.access',
    accessClientSecret: 'shh',
  );

  test('round-trips through JSON', () {
    expect(ServerSecrets.fromJson(Json.of(full.toJson())), full);
  });

  test('toString never contains a value', () {
    final text = full.toString();
    for (final secret in ['me', 'pw', 'abc.access', 'shh']) {
      expect(text, isNot(contains(secret)));
    }
  });

  test('a login needs both a username and a password', () {
    expect(const ServerSecrets(username: 'me').hasLogin, isFalse);
    expect(const ServerSecrets(password: 'pw').hasLogin, isFalse);
    expect(full.hasLogin, isTrue);
  });

  test('an Access token needs both halves, and yields both headers', () {
    expect(const ServerSecrets(accessClientId: 'a').hasAccessToken, isFalse);
    expect(full.accessHeaders, {
      'CF-Access-Client-Id': 'abc.access',
      'CF-Access-Client-Secret': 'shh',
    });
    expect(ServerSecrets.none.accessHeaders, isEmpty);
  });
}
