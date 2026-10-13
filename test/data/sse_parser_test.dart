import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/sse/sse_frame.dart';
import 'package:iris/data/sse/sse_parser.dart';

/// Feeds [chunks] through the parser exactly as written, so tests can control
/// where the network would have split the byte stream.
Future<List<SseFrame>> parseChunks(
  List<String> chunks, {
  void Function(String)? onComment,
}) => Stream<List<int>>.fromIterable(
  chunks.map(utf8.encode),
).transform(SseParser(onComment: onComment)).toList();

Future<List<SseFrame>> parse(String body, {void Function(String)? onComment}) =>
    parseChunks([body], onComment: onComment);

void main() {
  group('framing', () {
    test('a blank line dispatches the accumulated block', () async {
      final frames = await parse('event: token\ndata: {"text":"hi"}\n\n');
      expect(frames, hasLength(1));
      expect(frames.single.event, 'token');
      expect(frames.single.json['text'].string(), 'hi');
    });

    test('multiple data lines join with newlines', () async {
      final frames = await parse('event: token\ndata: one\ndata: two\n\n');
      expect(frames.single.data, 'one\ntwo');
    });

    test('an omitted event field defaults to "message"', () async {
      final frames = await parse('data: bare\n\n');
      expect(frames.single.event, 'message');
    });

    test('a frame split across chunks is reassembled', () async {
      // The realistic failure: one logical frame arriving as several TCP reads,
      // with the split falling inside a field value.
      final frames = await parseChunks([
        'event: to',
        'ken\ndata: {"te',
        'xt":"hello"}\n',
        '\n',
      ]);
      expect(frames, hasLength(1));
      expect(frames.single.event, 'token');
      expect(frames.single.json['text'].string(), 'hello');
    });

    test(
      'a multi-byte character split across chunks is not corrupted',
      () async {
        final bytes = utf8.encode('event: token\ndata: né\n\n');
        final frames = await Stream<List<int>>.fromIterable([
          bytes.sublist(0, 20),
          bytes.sublist(20),
        ]).transform(const SseParser()).toList();
        expect(frames.single.data, 'né');
      },
    );

    test('all three line terminators are accepted', () async {
      final crlf = await parse('event: a\r\ndata: 1\r\n\r\n');
      final cr = await parse('event: a\rdata: 1\r\r');
      final lf = await parse('event: a\ndata: 1\n\n');
      expect([crlf, cr, lf].map((f) => f.single.data), everyElement('1'));
    });

    test('an unterminated trailing block is discarded', () async {
      // Half a frame is indistinguishable from a truncated one, and rendering
      // it could show a partial tool result as though it were complete.
      final frames = await parse(
        'event: token\ndata: {"text":"hi"}\n\nevent: t',
      );
      expect(frames, hasLength(1));
    });
  });

  group('fields', () {
    test('exactly one leading space after the colon is stripped', () async {
      final one = await parse('data: value\n\n');
      final none = await parse('data:value\n\n');
      final two = await parse('data:  value\n\n');
      expect(one.single.data, 'value');
      expect(none.single.data, 'value');
      expect(
        two.single.data,
        ' value',
        reason: 'only the first space is sugar',
      );
    });

    test('a line with no colon is a field with an empty value', () async {
      final frames = await parse('event\ndata: x\n\n');
      expect(frames.single.event, 'message');
    });

    test('retry is parsed as a duration', () async {
      final frames = await parse('retry: 2500\ndata: x\n\n');
      expect(frames.single.retry, const Duration(milliseconds: 2500));
    });

    test('unknown fields are ignored, not fatal', () async {
      final frames = await parse('event: token\nfuture: 1\ndata: x\n\n');
      expect(frames.single.event, 'token');
      expect(frames.single.data, 'x');
    });
  });

  group('comments', () {
    test('a heartbeat produces no frame but is reported', () async {
      final comments = <String>[];
      final frames = await parse(
        ': heartbeat\n\nevent: token\ndata: x\n\n',
        onComment: comments.add,
      );
      expect(frames, hasLength(1));
      expect(comments, ['heartbeat']);
    });

    test('a stream of only heartbeats yields no frames', () async {
      final comments = <String>[];
      final frames = await parse(
        ': heartbeat\n\n: heartbeat\n\n',
        onComment: comments.add,
      );
      expect(frames, isEmpty);
      expect(comments, hasLength(2));
    });
  });

  group('event ids', () {
    test(
      'the last id persists across later frames for Last-Event-ID',
      () async {
        final frames = await parse(
          'id: s1:1\nevent: token\ndata: a\n\n'
          'event: token\ndata: b\n\n',
        );
        expect(frames.map((f) => f.id), ['s1:1', 's1:1']);
      },
    );

    test('an id containing NUL is ignored per spec', () async {
      final nul = String.fromCharCode(0);
      final frames = await parse('id: bad${nul}id\nevent: token\ndata: a\n\n');
      expect(frames.single.id, isNull);
    });
  });

  test('a payload-free event still dispatches', () async {
    // Deliberate spec deviation: stream_end carries no data, and dropping it
    // would leave the transcript spinning on a finished turn.
    final frames = await parse('event: stream_end\n\n');
    expect(frames, hasLength(1));
    expect(frames.single.event, 'stream_end');
  });

  test('a non-JSON payload yields Json.missing rather than throwing', () async {
    final frames = await parse('event: token\ndata: <html>oops</html>\n\n');
    expect(frames.single.json.exists, isFalse);
  });
}
