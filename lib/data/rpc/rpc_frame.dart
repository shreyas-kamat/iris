/// The dashboard's JSON-RPC 2.0 frames, as values.
///
/// Four things arrive on the socket: responses to Iris's requests (integer
/// ids), stream events (`method: "event"`), requests the gateway makes of Iris
/// (string ids such as `srq-1a2b`), and anything else. Parsing never throws:
/// a frame Iris cannot read becomes [RpcUnreadable] and is logged and dropped,
/// because one malformed frame must not take the connection down.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/json.dart';

/// Error codes Iris writes or recognises.
abstract final class RpcCodes {
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
}

/// An error the gateway returned for a request.
@immutable
final class RpcError {
  const RpcError({required this.message, this.code, this.reason});

  factory RpcError.fromJson(Json json) => RpcError(
    code: json['code'].intOrNull,
    message: json['message'].stringOrNull ?? 'The server reported an error.',
    reason: json['data']['reason'].stringOrNull,
  );

  final int? code;

  /// For people. Never parsed except by [isMethodNotFound].
  final String message;

  /// Machine-readable, from `data.reason` — for example `SESSION_NOT_OWNED`.
  final String? reason;

  /// Whether the gateway does not know the method. Older gateways phrase it
  /// differently, so the wording is matched as well as the code, as Hermes
  /// Desktop does.
  bool get isMethodNotFound {
    if (code == RpcCodes.methodNotFound) return true;
    final lowered = message.toLowerCase();
    return lowered.contains('method not found') ||
        lowered.contains('-32601') ||
        lowered.contains('unknown method') ||
        lowered.contains('no such method');
  }

  @override
  String toString() =>
      'RpcError($code, $message${reason == null ? '' : ', $reason'})';
}

/// Reads the [RpcError] behind a failure from an RPC call, if any.
extension RpcFailure on IrisFailure {
  RpcError? get rpcError => switch (cause) {
    final RpcError error => error,
    _ => null,
  };
}

/// One inbound frame.
sealed class RpcFrame {
  const RpcFrame();

  factory RpcFrame.parse(String text) {
    final json = Json.decode(text);
    if (!json.isMap) return const RpcUnreadable('not a JSON object');

    final method = json['method'].stringOrNull;
    final id = json['id'].raw;

    if (method == 'event') {
      final params = json['params'];
      final type = params['type'].stringOrNull;
      if (type == null || type.isEmpty) {
        return const RpcUnreadable('event without a type');
      }
      return RpcEvent(
        type: type,
        sessionId: params['session_id'].stringOrNull,
        payload: params['payload'],
        raw: params,
      );
    }

    if (method != null) {
      // Server requests carry string ids. An integer id could collide with one
      // of Iris's own requests, so such a frame is neither settled nor answered.
      if (id is String && id.isNotEmpty) {
        return RpcServerRequest(id: id, method: method, params: json['params']);
      }
      return RpcUnreadable('server request $method without a string id');
    }

    if (id is int) {
      final error = json['error'];
      return RpcResponse(
        id: id,
        result: json['result'],
        error: error.isMap ? RpcError.fromJson(error) : null,
      );
    }

    return const RpcUnreadable('neither a response, an event nor a request');
  }
}

/// The answer to one of Iris's requests.
final class RpcResponse extends RpcFrame {
  const RpcResponse({required this.id, required this.result, this.error});

  final int id;
  final Json result;
  final RpcError? error;
}

/// A stream event: agent output, tool progress, session changes.
final class RpcEvent extends RpcFrame {
  const RpcEvent({
    required this.type,
    required this.payload,
    required this.raw,
    this.sessionId,
  });

  /// For example `message.delta`, `tool.start`, `gateway.ready`.
  final String type;

  /// The session it belongs to, when it belongs to one.
  final String? sessionId;
  final Json payload;

  /// The whole `params` object, for fields this build does not read.
  final Json raw;
}

/// Something the gateway asks Iris: an approval, a clarifying question, a
/// secret. Answered by a frame echoing [id].
final class RpcServerRequest extends RpcFrame {
  const RpcServerRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final String id;
  final String method;
  final Json params;
}

/// A frame Iris could not read, kept only to be logged.
final class RpcUnreadable extends RpcFrame {
  const RpcUnreadable(this.reason);

  final String reason;
}

/// Outbound frames.
abstract final class RpcEncode {
  /// A request. `params` is omitted when empty: the gateway's contract check
  /// treats an explicit empty object and an absent one differently on some
  /// methods.
  static String request(int id, String method, Map<String, Object?>? params) =>
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
      });

  /// Declines a server request.
  static String errorReply(String id, int code, String message) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });

  /// Answers a server request with [result].
  static String resultReply(String id, Map<String, Object?> result) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});
}
