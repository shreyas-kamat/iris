/// What each connection mode is called and how it is explained.
library;

import 'package:flutter/material.dart';

import '../../data/net/connection_mode.dart';

extension ConnectionModeCopy on ConnectionMode {
  String get title => switch (this) {
    ConnectionMode.lan => 'Same Wi-Fi',
    ConnectionMode.tailscale => 'Tailscale',
    ConnectionMode.cloudflare => 'Cloudflare',
  };

  /// One line under the title on the welcome screen.
  String get line => switch (this) {
    ConnectionMode.lan => 'Your phone and server are on the same network',
    ConnectionMode.tailscale =>
      'Reach your server from anywhere over your tailnet',
    ConnectionMode.cloudflare =>
      'Your dashboard is published through Cloudflare Access',
  };

  /// The address field's hint.
  String get example => switch (this) {
    ConnectionMode.lan => 'http://192.168.1.20:9119',
    ConnectionMode.tailscale => 'http://100.101.102.103:9119',
    ConnectionMode.cloudflare => 'https://hermes.example.com',
  };

  /// Guidance under the address field.
  String get help => switch (this) {
    ConnectionMode.lan =>
      "The server's address on your network and the dashboard's port, "
          "usually 9119. Your router's device list, or ip addr on the "
          'server, shows it.',
    ConnectionMode.tailscale =>
      "Open the Tailscale app and copy your server's address, then add the "
          "dashboard's port, usually 9119. A https://….ts.net name works too.",
    ConnectionMode.cloudflare =>
      'The address you open in a browser. If Cloudflare Access protects it, '
          'Iris asks for a service token next.',
  };

  IconData get icon => switch (this) {
    ConnectionMode.lan => Icons.wifi,
    ConnectionMode.tailscale => Icons.hub_outlined,
    ConnectionMode.cloudflare => Icons.cloud_outlined,
  };
}
