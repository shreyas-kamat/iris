/// Colour in OKLCH, converted to sRGB at build time.
///
/// Iris ships many skins in light and dark, and every one needs its ramps to
/// step evenly. Hand-picked hex values cannot do that: in sRGB, equal numeric
/// steps are not equal *perceptual* steps, so a ramp that looks smooth in blue
/// goes muddy in yellow, and a "same lightness" accent reads darker in violet
/// than in cyan. OKLCH is perceptually uniform, so one set of lightness stops
/// produces ramps that match across every hue — which is the only way a
/// ten-skin system stays coherent without ten separate hand-tuning passes.
///
/// L is 0..1 (perceptual lightness), C is chroma from 0 (grey) upward, and H is
/// hue in degrees. Out-of-gamut combinations are resolved by reducing chroma
/// rather than clipping channels, which preserves hue and lightness instead of
/// skewing a colour toward whichever primary clipped first.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A colour specified in OKLCH.
@immutable
final class Oklch {
  const Oklch(this.l, this.c, this.h, [this.alpha = 1.0]);

  /// Perceptual lightness, 0 (black) to 1 (white).
  final double l;

  /// Chroma. 0 is neutral grey; roughly 0.37 is the most sRGB can hold.
  final double c;

  /// Hue in degrees, 0..360.
  final double h;

  final double alpha;

  Oklch withLightness(double value) => Oklch(value, c, h, alpha);

  Oklch withChroma(double value) => Oklch(l, value, h, alpha);

  Oklch withHue(double value) => Oklch(l, c, value, alpha);

  Oklch withAlpha(double value) => Oklch(l, c, h, value);

  /// Scales chroma, for muting a hue without shifting it.
  Oklch mute(double factor) => Oklch(l, c * factor, h, alpha);

  /// Converts to sRGB, reducing chroma if needed to land inside the gamut.
  Color toColor() {
    final resolved = _fitToGamut();
    final (r, g, b) = _toLinearSrgb(resolved.l, resolved.c, resolved.h);
    return Color.from(
      alpha: alpha,
      red: _encodeGamma(r),
      green: _encodeGamma(g),
      blue: _encodeGamma(b),
    );
  }

  /// Finds the highest chroma at this lightness and hue that sRGB can show.
  ///
  /// Binary search rather than an analytic gamut boundary: the exact sRGB
  /// boundary in OKLCH has no closed form, and 16 iterations lands well inside
  /// a single 8-bit step. Colours already in gamut are returned untouched, so
  /// this costs nothing for the common case.
  Oklch _fitToGamut() {
    if (_isInGamut(l, c, h)) return this;

    var low = 0.0;
    var high = c;
    for (var i = 0; i < 16; i++) {
      final mid = (low + high) / 2;
      if (_isInGamut(l, mid, h)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return Oklch(l, low, h, alpha);
  }

  static bool _isInGamut(double l, double c, double h) {
    final (r, g, b) = _toLinearSrgb(l, c, h);
    // A hair of tolerance, so a colour sitting exactly on the boundary is not
    // rejected by floating-point noise.
    const epsilon = 1e-6;
    return r >= -epsilon &&
        r <= 1 + epsilon &&
        g >= -epsilon &&
        g <= 1 + epsilon &&
        b >= -epsilon &&
        b <= 1 + epsilon;
  }

  /// OKLCH → OKLab → LMS → linear sRGB, per Björn Ottosson's derivation.
  static (double, double, double) _toLinearSrgb(double l, double c, double h) {
    final radians = h * math.pi / 180.0;
    final a = c * math.cos(radians);
    final b = c * math.sin(radians);

    final lRoot = l + 0.3963377774 * a + 0.2158037573 * b;
    final mRoot = l - 0.1055613458 * a - 0.0638541728 * b;
    final sRoot = l - 0.0894841775 * a - 1.2914855480 * b;

    final lms0 = lRoot * lRoot * lRoot;
    final lms1 = mRoot * mRoot * mRoot;
    final lms2 = sRoot * sRoot * sRoot;

    return (
      4.0767416621 * lms0 - 3.3077115913 * lms1 + 0.2309699292 * lms2,
      -1.2684380046 * lms0 + 2.6097574011 * lms1 - 0.3413193965 * lms2,
      -0.0041960863 * lms0 - 0.7034186147 * lms1 + 1.7076147010 * lms2,
    );
  }

  /// Linear light to sRGB's transfer function.
  static double _encodeGamma(double channel) {
    final v = channel.clamp(0.0, 1.0);
    return v <= 0.0031308
        ? v * 12.92
        : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Oklch &&
          other.l == l &&
          other.c == c &&
          other.h == h &&
          other.alpha == alpha);

  @override
  int get hashCode => Object.hash(l, c, h, alpha);

  @override
  String toString() =>
      'oklch(${l.toStringAsFixed(3)} ${c.toStringAsFixed(3)} '
      '${h.toStringAsFixed(1)}${alpha == 1 ? '' : ' / $alpha'})';
}

/// An evenly-stepped set of tones sharing one hue.
///
/// Stops are named by perceptual lightness in the same way across every ramp
/// and every skin, so `ramp[600]` means the same *weight* whether the hue is
/// violet or amber. That is what lets a component reference a stop rather than
/// a colour and still look right in ten skins.
@immutable
final class ColorRamp {
  const ColorRamp._(this._stops);

  /// Builds a ramp at [hue], with chroma peaking in the mid tones.
  ///
  /// Chroma is tapered toward both ends because saturated near-white and
  /// near-black read as tinted mistakes rather than as part of a family; the
  /// peak sits around the 500–600 stops where an accent actually gets used.
  factory ColorRamp.fromHue(double hue, {double chroma = 0.13}) {
    final stops = <int, Oklch>{};
    for (final entry in _lightnessStops.entries) {
      final position = _chromaCurve[entry.key]!;
      stops[entry.key] = Oklch(entry.value, chroma * position, hue);
    }
    return ColorRamp._(stops);
  }

  /// A neutral ramp — near-grey, with just enough chroma to feel like it
  /// belongs to [hue] rather than being a dead grey dropped in from elsewhere.
  factory ColorRamp.neutral(double hue, {double chroma = 0.012}) =>
      ColorRamp.fromHue(hue, chroma: chroma);

  /// Perceptual lightness for each stop. Deliberately not linear: the ends are
  /// spread out so 50/950 sit far enough from the mid tones to serve as page
  /// and ink, while the middle is dense enough for adjacent states (hover,
  /// pressed) to be distinguishable without a visible jump.
  static const Map<int, double> _lightnessStops = {
    50: 0.975,
    100: 0.940,
    200: 0.880,
    300: 0.800,
    400: 0.705,
    500: 0.620,
    600: 0.540,
    700: 0.455,
    800: 0.370,
    900: 0.280,
    950: 0.190,
    1000: 0.125,
  };

  /// Chroma multiplier per stop, peaking at 500–600.
  static const Map<int, double> _chromaCurve = {
    50: 0.18,
    100: 0.34,
    200: 0.56,
    300: 0.78,
    400: 0.93,
    500: 1.00,
    600: 1.00,
    700: 0.92,
    800: 0.80,
    900: 0.64,
    950: 0.48,
    1000: 0.36,
  };

  final Map<int, Oklch> _stops;

  /// The available stop keys, ascending.
  static List<int> get stops => _lightnessStops.keys.toList(growable: false);

  /// The tone at [stop]. Asserts in debug on an unknown stop, and falls back to
  /// the nearest one in release rather than throwing in a build method.
  Oklch operator [](int stop) {
    final exact = _stops[stop];
    if (exact != null) return exact;
    assert(false, 'No ramp stop $stop; valid stops are ${stops.join(', ')}');
    final nearest = _stops.keys.reduce(
      (a, b) => (a - stop).abs() <= (b - stop).abs() ? a : b,
    );
    return _stops[nearest]!;
  }

  Color color(int stop) => this[stop].toColor();
}
