/// Space, radius, borders and depth.
library;

import 'package:flutter/painting.dart';

import 'oklch.dart';
import 'palette.dart';

/// The spacing scale.
///
/// A 4pt grid, but not every multiple of 4 — the steps are named and the set is
/// closed, so "a bit more room here" has to pick an existing step instead of
/// inventing 14. That constraint is what makes rhythm survive a hundred screens.
abstract final class IrisSpace {
  /// Hairline gaps: between an icon and its label.
  static const double xxs = 2;

  /// Inside a chip; between tightly-related lines.
  static const double xs = 4;

  /// Between a label and its value.
  static const double sm = 8;

  /// The default. Padding inside cards, gaps between controls.
  static const double md = 12;

  /// Screen gutters, gaps between message groups.
  static const double lg = 16;

  /// Between sections.
  static const double xl = 24;

  /// Around an empty state; above a screen's first element.
  static const double xxl = 32;

  /// Major separation — only in sparse layouts.
  static const double huge = 48;
}

/// Corner radii.
///
/// Rounder than a developer tool usually is. The agent is doing something for
/// you on your own machine; the interface should feel like a companion rather
/// than a console. Sharp corners here would read as brutalist affect, and the
/// content — tool output, diffs, terminal text — is angular enough already.
abstract final class IrisRadius {
  /// Chips, badges, inline code.
  static const Radius xs = Radius.circular(6);

  /// Buttons, fields, small cards.
  static const Radius sm = Radius.circular(10);

  /// Tool cards, message groups.
  static const Radius md = Radius.circular(14);

  /// Sheets, dialogs, large panels.
  static const Radius lg = Radius.circular(20);

  /// The top corners of a bottom sheet, which read larger because only two
  /// corners are visible.
  static const Radius sheet = Radius.circular(26);

  /// Pills and the aperture.
  static const Radius full = Radius.circular(999);
}

/// Stroke widths.
abstract final class IrisStroke {
  /// Dividers and card edges. Deliberately sub-pixel on most devices so a
  /// hairline reads as a seam rather than a drawn line.
  static const double hairline = 0.5;

  /// Default borders.
  static const double thin = 1;

  /// Focus rings and selected states.
  static const double thick = 1.5;

  /// The aperture ring.
  static const double ring = 2;
}

/// The three planes everything sits on.
///
/// Depth is used to say *what can be dismissed*, not to decorate. Ground is the
/// conversation and cannot be dismissed. Raised is a card that belongs to the
/// conversation. Overlay is a sheet that sits on top of it and goes away. A
/// reader should be able to tell which is which without touching the screen.
enum IrisPlane {
  /// The page itself. No shadow.
  ground,

  /// Cards and grouped content. A shadow just deep enough to lift.
  raised,

  /// Sheets, menus, the approval gate. Reads as clearly detached.
  overlay,
}

/// Shadow and border treatment for a plane in a given palette.
final class IrisDepth {
  const IrisDepth({required this.shadows, required this.border});

  final List<BoxShadow> shadows;

  /// Dark themes cannot lift a surface with shadow — a shadow on near-black is
  /// invisible — so they separate planes with a light top edge instead, the way
  /// a physical object catches light. Light themes use shadow and skip it.
  final Color? border;

  /// Resolves depth for [plane] against [palette].
  ///
  /// Shadow colour is derived from the palette's own neutral hue rather than
  /// being a hard-coded black. A pure-black shadow on a violet-tinted ground
  /// reads as a dirty smudge, because the shadow and the surface disagree about
  /// what colour the light is. Tinting it to the ground is the difference
  /// between a card sitting on the page and a card pasted onto it.
  static IrisDepth of(IrisPlane plane, IrisPalette palette) {
    /// The colour light is absent in, for this palette.
    Color shade(double alpha) =>
        Oklch(0.08, 0.02, palette.neutralHue, alpha).toColor();

    if (palette.isDark) {
      return switch (plane) {
        IrisPlane.ground => const IrisDepth(shadows: [], border: null),
        IrisPlane.raised => IrisDepth(
          shadows: [
            BoxShadow(
              color: shade(0.25),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
          border: palette.line,
        ),
        IrisPlane.overlay => IrisDepth(
          shadows: [
            BoxShadow(
              color: shade(0.40),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
          border: palette.lineStrong,
        ),
      };
    }
    return switch (plane) {
      IrisPlane.ground => const IrisDepth(shadows: [], border: null),
      IrisPlane.raised => IrisDepth(
        shadows: [
          BoxShadow(
            color: shade(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: shade(0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: palette.line,
      ),
      IrisPlane.overlay => IrisDepth(
        shadows: [
          BoxShadow(
            color: shade(0.12),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: shade(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: null,
      ),
    };
  }
}

/// Sizes for things that must be a fixed size.
abstract final class IrisSize {
  /// The minimum any tappable thing may be. Enforced, not aspirational —
  /// a 32pt icon button with a 44pt hit area is correct; a 32pt hit area is not.
  static const double minTapTarget = 44;

  /// Standard control height: buttons, fields, the composer's send button.
  static const double control = 44;

  /// Compact controls inside a dense row.
  static const double controlSmall = 32;

  /// The signature aperture at its usual size, in the chat header.
  static const double aperture = 26;

  /// The aperture shrunk to a status dot on a session row.
  static const double apertureSmall = 10;

  /// Avatar / provider mark.
  static const double avatar = 28;

  /// Icon sizes.
  static const double icon = 20;
  static const double iconSmall = 16;
}
