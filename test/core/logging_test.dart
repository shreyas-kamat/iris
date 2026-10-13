/// Secrets the dashboard transport introduces must never reach a log.
///
/// A WebSocket ticket is a short-lived bearer credential embedded in a URL, and
/// an Access client secret is a long-lived one sent as a header. Both appear in
/// exception messages from the HTTP and socket layers, which are logged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/logging.dart';

void main() {
  group('redaction', () {
    test('a websocket ticket in a URL is removed', () {
      final out = IrisLog.redact(
        "Connection to 'wss://h.example/api/ws?ticket=abc123def' failed",
      );
      expect(out, isNot(contains('abc123def')));
      expect(out, contains('ticket=<redacted>'));
    });

    test('a ticket in a JSON body is removed', () {
      expect(
        IrisLog.redact('{"ticket":"abc123def"}'),
        '{"ticket":"<redacted>"}',
      );
    });

    test('a Cloudflare Access secret header is removed', () {
      final out = IrisLog.redact('CF-Access-Client-Secret: s3cr3tvalue');
      expect(out, isNot(contains('s3cr3tvalue')));
    });
  });

  group('access gate failures', () {
    test('are connection level and not retryable', () {
      const failure = IrisFailure(FailureKind.accessGate);
      expect(failure.isConnectionLevel, isTrue);
      expect(failure.isRetryable, isFalse);
    });
  });
}
