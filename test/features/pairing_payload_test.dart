import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/servers/pairing_payload.dart';

ServerPairing pairing(String raw) =>
    PairingPayload.parse(raw) as ServerPairing;

String reason(String raw) =>
    (PairingPayload.parse(raw) as UnreadablePayload).reason;

void main() {
  group('plain addresses', () {
    test('an https URL is the common case and just works', () {
      final result = pairing('https://hermes.example.com');
      expect(result.baseUrl, 'https://hermes.example.com');
      expect(result.carriesPassword, isFalse);
      expect(result.insecure, isFalse);
    });

    test('a port is kept', () {
      expect(pairing('https://10.0.0.4:8787').baseUrl, 'https://10.0.0.4:8787');
    });

    test('a path is dropped, because a code names a server not a page', () {
      // Keeping it would make every later API call resolve underneath it.
      expect(
        pairing('https://example.com/chat/session/42').baseUrl,
        'https://example.com',
      );
    });

    test('http is accepted but flagged', () {
      final result = pairing('http://192.168.1.50:8787');
      expect(result.insecure, isTrue);
      expect(result.isInsecureRemote, isTrue);
    });

    test('plaintext to this device is not flagged as remote', () {
      expect(pairing('http://localhost:8787').isInsecureRemote, isFalse);
      expect(pairing('http://127.0.0.1:8787').isInsecureRemote, isFalse);
    });

    test('surrounding whitespace from a scan is tolerated', () {
      expect(pairing('  https://example.com \n').baseUrl, 'https://example.com');
    });
  });

  group('the iris:// format', () {
    test('carries an address', () {
      final result = pairing(
        'iris://connect?url=https%3A%2F%2Fhermes.example.com',
      );
      expect(result.baseUrl, 'https://hermes.example.com');
    });

    test('carries an optional label', () {
      expect(
        pairing(
          'iris://connect?url=https%3A%2F%2Fa.example.com&label=Home%20server',
        ).label,
        'Home server',
      );
    });

    test('a password is surfaced, not silently used', () {
      final result = pairing(
        'iris://connect?url=https%3A%2F%2Fa.example.com&password=hunter2',
      );
      expect(result.carriesPassword, isTrue);
      expect(result.password, 'hunter2');
    });

    test('an empty password counts as absent', () {
      expect(
        pairing('iris://connect?url=https%3A%2F%2Fa.example.com&password=')
            .carriesPassword,
        isFalse,
      );
    });

    test('the scheme-less short form is accepted', () {
      expect(
        pairing('iris:connect?url=https%3A%2F%2Fa.example.com').baseUrl,
        'https://a.example.com',
      );
    });

    test('a bare host in the url parameter defaults to https', () {
      // Defaulting to http on a guessed address would put a password on the
      // wire in the clear.
      expect(pairing('iris://connect?url=a.example.com').baseUrl.startsWith('https://'), isTrue);
    });
  });

  group('codes Iris will not act on', () {
    test('an unknown iris action is named rather than ignored', () {
      expect(reason('iris://wipe?url=https%3A%2F%2Fa.com'), contains('wipe'));
    });

    test('an iris code with no server says so', () {
      expect(reason('iris://connect'), contains('does not name a server'));
    });

    test('a non-web scheme is identified', () {
      // The most likely mis-scan: a Wi-Fi or contact card code.
      expect(reason('WIFI:S:MyNetwork;T:WPA;P:secret;;'), contains('not a server'));
      expect(reason('mailto:someone@example.com'), contains('not a server'));
    });

    test('a tunnelled scheme Iris cannot speak is refused', () {
      expect(reason('iris://connect?url=ftp%3A%2F%2Fa.com'), contains('ftp'));
    });

    test('plain text is not mistaken for an address', () {
      expect(reason('just some text'), isNotEmpty);
      expect(reason(''), contains('empty'));
    });

    test('an address with no host is refused', () {
      expect(reason('https://'), isNotEmpty);
    });
  });

  test('parsing never throws, whatever is scanned', () {
    // A scanner hands over whatever the camera decoded, including binary junk.
    const nasty = [
      '',
      ' ',
      '://',
      'iris://',
      'https://[',
      'iris://connect?url=%%%',
      'data:text/html,<script>',
      'https://example.com:notaport',
    ];
    for (final input in nasty) {
      expect(
        () => PairingPayload.parse(input),
        returnsNormally,
        reason: 'failed on: $input',
      );
    }
  });
}
