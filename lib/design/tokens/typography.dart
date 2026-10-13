/// The Iris type system.
///
/// ## The move: mono is the voice of the interface
///
/// The usual arrangement gives prose to a sans and code to a mono. Iris inverts
/// half of it. Mono carries the *interface's own voice* — section labels, status
/// chips, tool names, timestamps, counts — set small, uppercase and tracked out.
/// Sans carries what people write and what the model says.
///
/// The reason is that this app is an instrument pointed at a machine. Almost
/// everything the interface says on its own behalf is machine fact: a tool name,
/// a cron expression, an exit code, a token count, a path. Setting those in the
/// same face as the agent's prose flattens a distinction the reader actually
/// needs. Setting them in mono means you can tell, at a glance and without
/// reading, whether a line is something the agent said or something the app is
/// reporting about it.
///
/// It also does the identity work. A transcript is mostly text, so type *is* the
/// design here; there is no room for ornament and no reason for it.
///
/// Geist and Geist Mono are a designed pair, which keeps the two voices related
/// rather than merely adjacent, and Geist Mono's figures are unusually good —
/// which matters when half the interface is numbers.
library;

import 'package:flutter/widgets.dart';

/// The two families. Referenced by constant so a swap is one edit.
abstract final class IrisFonts {
  static const String sans = 'Geist';
  static const String mono = 'GeistMono';

  /// Fallbacks if an asset fails to load. Deliberately platform-specific: a
  /// missing bundled font should degrade to something native rather than to
  /// whatever Flutter picks first.
  static const List<String> sansFallback = ['SF Pro Text', 'Roboto'];
  static const List<String> monoFallback = ['SF Mono', 'Roboto Mono'];
}

/// Every text style in Iris.
///
/// A closed set, not a starting point. Any screen needing a size that is not
/// here should be questioned before the scale is extended — an interface with
/// eleven text styles is legible; one with thirty is a ransom note.
final class IrisTypography {
  const IrisTypography._({
    required this.displayLarge,
    required this.display,
    required this.title,
    required this.heading,
    required this.body,
    required this.bodyLarge,
    required this.caption,
    required this.label,
    required this.labelSmall,
    required this.code,
    required this.codeSmall,
    required this.numeric,
  });

  /// Builds the scale in [color].
  ///
  /// Line heights are ratios chosen per size, not one global multiplier: small
  /// text needs proportionally more leading than large text to stay readable,
  /// and a single 1.5 everywhere makes headings look loose and captions tight.
  factory IrisTypography.resolve(Color color) {
    TextStyle sans(
      double size,
      FontWeight weight,
      double height, {
      double tracking = 0,
    }) => TextStyle(
      fontFamily: IrisFonts.sans,
      fontFamilyFallback: IrisFonts.sansFallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: tracking,
      color: color,
    );

    TextStyle mono(
      double size,
      FontWeight weight,
      double height, {
      double tracking = 0,
    }) => TextStyle(
      fontFamily: IrisFonts.mono,
      fontFamilyFallback: IrisFonts.monoFallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: tracking,
      color: color,
    );

    return IrisTypography._(
      // Reserved for empty states and onboarding — the only places with room.
      // Negative tracking because Geist opens up at large sizes.
      displayLarge: sans(34, FontWeight.w600, 1.12, tracking: -0.8),
      display: sans(27, FontWeight.w600, 1.18, tracking: -0.5),

      // Screen titles and sheet headers.
      title: sans(21, FontWeight.w600, 1.25, tracking: -0.3),

      // Section headings inside a screen; also session row titles.
      heading: sans(16, FontWeight.w500, 1.35, tracking: -0.1),

      // The transcript's default. 15.5 rather than a round 16 because at 16 a
      // 390pt-wide phone fits about 42 characters per line and at 15.5 it fits
      // 45 — closer to the 45–75 that long-form reading wants.
      body: sans(15.5, FontWeight.w400, 1.55),
      bodyLarge: sans(17, FontWeight.w400, 1.5),

      // Timestamps, secondary metadata. Sans because it sits under prose.
      caption: sans(13, FontWeight.w400, 1.4),

      // The interface's own voice. Uppercase is applied by the widget, not
      // baked in, so the string stays readable to a screen reader.
      label: mono(11.5, FontWeight.w500, 1.2, tracking: 0.9),
      labelSmall: mono(10, FontWeight.w500, 1.2, tracking: 1.1),

      // Tool output, diffs, file contents. Tight leading so a block of output
      // reads as one object rather than a list of lines.
      code: mono(13, FontWeight.w400, 1.45),
      codeSmall: mono(11.5, FontWeight.w400, 1.4),

      // Token counts, costs, durations. Tabular so digits do not jitter as a
      // streaming counter updates — the single most distracting thing a live
      // number can do.
      numeric: mono(
        13,
        FontWeight.w500,
        1.2,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }

  final TextStyle displayLarge;
  final TextStyle display;
  final TextStyle title;
  final TextStyle heading;
  final TextStyle body;
  final TextStyle bodyLarge;
  final TextStyle caption;

  /// Small, tracked mono for interface labels. Render through `IrisLabel`,
  /// which applies the uppercasing.
  final TextStyle label;
  final TextStyle labelSmall;

  final TextStyle code;
  final TextStyle codeSmall;

  /// Tabular mono for figures that change in place.
  final TextStyle numeric;

  /// Every style, for the gallery and for golden coverage.
  Map<String, TextStyle> get all => {
    'displayLarge': displayLarge,
    'display': display,
    'title': title,
    'heading': heading,
    'bodyLarge': bodyLarge,
    'body': body,
    'caption': caption,
    'label': label,
    'labelSmall': labelSmall,
    'code': code,
    'codeSmall': codeSmall,
    'numeric': numeric,
  };
}
