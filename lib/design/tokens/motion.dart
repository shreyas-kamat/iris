/// Motion.
///
/// Everything that moves in Iris moves on a spring, not a duration curve. The
/// reason is interruptibility: a phone UI is constantly interrupted mid-gesture,
/// and a spring carries its current velocity into the new target, while a
/// duration curve restarts and produces the small visual stutter that makes an
/// interface feel like software instead of like an object.
///
/// The scale is small on purpose. Four springs and three durations cover the
/// whole app; a system with a dozen easing curves has no rhythm, only variety.
library;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The named springs.
///
/// Each is critically damped or just under, so nothing visibly oscillates —
/// bounce reads as a toy, and this app tells people when a command is about to
/// delete their files. The differences are in *settling speed*, which is what
/// distinguishes a chip snapping into place from a sheet arriving.
abstract final class IrisSprings {
  /// Immediate feedback: a chip toggling, a checkbox, a press state.
  static const SpringDescription snappy = SpringDescription(
    mass: 1,
    stiffness: 620,
    damping: 42,
  );

  /// The default. Cards appearing, list items settling, most state changes.
  static const SpringDescription standard = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 34,
  );

  /// Sheets, page transitions — anything large enough that speed reads as
  /// violence.
  static const SpringDescription gentle = SpringDescription(
    mass: 1,
    stiffness: 210,
    damping: 28,
  );

  /// The aperture's dilation and the connection pulse. Slow and soft, because
  /// it is ambient: it should register peripherally and never pull the eye off
  /// the text being read.
  static const SpringDescription ambient = SpringDescription(
    mass: 1,
    stiffness: 90,
    damping: 22,
  );
}

/// Durations, for the few things a spring cannot express.
///
/// Cross-fades and colour interpolation have no physical analogue — nothing is
/// being thrown or pulled — so they use a curve. Motion through *space* uses a
/// spring; change of *appearance* uses these.
abstract final class IrisDurations {
  /// Colour and opacity changes on a control.
  static const Duration quick = Duration(milliseconds: 120);

  /// Cross-fades, state colour shifts.
  static const Duration normal = Duration(milliseconds: 220);

  /// The aperture's hue transition between agent states — deliberately slow, so
  /// a run that flickers between tool calls does not strobe.
  static const Duration hue = Duration(milliseconds: 520);

  /// One cycle of the idle breath.
  static const Duration breath = Duration(milliseconds: 2600);
}

/// Easing for the duration-based cases.
abstract final class IrisCurves {
  /// Appearance changes. Fast out, slow in.
  static const Curve standard = Cubic(0.2, 0, 0, 1);

  /// Something leaving. Slower start so the exit is readable.
  static const Curve exit = Cubic(0.4, 0, 1, 1);

  /// The ambient breath. Symmetric, so it has no attack.
  static const Curve breath = Curves.easeInOutSine;
}

/// Drives an [AnimationController] with a spring instead of a duration.
extension SpringAnimation on AnimationController {
  /// Springs to [target] from the current value, carrying current velocity.
  ///
  /// Carrying velocity is the whole point: a gesture released mid-flight
  /// continues rather than restarting, which is what makes a dragged sheet feel
  /// attached to the finger.
  TickerFuture springTo(
    double target, {
    SpringDescription spring = IrisSprings.standard,
  }) => animateWith(
    SpringSimulation(spring, value, target, velocity * _velocityScale),
  );

  /// `AnimationController.velocity` is per second in unit terms, which is
  /// already what `SpringSimulation` wants; the scale exists so the conversion
  /// has one place to change if that ever stops being true.
  static const double _velocityScale = 1;
}

/// An [ImplicitlyAnimatedWidget]-style builder that animates a double on a
/// spring.
///
/// Flutter's implicit animations are all duration-based, so this fills the gap
/// for the many places wanting `AnimatedFoo` semantics with spring physics —
/// the aperture's dilation, a card's press scale, a panel's height.
class SpringBuilder extends StatefulWidget {
  const SpringBuilder({
    required this.value,
    required this.builder,
    this.spring = IrisSprings.standard,
    this.child,
    super.key,
  });

  /// The target. Changing it springs from wherever the animation currently is.
  final double value;

  final SpringDescription spring;

  final Widget Function(BuildContext context, double value, Widget? child)
  builder;

  final Widget? child;

  @override
  State<SpringBuilder> createState() => _SpringBuilderState();
}

class _SpringBuilderState extends State<SpringBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.value,
  );

  @override
  void didUpdateWidget(SpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      // Respect the accessibility setting: someone who has asked the system to
      // stop animating should get the new value immediately, not a slower
      // version of the same motion.
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.value;
      } else {
        _controller.animateWith(
          SpringSimulation(
            widget.spring,
            _controller.value,
            widget.value,
            _controller.velocity,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) =>
        widget.builder(context, _controller.value, child),
    child: widget.child,
  );
}
