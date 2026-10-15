# Cleartext check (2026-10-15)

Release build on the Pixel 9 emulator, address `http://10.0.2.2:8799` (a Python HTTP server on the host).

- Result: **allowed**. Evidence: the app showed "Not a Hermes dashboard", and the server's log recorded the app's
  own requests, `GET /api/auth/providers` and `GET /api/status`, both answered 404.
- Android change: none. Dio uses dart:io sockets, which Android's cleartext policy does not govern here.
- iOS: `NSLocalNetworkUsageDescription` added, which iOS requires before any connection to the local network. Not
  tested on a device: there is no Mac here. Dio uses dart:io sockets, which App Transport Security does not cover,
  so no ATS exception was added.
