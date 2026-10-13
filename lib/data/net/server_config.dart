/// How to reach one Hermes dashboard.
///
/// Iris supports several servers — a laptop at home, a VPS, a work machine —
/// so the base URL is never a global constant. Credentials live in secure
/// storage and are attached by the auth interceptor; they are deliberately not
/// fields on this object, which is passed around freely and logged.
library;

import '../../core/json.dart';

/// A server the user has added, without its secrets.
final class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.baseUrl,
    required this.label,
    this.requiresPassword = false,
    this.usesAccessToken = false,
    this.allowSelfSignedCertificate = false,
  });

  factory ServerConfig.fromJson(Json json) => ServerConfig(
    id: json['id'].string(),
    baseUrl: json['base_url'].string(),
    label: json['label'].string(),
    requiresPassword: json['requires_password'].boolean(),
    usesAccessToken: json['uses_access_token'].boolean(),
    allowSelfSignedCertificate: json['allow_self_signed'].boolean(),
  );

  /// Stable local identifier. Also the secure-storage key for this server's
  /// password, so it must never be reused across servers.
  final String id;

  /// Normalised origin, without a trailing slash.
  final String baseUrl;

  /// What the user calls this server.
  final String label;

  /// Whether the dashboard wants a username and password.
  final bool requiresPassword;

  /// Whether requests carry a Cloudflare Access service token.
  final bool usesAccessToken;

  /// Whether to accept a certificate that does not chain to a trusted root.
  ///
  /// Off by default and only ever set by an explicit, warned choice: home
  /// servers behind a self-signed cert are common, but silently accepting one
  /// would defeat the point of using HTTPS at all.
  final bool allowSelfSignedCertificate;

  Uri get uri => Uri.parse(baseUrl);

  bool get isSecure => uri.scheme == 'https';

  /// Whether the connection is plaintext to somewhere other than this device.
  /// Plain HTTP to a loopback address is fine; to a LAN or public host it means
  /// the prompt text and any token are on the wire in the clear.
  bool get isInsecureRemote {
    if (isSecure) return false;
    final host = uri.host;
    return host != 'localhost' && host != '127.0.0.1' && host != '::1';
  }

  /// Trims whitespace, adds a scheme if the user omitted one, and strips a
  /// trailing slash so paths can be appended without doubling separators.
  static String normaliseBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'https://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'base_url': baseUrl,
    'label': label,
    'requires_password': requiresPassword,
    'uses_access_token': usesAccessToken,
    'allow_self_signed': allowSelfSignedCertificate,
  };

  ServerConfig copyWith({
    String? baseUrl,
    String? label,
    bool? requiresPassword,
    bool? usesAccessToken,
    bool? allowSelfSignedCertificate,
  }) => ServerConfig(
    id: id,
    baseUrl: baseUrl ?? this.baseUrl,
    label: label ?? this.label,
    requiresPassword: requiresPassword ?? this.requiresPassword,
    usesAccessToken: usesAccessToken ?? this.usesAccessToken,
    allowSelfSignedCertificate:
        allowSelfSignedCertificate ?? this.allowSelfSignedCertificate,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ServerConfig && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServerConfig($label, $baseUrl)';
}
