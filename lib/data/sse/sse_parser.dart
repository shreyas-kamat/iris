/// A Server-Sent Events parser built to the WHATWG event-stream rules.
///
/// Written by hand rather than pulled from a package because the streaming
/// transcript is the heart of Iris and its failure modes have to be understood
/// exactly: how a frame split across two TCP chunks is reassembled, what a
/// heartbeat comment does, which fields survive a reconnect. Everything here is
/// driven by the specification, not by what Hermes happens to send today.
///
/// Usage:
/// ```dart
/// response.stream.transform(const SseParser()).listen(handleFrame);
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'sse_frame.dart';

/// Transforms a raw byte stream into dispatched [SseFrame]s.
///
/// Handles UTF-8 sequences and frames that straddle chunk boundaries, all three
/// line terminators, comment lines, and the `retry` field. Comment lines — which
/// is how Hermes sends its 30-second heartbeat — produce no frame but do surface
/// through [SseParser.onComment] so a liveness watchdog can be fed.
final class SseParser extends StreamTransformerBase<List<int>, SseFrame> {
  const SseParser({this.onComment});

  /// Invoked for each `:comment` line, with the text after the colon.
  ///
  /// A live connection that has produced nothing but heartbeats for minutes is
  /// healthy; one that has produced nothing at all is not. The chat layer uses
  /// this to tell those apart.
  final void Function(String comment)? onComment;

  @override
  Stream<SseFrame> bind(Stream<List<int>> stream) {
    // `utf8.decoder` carries partial multi-byte sequences across chunks, and
    // LineSplitter carries a partial line, so a frame may span any number of
    // network reads without corruption.
    final lines = stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    return _dispatch(lines, onComment);
  }

  static Stream<SseFrame> _dispatch(
    Stream<String> lines,
    void Function(String)? onComment,
  ) async* {
    final builder = SseFrameBuilder();
    await for (final line in lines) {
      if (line.isEmpty) {
        final frame = builder.takeFrame();
        if (frame != null) yield frame;
        continue;
      }
      if (line.startsWith(':')) {
        onComment?.call(_stripLeadingSpace(line.substring(1)));
        continue;
      }
      builder.addLine(line);
    }
    // A stream that ends without a trailing blank line has an undispatched
    // block. The spec discards it; so do we, because a half-received frame is
    // indistinguishable from a truncated one and acting on it risks showing
    // a partial tool result as if it were complete.
  }

  static String _stripLeadingSpace(String value) =>
      value.startsWith(' ') ? value.substring(1) : value;
}

/// Accumulates field lines into a frame. Exposed for direct unit testing of the
/// field rules without constructing a stream.
final class SseFrameBuilder {
  /// The NUL character, built at runtime because a literal one cannot safely
  /// live in a source file. An `id` field containing it must be ignored.
  static final String _nul = String.fromCharCode(0);

  final StringBuffer _data = StringBuffer();
  bool _hasData = false;
  String? _event;
  String? _id;
  Duration? _retry;

  /// The last non-empty `id:` seen. It persists across frames — unlike every
  /// other field, which resets per frame — and is what gets sent as
  /// `Last-Event-ID` when reconnecting. Assignable so a resumed stream can be
  /// seeded with a cursor from a previous connection.
  String? lastEventId;

  /// Feeds one non-empty, non-comment line.
  void addLine(String line) {
    final colon = line.indexOf(':');
    final String field;
    final String value;
    if (colon < 0) {
      // A line with no colon is a field name with an empty value.
      field = line;
      value = '';
    } else {
      field = line.substring(0, colon);
      value = SseParser._stripLeadingSpace(line.substring(colon + 1));
    }

    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        // Multiple data lines join with newlines; the final one is dropped
        // when the frame is taken.
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'id':
        // The spec requires ignoring an id that contains a NUL character.
        if (!value.contains(_nul)) {
          _id = value;
          if (value.isNotEmpty) lastEventId = value;
        }
      case 'retry':
        final millis = int.tryParse(value);
        if (millis != null && millis >= 0) {
          _retry = Duration(milliseconds: millis);
        }
      default:
        // Unknown fields are ignored, which is how a future server can add
        // wire metadata without breaking this client.
        break;
    }
  }

  /// Dispatches the accumulated block, or returns `null` if there was nothing
  /// to dispatch. Resets the per-frame state either way.
  ///
  /// Deliberate spec deviation: the standard discards a block whose data buffer
  /// is empty, even when it named an event. Iris dispatches it. Hermes uses
  /// payload-free events as fences — `stream_end` is the signal to close the
  /// connection — and swallowing one would leave the transcript spinning
  /// forever on a turn the server considers finished.
  SseFrame? takeFrame() {
    final hadContent = _hasData || _event != null;
    final frame = hadContent
        ? SseFrame(
            event: _event?.isNotEmpty == true ? _event! : 'message',
            data: _data.toString(),
            id: _id ?? lastEventId,
            retry: _retry,
          )
        : null;

    _data.clear();
    _hasData = false;
    _event = null;
    _id = null;
    _retry = null;
    return frame;
  }
}
