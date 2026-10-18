import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/voice/voice_capabilities.dart';
import 'package:iris/features/voice/barge_in.dart';
import 'package:iris/features/voice/levels.dart';
import 'package:iris/features/voice/speech_detector.dart';

Uint8List _samples(List<int> values) {
  final data = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    data.setInt16(i * 2, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Duration _ms(int ms) => Duration(milliseconds: ms);

/// Feeds [rms] every 100 ms over (from, to], each `at` being the end of a
/// 100 ms chunk, and returns the events with the time they came at.
List<(Duration, SpeechEvent)> _run(
  SpeechDetector detector,
  double rms,
  int fromMs,
  int toMs,
) {
  final events = <(Duration, SpeechEvent)>[];
  for (var t = fromMs + 100; t <= toMs; t += 100) {
    final event = detector.feed(rms, _ms(t));
    if (event != null) events.add((_ms(t), event));
  }
  return events;
}

void main() {
  group('levels', () {
    test('rms of silence is 0', () {
      expect(rmsOf(_samples(List.filled(320, 0))), 0);
      expect(rmsOf(Uint8List(0)), 0);
    });

    test('rms of a full-scale square is ~32767', () {
      final square = [for (var i = 0; i < 320; i++) i.isEven ? 32767 : -32767];
      expect(rmsOf(_samples(square)), closeTo(32767, 1));
    });

    test('rms of a quarter-scale square is a quarter', () {
      final square = [for (var i = 0; i < 320; i++) i.isEven ? 8192 : -8192];
      expect(rmsOf(_samples(square)), closeTo(8192, 1));
    });

    test('an odd trailing byte is ignored', () {
      final bytes = Uint8List.fromList([
        ..._samples([1000, -1000]),
        7,
      ]);
      expect(rmsOf(bytes), closeTo(1000, 0.5));
    });

    test('orb level spreads -45..0 dBFS over 0..1', () {
      expect(orbLevel(0), 0);
      expect(orbLevel(32767), closeTo(1, 1e-9));
      expect(orbLevel(40000), 1);
      // -45 dBFS and below is the floor.
      expect(orbLevel(32767 * 0.005), 0);
      // -22.5 dBFS is halfway.
      expect(orbLevel(32767 * 0.0749894), closeTo(0.5, 0.001));
    });
  });

  group('speech detector', () {
    test(
      'detector starts above threshold and ends after the silence duration',
      () {
        final detector = SpeechDetector(const VoiceTuning());
        final loud = _run(detector, 300, 0, 1000);
        expect(loud, hasLength(1));
        expect(loud.single.$2, isA<SpeechStarted>());

        // The last loud chunk ended at 1 s, so the take ends at exactly 4 s.
        final quiet = _run(detector, 100, 1000, 3900);
        expect(quiet, isEmpty);
        final ended = detector.feed(100, _ms(4000));
        expect(ended, isA<SpeechEnded>());
        expect((ended! as SpeechEnded).capped, isFalse);
      },
    );

    test('the server silence duration and threshold are used', () {
      final detector = SpeechDetector(
        const VoiceTuning(
          silenceThreshold: 500,
          silenceDuration: Duration(seconds: 1),
        ),
      );
      // 300 is below this server's threshold: nothing starts.
      expect(_run(detector, 300, 0, 1000), isEmpty);
      final loud = _run(detector, 600, 1000, 2000);
      expect(loud.single.$2, isA<SpeechStarted>());
      expect(_run(detector, 100, 2000, 2900), isEmpty);
      expect(detector.feed(100, _ms(3000)), isA<SpeechEnded>());
    });

    test('a pause shorter than the silence duration keeps the take', () {
      final detector = SpeechDetector(const VoiceTuning());
      _run(detector, 300, 0, 1000);
      expect(_run(detector, 100, 1000, 3000), isEmpty);
      expect(_run(detector, 300, 3000, 3500), isEmpty);
      expect(_run(detector, 100, 3500, 6400), isEmpty);
      expect(detector.feed(100, _ms(6500)), isA<SpeechEnded>());
    });

    test('takes under 400 ms are ignored', () {
      final detector = SpeechDetector(const VoiceTuning());
      final events = [
        ..._run(detector, 100, 0, 500),
        ..._run(detector, 300, 500, 800),
        ..._run(detector, 100, 800, 6000),
      ];
      expect(events, isEmpty);

      // And the detector is ready for a real take afterwards.
      expect(_run(detector, 300, 6000, 7000).single.$2, isA<SpeechStarted>());
    });

    test('capped at max recording', () {
      final detector = SpeechDetector(const VoiceTuning());
      final events = _run(detector, 300, 0, 119900);
      expect(events.single.$2, isA<SpeechStarted>());
      // The take began with the first chunk, at 0.
      final capped = detector.feed(300, _ms(120000));
      expect(capped, isA<SpeechEnded>());
      expect((capped! as SpeechEnded).capped, isTrue);
    });

    test('after a take ends the next one starts afresh', () {
      final detector = SpeechDetector(const VoiceTuning());
      _run(detector, 300, 0, 1000);
      _run(detector, 100, 1000, 4000);
      final next = _run(detector, 300, 4000, 5000);
      expect(next.single.$2, isA<SpeechStarted>());
    });

    test('reset drops a take in progress', () {
      final detector = SpeechDetector(const VoiceTuning());
      _run(detector, 300, 0, 1000);
      detector.reset();
      expect(_run(detector, 100, 1000, 6000), isEmpty);
    });
  });

  group('barge-in', () {
    BargeInDetector detector(VoiceTuning tuning, {double floor = 100}) =>
        BargeInDetector(tuning)..calibrate(floor);

    test('barge-in waits for the grace', () {
      final b = detector(const VoiceTuning());
      expect(b.feed(1000, _ms(300)), isFalse);
      expect(b.feed(1000, _ms(400)), isFalse);
      // Loud during the grace does not count towards the 200 ms.
      expect(b.feed(1000, _ms(600)), isFalse);
      expect(b.feed(1000, _ms(700)), isFalse);
      expect(b.feed(1000, _ms(800)), isTrue);
    });

    test('barge-in uses floor × multiplier', () {
      final quiet = detector(const VoiceTuning());
      for (var t = 600; t <= 3000; t += 100) {
        expect(quiet.feed(250, _ms(t)), isFalse);
      }

      final loud = detector(const VoiceTuning());
      expect(loud.feed(350, _ms(600)), isFalse);
      expect(loud.feed(350, _ms(700)), isFalse);
      expect(loud.feed(350, _ms(800)), isTrue);
    });

    test('a dip resets the 200 ms', () {
      final b = detector(const VoiceTuning());
      expect(b.feed(1000, _ms(600)), isFalse);
      expect(b.feed(1000, _ms(700)), isFalse);
      expect(b.feed(50, _ms(800)), isFalse);
      expect(b.feed(1000, _ms(900)), isFalse);
      expect(b.feed(1000, _ms(1000)), isFalse);
      expect(b.feed(1000, _ms(1100)), isTrue);
    });

    test('the floor is the mean of the calibration', () {
      final b = BargeInDetector(const VoiceTuning())
        ..calibrate(50)
        ..calibrate(150);
      // Floor 100 × 3 = 300.
      expect(b.feed(290, _ms(600)), isFalse);
      expect(b.feed(290, _ms(900)), isFalse);
      expect(b.feed(310, _ms(1000)), isFalse);
      expect(b.feed(310, _ms(1200)), isTrue);
    });

    test('a silent room never puts the bar below the silence threshold', () {
      final b = detector(const VoiceTuning(), floor: 0);
      for (var t = 600; t <= 2000; t += 100) {
        expect(b.feed(150, _ms(t)), isFalse);
      }
    });

    test('uncalibrated, the silence threshold is the floor', () {
      final b = BargeInDetector(const VoiceTuning(bargeInMultiplier: 2));
      expect(b.feed(390, _ms(600)), isFalse);
      expect(b.feed(390, _ms(900)), isFalse);
      expect(b.feed(410, _ms(1000)), isFalse);
      expect(b.feed(410, _ms(1200)), isTrue);
    });

    test('the server grace is used', () {
      final b = detector(
        const VoiceTuning(bargeInGrace: Duration(milliseconds: 1000)),
      );
      expect(b.feed(1000, _ms(700)), isFalse);
      expect(b.feed(1000, _ms(900)), isFalse);
      expect(b.feed(1000, _ms(1000)), isFalse);
      expect(b.feed(1000, _ms(1200)), isTrue);
    });

    test('barge-in off never trips', () {
      final b = detector(const VoiceTuning(bargeIn: false));
      for (var t = 0; t <= 5000; t += 100) {
        expect(b.feed(30000, _ms(t)), isFalse);
      }
    });
  });
}
