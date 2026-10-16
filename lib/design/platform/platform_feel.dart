/// The parts of "native" that are not visual.
///
/// Iris uses one visual language on both platforms, which is a deliberate
/// choice. What makes it still feel native is everything underneath the pixels:
/// how a list decelerates, which way the back gesture goes, what the phone does
/// in your hand when you commit to something. Those are not cosmetic, and they
/// are the parts a person notices without being able to name.
///
/// Everything here is centralised so a widget never branches on the platform
/// itself. A `Platform.isIOS` scattered through feature code is how the two
/// platforms quietly drift apart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which set of conventions to follow.
///
/// Read from [defaultTargetPlatform] rather than `dart:io`, so it resolves in
/// tests and honours `debugDefaultTargetPlatformOverride` - which is how a
/// golden can capture the Android treatment from a machine running iOS.
enum IrisPlatform {
  ios,
  android,
  other;

  static IrisPlatform get current => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => IrisPlatform.ios,
    TargetPlatform.android => IrisPlatform.android,
    _ => IrisPlatform.other,
  };

  /// Takes a context for symmetry with the rest of the design system and so
  /// this can later consult an inherited override without changing callers.
  static IrisPlatform of(BuildContext context) => current;
}

/// Scroll physics that match the platform.
///
/// iOS scrolling overscrolls and springs back; Android glows and stops. Getting
/// this wrong is the single clearest tell that an app was built somewhere else,
/// and it costs one line to get right.
abstract final class IrisScroll {
  static ScrollPhysics physicsFor(BuildContext context) =>
      switch (IrisPlatform.of(context)) {
        IrisPlatform.ios => const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        IrisPlatform.android || IrisPlatform.other =>
          const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      };
}

/// Haptics, named by what they mean rather than by how strong they are.
///
/// Naming them by intent is what keeps them consistent: `selection` is always
/// the same weight everywhere in the app, and a screen cannot quietly decide
/// that its button deserves a heavier thump than every other button.
///
/// Android's haptic vocabulary is coarser than iOS's, so several of these
/// collapse to the same call there. That is correct - imitating iOS's finer
/// grades with vibration patterns feels worse than matching the platform.
abstract final class IrisHaptics {
  /// A value changed: a chip toggled, a picker moved, a tab switched.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// A message was sent, a run started. Light, affirmative.
  static Future<void> commit() => HapticFeedback.lightImpact();

  /// An approval gate arrived and is blocking. Deliberately heavier than
  /// anything else in the app: it is the one moment Iris interrupts a person,
  /// and it should feel like an interruption.
  static Future<void> gate() => HapticFeedback.heavyImpact();

  /// A run finished cleanly.
  static Future<void> settled() => HapticFeedback.mediumImpact();

  /// Something failed. Not a heavier tap - a distinct pattern, so failure is
  /// distinguishable from success without looking at the screen.
  static Future<void> failed() => HapticFeedback.vibrate();
}

/// The page push, drawn the same way on every platform.
///
/// This is the design's own transition, not the platform's. The incoming page
/// slides in from just off the right edge on a long, soft curve, and it casts
/// a shadow to its left so it reads as lying on top of the page beneath. The
/// page beneath drifts a short way to the left rather than sliding out fully.
///
/// Matching one motion everywhere is deliberate. The app's whole rhythm (orb,
/// sheets, pushes) comes from one curve, and an Android-style scale would fight
/// it. Under reduced motion the page appears with no movement at all.
final class IrisPageRoute<T> extends PageRoute<T> {
  IrisPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  /// The design's curve, a fast start that settles without overshooting.
  static const Curve _curve = Cubic(0.32, 0.72, 0, 1);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  /// The forward push is slower than the return, so the page feels like it
  /// settles into place and then leaves briskly.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 380);

  /// Only another page pushes this one aside. A sheet, dialog or any other
  /// route opened over it leaves it where it is; otherwise the page drifts
  /// left under the scrim and the screen behind shows through.
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is IrisPageRoute;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    // The page beneath this one drifts left while this page covers it. That
    // is driven by `secondaryAnimation`, which runs when another route is
    // pushed over this one.
    final beneath = SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.28, 0),
      ).animate(CurvedAnimation(parent: secondaryAnimation, curve: _curve)),
      child: child,
    );

    // The incoming page slides from just outside the edge, so a sliver of it
    // is visible from the first frame and the motion never looks like a
    // page popping in.
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.05, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: _curve)),
      child: DecoratedBox(
        // The shadow falls to the left, onto the page underneath. It is what
        // makes the incoming page read as a layer rather than a flat wipe.
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 60,
              offset: Offset(-30, 0),
            ),
          ],
        ),
        child: beneath,
      ),
    );
  }
}

/// Applies the platform's scroll physics to everything beneath it.
///
/// Wrapped once at the app root so no individual list has to remember.
class IrisScrollBehavior extends ScrollBehavior {
  const IrisScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      IrisScroll.physicsFor(context);

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      // iOS expresses overscroll through the bounce itself; drawing Android's
      // glow on top of it would be two answers to the same question.
      IrisPlatform.of(context) == IrisPlatform.ios
      ? child
      : super.buildOverscrollIndicator(context, child, details);
}
