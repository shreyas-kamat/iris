/// The transcribe-stream protocol over a scripted socket: PCM in, words out.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/voice/transcribe_stream.dart';

import '../support/fake_voice.dart';

void main() {
  late FakeAudioSocket socket;

  setUp(() => socket = FakeAudioSocket());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('first frame is the rate', () {
    TranscribeStream(socket);

    expect(socket.sentJson, [
      {'sample_rate': 16000},
    ]);
  });

  test('a custom rate is announced', () {
    final other = FakeAudioSocket();
    TranscribeStream(other, sampleRate: 24000);
    expect(other.sentJson.single, {'sample_rate': 24000});
  });

  test('pcm goes out as binary frames', () {
    TranscribeStream(socket)
      ..add(Uint8List.fromList([1, 2]))
      ..add(Uint8List.fromList([3, 4]));
    expect(socket.sentBytes, [
      [1, 2],
      [3, 4],
    ]);
  });

  test('partials then final', () async {
    final stream = TranscribeStream(socket);
    final partials = <String>[];
    final sub = stream.partials.listen(partials.add);
    addTearDown(sub.cancel);

    socket
      ..serverSends({'type': 'partial', 'text': 'he'})
      ..serverSends({'type': 'partial', 'text': 'hello wor'});
    await settle();
    final result = stream.finish();
    socket.serverSends({
      'type': 'final',
      'transcript': 'hello world',
      'provider': 'x',
    });

    expect(partials, ['he', 'hello wor']);
    expect((await result).valueOrNull, 'hello world');
    expect(socket.sentJson.last, {'eos': true});
    expect(socket.closed, isTrue);
  });

  test('a final that arrives before finish is kept', () async {
    final stream = TranscribeStream(socket);
    socket.serverSends({'type': 'final', 'transcript': 'early'});
    await settle();

    expect((await stream.finish()).valueOrNull, 'early');
  });

  test('a final with no words is ok and empty', () async {
    final stream = TranscribeStream(socket);
    final result = stream.finish();
    socket.serverSends({'type': 'final', 'transcript': ''});

    expect((await result).valueOrNull, '');
  });

  test('error frame is Err with the message', () async {
    final stream = TranscribeStream(socket);
    final result = stream.finish();
    socket.serverSends({
      'type': 'error',
      'message': 'no live STT for the configured provider',
    });

    final failure = (await result).failureOrNull;
    expect(failure?.kind, FailureKind.server);
    expect(failure?.message, 'no live STT for the configured provider');
  });

  test('an error before finish is still reported by finish', () async {
    final stream = TranscribeStream(socket);
    socket.serverSends({'type': 'error', 'message': 'nope'});
    await settle();

    expect((await stream.finish()).failureOrNull?.message, 'nope');
  });

  test('close without final is Err', () async {
    final stream = TranscribeStream(socket);
    final result = stream.finish();
    await socket.serverCloses();

    final failure = (await result).failureOrNull;
    expect(failure, isNotNull);
    expect(failure!.kind, FailureKind.offline);
  });

  test('finish gives up after its timeout', () async {
    final stream = TranscribeStream(socket);

    final result = await stream.finish(
      timeout: const Duration(milliseconds: 30),
    );

    expect(result.failureOrNull?.kind, FailureKind.timeout);
    expect(socket.closed, isTrue);
  });

  test('cancel closes without eos', () async {
    final stream = TranscribeStream(socket);
    await stream.cancel();

    expect(socket.closed, isTrue);
    expect(socket.sentJson.where((j) => j.containsKey('eos')), isEmpty);
  });

  test('cancel while finishing answers cancelled', () async {
    final stream = TranscribeStream(socket);
    final result = stream.finish();
    await stream.cancel();

    expect((await result).failureOrNull?.kind, FailureKind.cancelled);
  });

  test('partials end when the stream does', () async {
    final stream = TranscribeStream(socket);
    final done = stream.partials.toList();
    await stream.cancel();

    expect(await done, isEmpty);
  });

  test('adding or finishing after the close does not throw', () async {
    final stream = TranscribeStream(socket);
    await stream.cancel();

    stream.add(Uint8List.fromList([1]));
    expect((await stream.finish()).isErr, isTrue);
  });

  test('a partial without text is skipped', () async {
    final stream = TranscribeStream(socket);
    final partials = <String>[];
    final sub = stream.partials.listen(partials.add);
    addTearDown(sub.cancel);
    socket.serverSends({'type': 'partial'});
    await settle();
    expect(partials, isEmpty);
  });
}
