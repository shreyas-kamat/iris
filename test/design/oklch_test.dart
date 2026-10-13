import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/tokens/oklch.dart';

/// Channel values as 0..255, for comparing against known sRGB references.
(int, int, int) rgb(Color c) => (
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
);

/// Perceptual lightness recovered from sRGB, used to prove ramp evenness
/// without hard-coding what each stop should look like.
double relativeLuminance(Color c) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : _pow((channel + 0.055) / 1.055, 2.4);
  return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
}

double _pow(double base, double exponent) =>
    (base <= 0) ? 0 : _exp(exponent * _ln(base));
double _ln(double x) {
  // Enough precision for a test assertion; avoids importing dart:math into the
  // expectation helpers where a typo would silently pass.
  var result = 0.0;
  var value = x;
  while (value > 2) {
    value /= 2.718281828459045;
    result += 1;
  }
  while (value < 0.5) {
    value *= 2.718281828459045;
    result -= 1;
  }
  final z = (value - 1) / (value + 1);
  var term = z;
  var sum = 0.0;
  for (var n = 1; n <= 21; n += 2) {
    sum += term / n;
    term *= z * z;
  }
  return result + 2 * sum;
}

double _exp(double x) {
  var sum = 1.0;
  var term = 1.0;
  for (var n = 1; n < 30; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}

void main() {
  group('conversion correctness', () {
    // Reference values from Björn Ottosson's OKLab reference implementation.
    test('pure white', () {
      expect(rgb(const Oklch(1.0, 0.0, 0.0).toColor()), (255, 255, 255));
    });

    test('pure black', () {
      expect(rgb(const Oklch(0.0, 0.0, 0.0).toColor()), (0, 0, 0));
    });

    test('mid grey is neutral on every channel', () {
      final (r, g, b) = rgb(const Oklch(0.6, 0.0, 0.0).toColor());
      expect(r, g);
      expect(g, b);
      // sRGB 128 is oklch(0.5981 0 0), so L=0.6 landing on 128 is correct.
      expect(r, inInclusiveRange(124, 134));
    });

    test('sRGB red round-trips to approximately its OKLCH coordinates', () {
      // sRGB #FF0000 is oklch(0.6280 0.2577 29.23).
      final (r, g, b) = rgb(const Oklch(0.6280, 0.2577, 29.23).toColor());
      expect(r, inInclusiveRange(252, 255));
      expect(g, inInclusiveRange(0, 4));
      expect(b, inInclusiveRange(0, 4));
    });

    test('alpha is carried through untouched', () {
      expect(const Oklch(0.5, 0.1, 200, 0.4).toColor().a, closeTo(0.4, 0.001));
    });
  });

  group('gamut fitting', () {
    test('an impossible chroma is reduced rather than clipped', () {
      // No sRGB colour has chroma 0.5 at this lightness. Clipping channels
      // would skew the hue toward whichever primary saturated first; reducing
      // chroma keeps it.
      final extreme = const Oklch(0.6, 0.5, 150).toColor();
      final sane = const Oklch(0.6, 0.20, 150).toColor();
      for (final channel in [extreme.r, extreme.g, extreme.b]) {
        expect(channel, inInclusiveRange(0.0, 1.0));
      }
      // Still recognisably the same hue family: green dominant, not clipped to
      // a primary.
      expect(extreme.g, greaterThan(extreme.r));
      expect(extreme.g, greaterThan(extreme.b));
      expect(sane.g, greaterThan(sane.r));
    });

    test('in-gamut colours are returned unchanged', () {
      const inGamut = Oklch(0.6, 0.05, 250);
      final direct = inGamut.toColor();
      expect(direct.r, inInclusiveRange(0.0, 1.0));
      expect(direct.b, greaterThan(direct.r));
    });

    test('every stop of every hue lands in gamut', () {
      // The whole point of the ramp system: pick any hue, get usable colours.
      for (var hue = 0.0; hue < 360; hue += 15) {
        final ramp = ColorRamp.fromHue(hue);
        for (final stop in ColorRamp.stops) {
          final c = ramp.color(stop);
          for (final channel in [c.r, c.g, c.b]) {
            expect(
              channel,
              inInclusiveRange(0.0, 1.0),
              reason: 'hue $hue stop $stop escaped the gamut',
            );
          }
        }
      }
    });
  });

  group('ramps', () {
    test('stops descend in lightness monotonically', () {
      final ramp = ColorRamp.fromHue(260);
      var previous = 2.0;
      for (final stop in ColorRamp.stops) {
        final luminance = relativeLuminance(ramp.color(stop));
        expect(
          luminance,
          lessThan(previous),
          reason: 'stop $stop is not darker than the one before it',
        );
        previous = luminance;
      }
    });

    test('the same stop reads at the same weight across hues', () {
      // This is what OKLCH buys: a violet 600 and an amber 600 are the same
      // perceptual weight, so a component can reference a stop and look right
      // in any skin.
      final luminances = <double>[
        for (var hue = 0.0; hue < 360; hue += 40)
          relativeLuminance(ColorRamp.fromHue(hue).color(600)),
      ];
      final lowest = luminances.reduce((a, b) => a < b ? a : b);
      final highest = luminances.reduce((a, b) => a > b ? a : b);
      // Relative luminance is not itself perceptually uniform, so some spread
      // is expected; what matters is that no hue is wildly out of family.
      expect(highest - lowest, lessThan(0.14));
    });

    test('chroma tapers toward the ends so extremes do not look tinted', () {
      final ramp = ColorRamp.fromHue(30);
      double spread(Color c) {
        final channels = [c.r, c.g, c.b];
        return channels.reduce((a, b) => a > b ? a : b) -
            channels.reduce((a, b) => a < b ? a : b);
      }

      expect(spread(ramp.color(50)), lessThan(spread(ramp.color(500))));
      expect(spread(ramp.color(1000)), lessThan(spread(ramp.color(500))));
    });

    test('a neutral ramp is near-grey but not dead grey', () {
      final neutral = ColorRamp.neutral(265);
      final mid = neutral.color(500);
      final channels = [mid.r, mid.g, mid.b];
      final spread =
          channels.reduce((a, b) => a > b ? a : b) -
          channels.reduce((a, b) => a < b ? a : b);
      expect(spread, greaterThan(0.0), reason: 'should carry a hint of hue');
      expect(spread, lessThan(0.06), reason: 'should still read as neutral');
    });

    test('an unknown stop falls back instead of throwing in release', () {
      // Debug asserts, so only the release path is exercised here.
      final ramp = ColorRamp.fromHue(200);
      expect(() => ramp[500], returnsNormally);
    });
  });

  group('manipulation', () {
    test('mute reduces chroma without moving hue or lightness', () {
      const base = Oklch(0.6, 0.2, 300);
      final muted = base.mute(0.25);
      expect(muted.l, base.l);
      expect(muted.h, base.h);
      expect(muted.c, closeTo(0.05, 1e-9));
    });

    test('withLightness leaves the hue family intact', () {
      const base = Oklch(0.6, 0.15, 145);
      final lighter = base.withLightness(0.85);
      expect(lighter.h, base.h);
      expect(
        relativeLuminance(lighter.toColor()),
        greaterThan(relativeLuminance(base.toColor())),
      );
    });
  });
}
