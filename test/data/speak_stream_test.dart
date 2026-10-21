/// The speak-stream protocol over a scripted socket: text in, PCM out.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/voice/speak_stream.dart';

import '../support/fake_voice.dart';

void main() {
  late FakeAudioSocket socket;
  late SpeakStream stream;
  late List<SpeakFrame> frames;
  late Future<void> listening;

  setUp(() {
    socket = FakeAudioSocket();
    stream = SpeakStream(socket);
    frames = [];
    listening = stream.frames.forEach(frames.add);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('sends text deltas then done', () async {
    stream
      ..add('Hi. ')
      ..add('There.')
      ..done();

    expect(socket.sentJson, [
      {'text': 'Hi. '},
      {'text': 'There.'},
      {'done': true},
    ]);
  });

  test('empty text is not sent', () {
    stream
      ..add('')
      ..add('Hello');
    expect(socket.sentJson, [
      {'text': 'Hello'},
    ]);
  });

  test('whitespace between deltas is kept', () {
    stream
      ..add('one')
      ..add(' ')
      ..add('two');
    expect(socket.sentJson.map((j) => j['text']), ['one', ' ', 'two']);
  });

  test('done is sent once', () {
    stream
      ..done()
      ..done();
    expect(socket.sentJson, [
      {'done': true},
    ]);
  });

  test('start then pcm then end', () async {
    socket
      ..serverSends({'type': 'start', 'sample_rate': 24000, 'channels': 1})
      ..serverSendsBytes(Uint8List.fromList([1, 2, 3, 4]))
      ..serverSendsBytes(Uint8List.fromList([5, 6]))
      ..serverSends({'type': 'end'});
    await listening;

    expect(frames, hasLength(4));
    expect(frames[0], isA<SpeakStart>());
    expect((frames[0] as SpeakStart).sampleRate, 24000);
    expect((frames[0] as SpeakStart).channels, 1);
    expect((frames[1] as SpeakPcm).pcm, [1, 2, 3, 4]);
    expect((frames[2] as SpeakPcm).pcm, [5, 6]);
    expect(frames[3], isA<SpeakEnd>());
  });

  test('a start without a channel count is mono', () async {
    socket
      ..serverSends({'type': 'start', 'sample_rate': 22050})
      ..serverSends({'type': 'end'});
    await listening;
    expect((frames.first as SpeakStart).channels, 1);
  });

  test('a start without a usable rate is ignored, not a crash', () async {
    socket
      ..serverSends({'type': 'start'})
      ..serverSends({'type': 'end'});
    await listening;
    expect(frames, [isA<SpeakEnd>()]);
  });

  test('fallback', () async {
    socket.serverSends({'type': 'fallback'});
    await listening;
    expect(frames, [isA<SpeakFallback>()]);
  });

  test('an error frame is a fallback, so the reply is still spoken', () async {
    socket.serverSends({'type': 'error', 'message': 'tts failed'});
    await listening;
    expect(frames, [isA<SpeakFallback>()]);
  });

  test('unknown frames are ignored', () async {
    socket
      ..serverSends({'type': 'metrics', 'ms': 12})
      ..serverSends({'type': 'end'});
    await listening;
    expect(frames, [isA<SpeakEnd>()]);
  });

  test('stop sends stop and closes', () async {
    await stream.stop();

    expect(socket.sentJson, [
      {'stop': true},
    ]);
    expect(socket.closed, isTrue);
    // The stream ends; nothing more is delivered, not even an end.
    await listening;
    expect(frames, isEmpty);
  });

  test('stop is safe twice and after the socket has closed', () async {
    await socket.serverCloses();
    await stream.stop();
    await stream.stop();
    expect(socket.sentJson, isEmpty);
  });

  test('close without end is an end', () async {
    socket.serverSends({'type': 'start', 'sample_rate': 24000});
    await settle();
    await socket.serverCloses();
    await listening;

    expect(frames.last, isA<SpeakEnd>());
  });

  test('close before anything is an end, never a hang', () async {
    await socket.serverCloses();
    await listening.timeout(const Duration(seconds: 2));
    expect(frames, [isA<SpeakEnd>()]);
  });

  test('nothing follows the end', () async {
    socket
      ..serverSends({'type': 'end'})
      ..serverSendsBytes(Uint8List.fromList([9]));
    await listening;
    expect(frames, [isA<SpeakEnd>()]);
  });

  test('sending after the stream has ended does not throw', () async {
    socket.serverSends({'type': 'end'});
    await listening;
    stream
      ..add('late')
      ..done();
    expect(socket.sentJson, isEmpty);
  });

  test('frames wait for a listener', () async {
    final late = SpeakStream(FakeAudioSocket()..serverSends({'type': 'end'}));
    await settle();
    expect(await late.frames.toList(), [isA<SpeakEnd>()]);
  });
}
