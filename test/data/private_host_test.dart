/// Which addresses may use plain http, and what scheme a bare address gets.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/net/connection_mode.dart';
import 'package:iris/data/net/private_host.dart';

void main() {
  group('isPrivateHost', () {
    for (final host in [
      '10.0.0.5',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.20',
      '127.0.0.1',
      '100.64.0.1',
      '100.127.255.254',
      'localhost',
      'nas.local',
      'box.tail1234.ts.net',
      'nas',
      '::1',
      '[::1]',
      'fd12:3456::1',
      'fc00::1',
    ]) {
      test('$host is private', () => expect(isPrivateHost(host), isTrue));
    }
    for (final host in [
      '8.8.8.8',
      '172.32.0.1',
      '100.128.0.1',
      '100.63.255.255',
      '192.169.0.1',
      'hermes.example.com',
      'example.local.evil.com',
      '2001:db8::1',
    ]) {
      test('$host is public', () => expect(isPrivateHost(host), isFalse));
    }
  });

  test('https is always allowed; http only for private hosts', () {
    expect(plainHttpAllowed(Uri.parse('https://hermes.example.com')), isTrue);
    expect(plainHttpAllowed(Uri.parse('http://192.168.1.20:9119')), isTrue);
    expect(plainHttpAllowed(Uri.parse('http://hermes.example.com')), isFalse);
  });

  group('addressFor', () {
    test('a bare private address in a LAN or Tailscale mode gets http', () {
      expect(
        addressFor('192.168.1.20:9119', ConnectionMode.lan),
        'http://192.168.1.20:9119',
      );
      expect(
        addressFor(' 100.101.102.103:9119/ ', ConnectionMode.tailscale),
        'http://100.101.102.103:9119',
      );
    });
    test(
      'a bare .ts.net name gets https, which MagicDNS certificates serve',
      () {
        expect(
          addressFor('box.tail1234.ts.net', ConnectionMode.tailscale),
          'https://box.tail1234.ts.net',
        );
      },
    );
    test('Cloudflare and public names default to https', () {
      expect(
        addressFor('hermes.example.com', ConnectionMode.cloudflare),
        'https://hermes.example.com',
      );
      expect(
        addressFor('192.168.1.20:9119', ConnectionMode.cloudflare),
        'https://192.168.1.20:9119',
      );
      expect(
        addressFor('hermes.example.com', ConnectionMode.lan),
        'https://hermes.example.com',
      );
    });
    test('a typed scheme is kept', () {
      expect(
        addressFor('https://192.168.1.20:9119', ConnectionMode.lan),
        'https://192.168.1.20:9119',
      );
    });
  });

  test('modes round-trip through their stored names', () {
    for (final mode in ConnectionMode.values) {
      expect(ConnectionMode.fromStoredName(mode.storedName), mode);
    }
    expect(ConnectionMode.fromStoredName(null), isNull);
    expect(ConnectionMode.fromStoredName('carrier-pigeon'), isNull);
  });
}
