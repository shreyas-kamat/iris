/// The voice orb: every mode paints, it follows the level the way the design
/// does, and it is still under reduced motion.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/iris_voice_orb.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';

/// Like `themed`, but chooses the brightness and whether animations run.
Widget host(Widget child, {bool dark = true, bool reduced = true}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
  return MaterialApp(
    theme: theme.materialTheme,
    builder: (context, navigator) => IrisTheme(
      data: theme,
      child: Material(type: MaterialType.transparency, child: navigator),
    ),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        disableAnimations: reduced,
      ),
      child: Center(child: child),
    ),
  );
}

IrisVoiceOrbState orbState(WidgetTester tester) =>
    tester.state<IrisVoiceOrbState>(find.byType(IrisVoiceOrb));

void main() {
  group('painting', () {
    testWidgets('each mode paints, dark and light, animated and still', (
      tester,
    ) async {
      for (final dark in [true, false]) {
        for (final reduced in [true, false]) {
          for (final mode in VoiceOrbMode.values) {
            await tester.pumpWidget(
              host(
                IrisVoiceOrb(mode: mode, size: 126),
                dark: dark,
                reduced: reduced,
              ),
            );
            await tester.pump(const Duration(milliseconds: 120));
            expect(
              tester.takeException(),
              isNull,
              reason: '${mode.name} dark=$dark reduced=$reduced',
            );
          }
        }
      }
    });

    testWidgets('small sizes and an odd level paint', (tester) async {
      for (final size in [20.0, 46.0, 126.0, 320.0]) {
        await tester.pumpWidget(
          host(
            IrisVoiceOrb(
              mode: VoiceOrbMode.hearing,
              size: size,
              level: ValueNotifier<double>(2.5),
            ),
            reduced: false,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: 'size $size');
      }
    });

    testWidgets('it has a label for the mode', (tester) async {
      await tester.pumpWidget(
        host(const IrisVoiceOrb(mode: VoiceOrbMode.muted)),
      );
      expect(find.bySemanticsLabel('Microphone muted'), findsOneWidget);
    });
  });

  group('motion', () {
    testWidgets('still under reduced motion', (tester) async {
      final level = ValueNotifier<double>(0.7);
      await tester.pumpWidget(
        host(IrisVoiceOrb(mode: VoiceOrbMode.hearing, level: level)),
      );
      await tester.pump();

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);

      // A new level repaints once and still schedules nothing after it.
      level.value = 0.2;
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('an explicit still wins over the system setting', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const IrisVoiceOrb(mode: VoiceOrbMode.speaking, still: false),
        ),
      );
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
    });

    testWidgets('it runs a ticker when animated and stops when removed', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const IrisVoiceOrb(mode: VoiceOrbMode.thinking), reduced: false),
      );
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(host(const SizedBox(), reduced: false));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('attack and release', (tester) async {
      final level = ValueNotifier<double>(1);
      await tester.pumpWidget(
        host(
          IrisVoiceOrb(mode: VoiceOrbMode.hearing, level: level),
          reduced: false,
        ),
      );
      await tester.pump();
      expect(orbState(tester).smoothedLevel, 0);

      // Up: 1 - exp(-dt / .06) is .63 after 60 ms.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(orbState(tester).smoothedLevel, greaterThan(0.6));

      // Let it saturate, then drop: exp(-dt / .28) is .37 after 280 ms.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(orbState(tester).smoothedLevel, greaterThan(0.99));
      level.value = 0;
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(orbState(tester).smoothedLevel, lessThan(0.4));
      expect(orbState(tester).smoothedLevel, greaterThan(0.2));
    });

    testWidgets('a stalled frame does not make the level leap', (tester) async {
      final level = ValueNotifier<double>(1);
      await tester.pumpWidget(
        host(
          IrisVoiceOrb(mode: VoiceOrbMode.speaking, level: level),
          reduced: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      // One capped 50 ms step: 1 - exp(-.05 / .06) = .57.
      expect(orbState(tester).smoothedLevel, closeTo(0.565, 0.01));
    });

    testWidgets('the level a still orb shows is the level it is given', (
      tester,
    ) async {
      final level = ValueNotifier<double>(0.8);
      await tester.pumpWidget(
        host(IrisVoiceOrb(mode: VoiceOrbMode.speaking, level: level)),
      );
      await tester.pump();
      expect(orbState(tester).smoothedLevel, closeTo(0.8, 1e-9));
      level.value = 0.1;
      await tester.pump();
      expect(orbState(tester).smoothedLevel, closeTo(0.1, 1e-9));
    });
  });

  group('still outlines', () {
    testWidgets('hearing shows 0, 1 or 2 dashed outlines by level band', (
      tester,
    ) async {
      final level = ValueNotifier<double>(0.2);
      await tester.pumpWidget(
        host(IrisVoiceOrb(mode: VoiceOrbMode.hearing, level: level)),
      );
      await tester.pump();
      expect(orbState(tester).ripplePresence, [0, 0]);

      level.value = 0.45;
      await tester.pump();
      expect(orbState(tester).ripplePresence, [1, 0]);

      level.value = 0.9;
      await tester.pump();
      expect(orbState(tester).ripplePresence, [1, 1]);
    });

    testWidgets(
      'a band change cross-fades over 400 ms when still is asked for',
      (tester) async {
        final level = ValueNotifier<double>(0.2);
        await tester.pumpWidget(
          host(
            IrisVoiceOrb(mode: VoiceOrbMode.hearing, level: level, still: true),
            reduced: false,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(orbState(tester).ripplePresence, [0, 0]);

        level.value = 0.45;
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        final half = orbState(tester).ripplePresence.first;
        expect(half, greaterThan(0.2));
        expect(half, lessThan(0.8));

        for (var i = 0; i < 13; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(orbState(tester).ripplePresence, [1, 0]);
      },
    );

    testWidgets(
      'an asked-for still pulses its opacity; reduced motion does not',
      (tester) async {
        await tester.pumpWidget(
          host(
            const IrisVoiceOrb(mode: VoiceOrbMode.speaking, still: true),
            reduced: false,
          ),
        );
        await tester.pump();
        final seen = <double>{};
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 450));
          final alpha = orbState(tester).pulseAlpha;
          expect(alpha, inInclusiveRange(0.72, 1.0));
          seen.add(double.parse(alpha.toStringAsFixed(3)));
        }
        expect(seen.length, greaterThan(2));

        await tester.pumpWidget(
          host(const IrisVoiceOrb(mode: VoiceOrbMode.speaking, still: true)),
        );
        await tester.pump();
        expect(orbState(tester).pulseAlpha, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  });

  group('geometry', () {
    test('level drives the ring', () {
      expect(
        ringRadiusFor(VoiceOrbMode.hearing, 0.95),
        greaterThan(ringRadiusFor(VoiceOrbMode.hearing, 0.35)),
      );
      expect(
        ringRadiusFor(VoiceOrbMode.speaking, 0.95),
        greaterThan(ringRadiusFor(VoiceOrbMode.speaking, 0.35)),
      );
      expect(ringRadiusFor(VoiceOrbMode.hearing, 0), closeTo(0.27, 1e-9));
      expect(
        ringRadiusFor(VoiceOrbMode.thinking, 0.95),
        ringRadiusFor(VoiceOrbMode.thinking, 0.1),
      );
    });

    test('the level is clamped', () {
      expect(
        ringRadiusFor(VoiceOrbMode.hearing, 5),
        ringRadiusFor(VoiceOrbMode.hearing, 1),
      );
      expect(
        ringRadiusFor(VoiceOrbMode.hearing, -1),
        ringRadiusFor(VoiceOrbMode.hearing, 0),
      );
    });
  });

  group('colours', () {
    test('colours are palette roles', () {
      final dark = IrisSkin.aperture.palette(isDark: true);
      final light = IrisSkin.aperture.palette(isDark: false);

      expect(dark.voiceOrbColor(VoiceOrbMode.hearing), const Color(0xFFFF8AD8));
      expect(
        light.voiceOrbColor(VoiceOrbMode.hearing),
        const Color(0xFFB0307F),
      );

      const darkTable = {
        VoiceOrbMode.idle: 0xFFC9C3FF,
        VoiceOrbMode.connecting: 0xFF5CC8FF,
        VoiceOrbMode.listening: 0xFFFF8AD8,
        VoiceOrbMode.hearing: 0xFFFF8AD8,
        VoiceOrbMode.thinking: 0xFF9B7BFF,
        VoiceOrbMode.tool: 0xFFFFB547,
        VoiceOrbMode.speaking: 0xFF4FE3C1,
        VoiceOrbMode.muted: 0xFF8A8898,
        VoiceOrbMode.error: 0xFFFF6B6B,
        VoiceOrbMode.needs: 0xFFFF8A5C,
        VoiceOrbMode.offline: 0xFF8A8898,
      };
      const lightTable = {
        VoiceOrbMode.idle: 0xFF4F3FCF,
        VoiceOrbMode.connecting: 0xFF0B6FA3,
        VoiceOrbMode.listening: 0xFFB0307F,
        VoiceOrbMode.hearing: 0xFFB0307F,
        VoiceOrbMode.thinking: 0xFF6544D9,
        VoiceOrbMode.tool: 0xFF8A5000,
        VoiceOrbMode.speaking: 0xFF00735E,
        VoiceOrbMode.muted: 0xFF646372,
        VoiceOrbMode.error: 0xFFC0312D,
        VoiceOrbMode.needs: 0xFFB5410F,
        VoiceOrbMode.offline: 0xFF646372,
      };
      for (final entry in darkTable.entries) {
        expect(
          dark.voiceOrbColor(entry.key),
          Color(entry.value),
          reason: '${entry.key}',
        );
      }
      for (final entry in lightTable.entries) {
        expect(
          light.voiceOrbColor(entry.key),
          Color(entry.value),
          reason: '${entry.key}',
        );
      }
      // Interrupted is the turn from speaking to hearing.
      expect(
        dark.voiceOrbColor(VoiceOrbMode.interrupted),
        dark.voiceOrbColor(VoiceOrbMode.hearing),
      );
    });

    test('the orb file holds no hex colour of its own', () {
      // The widget takes every colour from the palette (white is
      // `Colors.white`).
      final source = File(
        'lib/design/components/iris_voice_orb.dart',
      ).readAsStringSync();
      expect(RegExp('0x[0-9A-Fa-f]{6,8}').hasMatch(source), isFalse);
    });
  });
}
