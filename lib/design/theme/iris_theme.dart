/// The theme: how tokens reach a widget.
///
/// Iris does not style itself through `ThemeData`. Material's theme is shaped
/// around Material's components, and mapping a bespoke system onto it means
/// every token gets a lossy home — an accent becomes `colorScheme.primary`,
/// a label becomes `textTheme.labelSmall`, and the vocabulary stops describing
/// the design. So the design system travels in its own [InheritedWidget] and
/// `ThemeData` is filled in only far enough to keep the Material widgets Iris
/// does borrow (the ink well, the scrollbar, text selection) from looking wrong.
library;

import 'package:flutter/material.dart';

import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';
import '../tokens/typography.dart';

/// The resolved design system for one skin and brightness.
@immutable
final class IrisThemeData {
  IrisThemeData({required this.skin, required this.isDark})
    : palette = skin.palette(isDark: isDark),
      typography = IrisTypography.resolve(skin.palette(isDark: isDark).ink);

  final IrisSkin skin;
  final bool isDark;
  final IrisPalette palette;
  final IrisTypography typography;

  /// Depth treatment for [plane] under this palette.
  IrisDepth depth(IrisPlane plane) => IrisDepth.of(plane, palette);

  /// A minimal [ThemeData] so borrowed Material widgets inherit the right
  /// colours. Not the source of truth for anything Iris draws itself.
  ThemeData get materialTheme {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: palette.accent,
        onPrimary: palette.accentInk,
        secondary: palette.accent,
        onSecondary: palette.accentInk,
        error: palette.colorFor(AgentState.failed),
        onError: palette.inkInverse,
        surface: palette.surface,
        onSurface: palette.ink,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accent,
        selectionColor: palette.accent.withValues(alpha: 0.28),
        selectionHandleColor: palette.accent,
      ),
      // Material's page transitions are duration-based and do not match the
      // spring language, so Iris supplies its own on every route.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IrisThemeData && other.skin == skin && other.isDark == isDark);

  @override
  int get hashCode => Object.hash(skin, isDark);
}

/// Makes the design system available below it.
class IrisTheme extends InheritedWidget {
  const IrisTheme({required this.data, required super.child, super.key});

  final IrisThemeData data;

  /// The nearest theme.
  ///
  /// Asserts rather than falling back: a widget rendering without the design
  /// system is a wiring bug, and a silent default would hide it until it
  /// reached a screenshot.
  static IrisThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<IrisTheme>();
    assert(
      theme != null,
      'No IrisTheme above this widget. Wrap it in IrisApp.',
    );
    return theme!.data;
  }

  static IrisThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IrisTheme>()?.data;

  @override
  bool updateShouldNotify(IrisTheme oldWidget) => oldWidget.data != data;
}

/// Shorthands, so a build method reads as design rather than as plumbing.
///
/// `context.palette.accent` instead of `IrisTheme.of(context).palette.accent`
/// is a small thing repeated several thousand times.
extension IrisThemeContext on BuildContext {
  IrisThemeData get iris => IrisTheme.of(this);
  IrisPalette get palette => IrisTheme.of(this).palette;
  IrisTypography get type => IrisTheme.of(this).typography;

  /// Whether the system has asked for reduced motion. Every animated widget in
  /// Iris checks this; the design system's job is to make that one call.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}

/// Cross-fades the whole design system when the skin or brightness changes.
///
/// A skin switch that snaps looks like a bug; one that animates every colour
/// independently looks like a disco. This interpolates a single [IrisThemeData]
/// at the root, so the entire tree moves together as one image.
class AnimatedIrisTheme extends StatelessWidget {
  const AnimatedIrisTheme({
    required this.data,
    required this.child,
    this.duration = IrisDurations.normal,
    super.key,
  });

  final IrisThemeData data;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A keyed cross-fade rather than colour-by-colour interpolation: the
    // palette is derived, so there is no meaningful halfway skin, and fading
    // between two fully-resolved renderings is both simpler and truer.
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : duration,
      switchInCurve: IrisCurves.standard,
      switchOutCurve: IrisCurves.standard,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey((data.skin, data.isDark)),
        child: IrisTheme(data: data, child: child),
      ),
    );
  }
}
