/// The seam between the voice layer and a real audio WebSocket.
///
/// Unlike the RPC `WireSocket`, an audio socket carries both text frames
/// (control JSON) and binary frames (PCM), so frames are typed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/json.dart';

sealed class AudioFrame {
  const AudioFrame();
}

/// A control frame, decoded.
final class AudioText extends AudioFrame {
  const AudioText(this.json);

  final Json json;
}

/// A binary frame: PCM in either direction.
final class AudioBytes extends AudioFrame {
  const AudioBytes(this.bytes);

  final Uint8List bytes;
}

abstract interface class AudioSocket {
  /// Frames from the server. Single-subscription; ends when the socket closes
  /// for any reason.
  Stream<AudioFrame> get frames;

  /// Sends one control frame. Throws if the socket is already closed.
  void sendJson(Map<String, Object?> json);

  /// Sends one binary frame. Throws if the socket is already closed.
  void sendBytes(Uint8List bytes);

  Future<void> close();
}

/// Opens a socket to [uri] with extra handshake [headers].
typedef AudioConnector =
    Future<AudioSocket> Function(Uri uri, Map<String, String> headers);

/// The production socket, over `dart:io`.
final class IoAudioSocket implements AudioSocket {
  IoAudioSocket._(this._socket);

  static Future<AudioSocket> connect(
    Uri uri,
    Map<String, String> headers, {
    HttpClient? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // A transport-level ping finds a half-open connection (a phone that
    // changed networks) without spending a frame on it.
    return IoAudioSocket._(
      (await WebSocket.connect(
        uri.toString(),
        headers: headers,
        customClient: client,
      ).timeout(timeout))..pingInterval = const Duration(seconds: 20),
    );
  }

  final WebSocket _socket;

  @override
  Stream<AudioFrame> get frames => _socket
      .map<AudioFrame?>(
        (Object? message) => switch (message) {
          final String text => AudioText(Json.decode(text)),
          final Uint8List bytes => AudioBytes(bytes),
          final List<int> bytes => AudioBytes(Uint8List.fromList(bytes)),
          _ => null,
        },
      )
      .where((frame) => frame != null)
      .cast<AudioFrame>();

  @override
  void sendJson(Map<String, Object?> json) => _socket.add(jsonEncode(json));

  @override
  void sendBytes(Uint8List bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close(1000);
  }
}
