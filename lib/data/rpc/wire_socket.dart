/// The seam between the RPC layer and a real WebSocket.
///
/// Small on purpose: text frames in, text frames out, and close. Everything the
/// RPC client does is tested through a fake of this, so no test needs a server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class WireSocket {
  /// Text frames from the server. Single-subscription; ends when the socket
  /// closes, for any reason.
  Stream<String> get frames;

  /// Sends one text frame. Throws if the socket is already closed.
  void send(String text);

  Future<void> close([int code = 1000]);

  /// Null while open.
  int? get closeCode;
}

/// Opens a socket to [uri] with extra handshake [headers].
typedef WireConnector =
    Future<WireSocket> Function(Uri uri, Map<String, String> headers);

/// The production socket, over `dart:io`.
final class IoWireSocket implements WireSocket {
  IoWireSocket._(this._socket);

  static Future<WireSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
    HttpClient? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // A transport-level ping finds a half-open connection — a phone that
    // changed networks — without spending an RPC on it.
    return IoWireSocket._(
      (await WebSocket.connect(
        uri.toString(),
        headers: headers,
        customClient: client,
      ).timeout(timeout))..pingInterval = const Duration(seconds: 20),
    );
  }

  final WebSocket _socket;

  @override
  Stream<String> get frames => _socket
      .map<String>(
        (Object? message) => switch (message) {
          final String text => text,
          final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
          _ => '',
        },
      )
      .where((text) => text.isNotEmpty);

  @override
  void send(String text) => _socket.add(text);

  @override
  Future<void> close([int code = 1000]) async {
    await _socket.close(code);
  }

  @override
  int? get closeCode => _socket.closeCode;
}
