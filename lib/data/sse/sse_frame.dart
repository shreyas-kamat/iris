/// One dispatched Server-Sent Events frame, still at the wire level.
///
/// This is the transport's vocabulary — `event`, `data`, `id`, `retry` — with no
/// knowledge of Hermes. Turning a frame into a typed Hermes event happens a
/// layer up, in `stream_event.dart`, so the parser stays testable against the
/// SSE specification alone.
library;

import '../../core/json.dart';

/// A frame the server dispatched by terminating a block with a blank line.
final class SseFrame {
  const SseFrame({
    required this.event,
    required this.data,
    this.id,
    this.retry,
  });

  /// The `event:` field, or `message` when the server omitted it, per spec.
  final String event;

  /// The concatenated `data:` lines, joined with newlines and with the trailing
  /// newline removed.
  final String data;

  /// The `id:` field, if present. Opaque — Iris echoes it back in
  /// `Last-Event-ID` on reconnect and never parses its structure.
  final String? id;

  /// A `retry:` field, if the server supplied a new reconnection delay.
  final Duration? retry;

  /// The payload decoded as JSON, or [Json.missing] if it is not valid JSON.
  ///
  /// Hermes sends JSON objects for every event, but a proxy inserting an error
  /// page, or a truncated final frame, must not throw here.
  Json get json => Json.decode(data);

  @override
  String toString() =>
      'SseFrame($event, ${data.length} bytes${id == null ? '' : ', id=$id'})';
}
