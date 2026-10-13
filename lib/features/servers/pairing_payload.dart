/// What a pairing QR code contains, and how much of it to trust.
///
/// hermes-webui does not define a pairing format, so Iris defines one and also
/// accepts the thing people will actually generate: a QR of the plain server
/// address. Both paths end in the same review step.
///
/// The security position matters more than the format. A QR code is an address
/// someone else chose, pointed at a device, and scanning one is not consent to
/// connect. So parsing never connects: it produces a description of what was
/// scanned, the UI shows it, and the person confirms. An attacker who gets a
/// code in front of a camera should get a visible prompt naming their host,
/// not a silent connection.
library;

/// A scanned code that Iris understands.
sealed class PairingPayload {
  const PairingPayload();

  /// Iris's own format, which may also carry a label and a password:
  /// `iris://connect?url=https://host&label=Home&password=...`
  ///
  /// Percent-encoding is required for the nested URL, which is why this is a
  /// query parameter rather than a path.
  static const String scheme = 'iris';

  /// Reads [raw] without acting on it.
  ///
  /// Never throws and never returns null: an unreadable code is a value
  /// describing why, so the scanner can say "that is a Wi-Fi code, not a
  /// server" instead of silently ignoring it.
  factory PairingPayload.parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const UnreadablePayload(reason: 'The code is empty.');

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      return const UnreadablePayload(
        reason: 'That code is not a web address.',
      );
    }

    if (uri.scheme.toLowerCase() == scheme) return _parseIrisUri(uri, text);

    if (uri.scheme.toLowerCase() case 'https' || 'http') {
      if (uri.host.isEmpty) {
        return const UnreadablePayload(reason: 'That address has no host.');
      }
      return ServerPairing(
        baseUrl: _normalise(uri),
        insecure: uri.scheme.toLowerCase() == 'http',
      );
    }

    return UnreadablePayload(
      reason: 'That is a ${uri.scheme} code, not a server address.',
    );
  }

  static PairingPayload _parseIrisUri(Uri uri, String raw) {
    // `iris://connect?...` and `iris:connect?...` both reach here; the action
    // is whichever of host or path is populated.
    final action = (uri.host.isNotEmpty ? uri.host : uri.path)
        .replaceAll('/', '')
        .toLowerCase();
    if (action != 'connect') {
      return UnreadablePayload(
        reason: action.isEmpty
            ? 'That Iris code is missing an action.'
            : 'Iris does not know the action "$action".',
      );
    }

    final target = uri.queryParameters['url'] ?? uri.queryParameters['server'];
    if (target == null || target.trim().isEmpty) {
      return const UnreadablePayload(
        reason: 'That Iris code does not name a server.',
      );
    }

    // A bare host parses with an empty `host` and the text in `path`, so the
    // scheme is supplied before parsing. https, not http: guessing plaintext
    // for an address someone encoded in a QR would put a password on the wire
    // in the clear.
    final trimmed = target.trim();
    final parsed = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    if (parsed == null || parsed.host.isEmpty) {
      return const UnreadablePayload(
        reason: 'That Iris code has an unreadable address.',
      );
    }
    if (parsed.scheme.isNotEmpty &&
        parsed.scheme.toLowerCase() != 'https' &&
        parsed.scheme.toLowerCase() != 'http') {
      return UnreadablePayload(
        reason: 'Iris cannot connect over ${parsed.scheme}.',
      );
    }

    final password = uri.queryParameters['password'];
    return ServerPairing(
      baseUrl: _normalise(parsed),
      label: uri.queryParameters['label']?.trim(),
      password: password == null || password.isEmpty ? null : password,
      insecure: parsed.scheme.toLowerCase() == 'http',
    );
  }

  /// Drops anything after the origin and strips a trailing slash.
  ///
  /// A pairing code's job is to name a server, not a page on it; keeping a path
  /// would make every API call resolve under it.
  static String _normalise(Uri uri) {
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme.toLowerCase();
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port';
  }
}

/// A server worth offering to connect to, once the person confirms.
final class ServerPairing extends PairingPayload {
  const ServerPairing({
    required this.baseUrl,
    this.label,
    this.password,
    this.insecure = false,
  });

  final String baseUrl;
  final String? label;

  /// A password carried in the code.
  ///
  /// Convenient and genuinely risky: anyone who photographs the code has the
  /// password. The UI says so rather than quietly using it.
  final String? password;

  /// Whether the address is plaintext to somewhere other than this device.
  final bool insecure;

  bool get carriesPassword => password != null && password!.isNotEmpty;

  /// The host, for the confirmation prompt. The whole point of the prompt is
  /// that the person reads this and recognises it.
  String get host => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  /// Whether the address is plaintext to a host that is not this device.
  bool get isInsecureRemote {
    if (!insecure) return false;
    return host != 'localhost' && host != '127.0.0.1' && host != '::1';
  }
}

/// A code Iris could not use, with a reason to show.
final class UnreadablePayload extends PairingPayload {
  const UnreadablePayload({required this.reason});

  final String reason;
}
