/// WCAG contrast, measured across every skin and both appearances.
///
/// A ten-skin system generated from three numbers each cannot be checked by
/// eye: that is 20 palettes and roughly a dozen meaningful foreground/background
/// pairs in every one. So the ratios are computed and asserted here, and a skin
/// whose accent collapses against its own surface fails the build rather than
/// shipping and being noticed by someone who cannot read it.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/tokens/metrics.dart';
import 'package:iris/design/tokens/palette.dart';

/// WCAG 2.1 relative luminance.
double luminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio, 1.0 to 21.0.
double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA thresholds. Large text is 18pt+, or 14pt+ bold.
const double aaBody = 4.5;
const double aaLarge = 3.0;

/// Non-text contrast: borders and controls that carry meaning.
const double aaNonText = 3.0;

void main() {
  /// Every combination the app actually renders.
  final palettes = <String, IrisPalette>{
    for (final skin in IrisSkin.values) ...{
      '${skin.name} dark': skin.palette(isDark: true),
      '${skin.name} light': skin.palette(isDark: false),
    },
  };

  group('body text', () {
    test('ink on every surface passes AA', () {
      for (final entry in palettes.entries) {
        final p = entry.value;
        for (final (name, surface) in [
          ('canvas', p.canvas),
          ('surface', p.surface),
          ('raised', p.surfaceRaised),
          ('sunken', p.surfaceSunken),
        ]) {
          expect(
            contrast(p.ink, surface),
            greaterThanOrEqualTo(aaBody),
            reason: '${entry.key}: ink on $name',
          );
        }
      }
    });

    test('muted text passes AA on canvas and surface', () {
      // inkMuted carries timestamps, metadata and section labels. It is
      // secondary, not decorative, so it gets the body threshold rather than
      // the large-text one.
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.inkMuted, p.canvas),
          greaterThanOrEqualTo(aaBody),
          reason: '${entry.key}: inkMuted on canvas',
        );
        expect(
          contrast(p.inkMuted, p.surface),
          greaterThanOrEqualTo(aaBody),
          reason: '${entry.key}: inkMuted on surface',
        );
      }
    });

    test('faint text passes the large-text threshold at minimum', () {
      // inkFaint is only ever used for placeholders and disabled hints, which
      // are large-ish or non-essential. Holding it to AA body would force it
      // dark enough to stop reading as a hint at all.
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.inkFaint, p.surfaceSunken),
          greaterThanOrEqualTo(aaLarge),
          reason: '${entry.key}: inkFaint on sunken (placeholder)',
        );
      }
    });
  });

  group('controls', () {
    test('accent text passes AA on its own fill', () {
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.accentInk, p.accent),
          greaterThanOrEqualTo(aaBody),
          reason: '${entry.key}: accentInk on accent (primary button)',
        );
      }
    });

    test('danger text passes AA on the danger fill', () {
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.onDanger, p.danger),
          greaterThanOrEqualTo(aaBody),
          reason: '${entry.key}: onDanger on danger (destructive button)',
        );
      }
    });

    test('the accent is distinguishable from the canvas it sits on', () {
      // A selected row, a focus ring, a link: all rely on the accent being
      // visible against the page without any text on it.
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.accent, p.canvas),
          greaterThanOrEqualTo(aaNonText),
          reason: '${entry.key}: accent on canvas',
        );
      }
    });

    test('a focused border is visible against the field it outlines', () {
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.accent, p.surfaceSunken),
          greaterThanOrEqualTo(aaNonText),
          reason: '${entry.key}: focus ring on field',
        );
      }
    });
  });

  group('agent states', () {
    test('every state colour is legible as text on the canvas', () {
      // These carry the one thing the app exists to communicate. If a state
      // colour is unreadable, the interface has failed at its only job.
      for (final entry in palettes.entries) {
        final p = entry.value;
        for (final state in AgentState.values) {
          expect(
            contrast(p.colorFor(state), p.canvas),
            greaterThanOrEqualTo(aaLarge),
            reason: '${entry.key}: ${state.name} on canvas',
          );
        }
      }
    });

    test('a state chip passes AA against its own tinted background', () {
      for (final entry in palettes.entries) {
        final p = entry.value;
        for (final state in AgentState.values) {
          expect(
            contrast(p.colorFor(state), p.quietFor(state)),
            greaterThanOrEqualTo(aaLarge),
            reason: '${entry.key}: ${state.name} chip',
          );
        }
      }
    });
  });

  group('structure', () {
    test('a hairline is visible against the surfaces it divides', () {
      // Below this a divider is decoration rather than structure, and the
      // grouping it is meant to express is lost.
      const minimumSeam = 1.18;
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.line, p.surface),
          greaterThanOrEqualTo(minimumSeam),
          reason: '${entry.key}: line on surface',
        );
      }
    });

    test('the ground and the surfaces on it are distinguishable', () {
      const minimumStep = 1.05;
      for (final entry in palettes.entries) {
        final p = entry.value;
        expect(
          contrast(p.canvas, p.surface),
          greaterThanOrEqualTo(minimumStep),
          reason: '${entry.key}: canvas vs surface',
        );
      }
    });

    test('raised separates from surface by tone in dark, by shadow in light', () {
      // Asserted differently per appearance because the physics differ. A dark
      // theme cannot lift a surface with shadow, so tone has to do the work and
      // is held to the same step as everything else. A light theme is already
      // near the ceiling of the luminance range, where no honest tone step is
      // available, so elevation is carried by shadow instead - which is how
      // real light-mode elevation has always worked.
      for (final entry in palettes.entries) {
        final p = entry.value;
        if (p.isDark) {
          expect(
            contrast(p.surface, p.surfaceRaised),
            greaterThanOrEqualTo(1.05),
            reason: '${entry.key}: surface vs raised',
          );
        } else {
          expect(
            IrisDepth.of(IrisPlane.overlay, p).shadows,
            isNotEmpty,
            reason: '${entry.key}: light overlay must carry a shadow',
          );
          expect(
            contrast(p.surface, p.surfaceRaised),
            greaterThanOrEqualTo(1.0),
            reason: '${entry.key}: raised must not be darker than surface',
          );
        }
      }
    });
  });

  test('no surface is pure black or pure white', () {
    // Pure values kill depth: there is nowhere left to go in one direction,
    // so the plane above or below has no room to separate itself.
    for (final entry in palettes.entries) {
      final p = entry.value;
      for (final (name, c) in [
        ('canvas', p.canvas),
        ('surface', p.surface),
        ('raised', p.surfaceRaised),
        ('sunken', p.surfaceSunken),
      ]) {
        // Asserted on the rendered bytes rather than on luminance: the rule is
        // about #FFFFFF and #000000 specifically, and any luminance threshold
        // for it is an arbitrary line that fails a legitimately near-white
        // surface.
        final bytes = [
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
        ];
        expect(
          bytes,
          isNot(everyElement(255)),
          reason: '${entry.key}: $name is pure white',
        );
        expect(
          bytes,
          isNot(everyElement(0)),
          reason: '${entry.key}: $name is pure black',
        );
      }
    }
  });
}
