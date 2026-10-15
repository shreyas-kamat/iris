/// Which addresses may be reached over plain http.
///
/// A home server on the same Wi-Fi or a tailnet usually has no certificate,
/// so http has to work there. Anywhere else it would put the password and the
/// conversation on the open internet in the clear, so it is refused.
library;

import 'connection_mode.dart';
import 'server_config.dart';

/// Whether [host] is on this device, the local network, or a tailnet.
bool isPrivateHost(String host) {
  var name = host.trim().toLowerCase();
  if (name.startsWith('[') && name.endsWith(']')) {
    name = name.substring(1, name.length - 1);
  }
  if (name.isEmpty) return false;
  if (name == 'localhost' ||
      name.endsWith('.local') ||
      name.endsWith('.ts.net')) {
    return true;
  }
  if (name.contains(':')) return _privateIpv6(name);
  final octets = name.split('.');
  if (octets.length == 4 &&
      octets.every((part) => int.tryParse(part) != null)) {
    return _privateIpv4([for (final part in octets) int.parse(part)]);
  }
  // A single label, such as `nas`, only resolves on the local network.
  return !name.contains('.');
}

bool _privateIpv4(List<int> octets) {
  if (octets.any((octet) => octet < 0 || octet > 255)) return false;
  final [a, b, _, _] = octets;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      // Tailscale's CGNAT range, 100.64.0.0/10.
      (a == 100 && b >= 64 && b <= 127);
}

bool _privateIpv6(String address) {
  if (address == '::1') return true;
  // Unique local addresses, fc00::/7.
  return address.startsWith('fc') || address.startsWith('fd');
}

/// Whether Iris may connect to [uri]: always over https, over http only to a
/// private host.
bool plainHttpAllowed(Uri uri) =>
    uri.scheme != 'http' || isPrivateHost(uri.host);

/// The address to use for what was typed in [mode].
///
/// A bare private address in a LAN or Tailscale mode gets http, because that
/// is what a home server without a certificate speaks; the general rule in
/// [ServerConfig.normaliseBaseUrl] would make it https and fail. A `.ts.net`
/// name keeps https, which Tailscale serves with real certificates.
String addressFor(String input, ConnectionMode mode) {
  final typed = input.trim();
  if (typed.isEmpty ||
      typed.contains('://') ||
      mode == ConnectionMode.cloudflare) {
    return ServerConfig.normaliseBaseUrl(typed);
  }
  final host = Uri.tryParse('http://$typed')?.host ?? '';
  final plain = isPrivateHost(host) && !host.endsWith('.ts.net');
  return ServerConfig.normaliseBaseUrl(plain ? 'http://$typed' : typed);
}
