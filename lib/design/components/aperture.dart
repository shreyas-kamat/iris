/// The aperture — the one element Iris is meant to be remembered by.
///
/// The whole app answers three questions about a machine you cannot see: is it
/// alive, what is it doing, and does it need you. Everywhere else those are
/// answered in words. Here they are answered in one 26pt mark that is always on
/// screen, so the answer arrives before you have read anything.
///
/// It is an iris, in both senses the app is named for. A ring with a pupil that
/// dilates: wide while the agent is thinking or working, contracted at rest,
/// pulsing when it is blocked and needs a person. Hue carries the state, motion
/// carries the liveness, and size carries the intensity — three channels, so it
/// stays legible to someone who cannot distinguish the colours.
///
/// It is the only place in the interface allowed continuous motion. Everything
/// else is still until touched, which is what keeps this readable rather than
/// making the screen twitch.
library;

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';

/// A live indicator of what the agent is doing.
class Aperture extends StatefulWidget {
  const Aperture({
    required this.state,
    this.size = IrisSize.aperture,
    this.pulse,
    this.semanticLabel,
    super.key,
  });

  final AgentState state;
  final double size;

  /// Bumped by the caller each time a token arrives, to flick the pupil.
  ///
  /// A counter rather than a callback so the widget stays pure: the transcript
  /// already knows how many deltas it has seen, and passing that number is
  /// cheaper than plumbing a stream down here.
  final int? pulse;

  /// Overrides the spoken description. The default describes the state in
  /// words, because the entire meaning of this widget is otherwise visual.
  final String? semanticLabel;

  @override
  State<Aperture> createState() => _ApertureState();
}

class _ApertureState extends State<Aperture> with TickerProviderStateMixin {
  /// Continuous, for the idle breath and the sweeping activity arc.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: IrisDurations.breath,
  );

  /// Unbounded, so the pupil can be sprung to a new dilation from wherever it
  /// currently is rather than restarting.
  late final AnimationController _dilation = AnimationController.unbounded(
    vsync: this,
    value: _targetDilation(AgentState.idle),
  );

  /// Decays after each token, producing a flick rather than a sustained bump.
  late final AnimationController _flick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _dilation.value = _targetDilation(widget.state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not in initState: _syncAmbient reads MediaQuery for the reduced-motion
    // setting, and an inherited lookup there is illegal — and would also miss
    // the user turning the setting on while the app is running.
    _syncAmbient();
  }

  @override
  void didUpdateWidget(Aperture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      final target = _targetDilation(widget.state);
      if (context.reduceMotion) {
        _dilation.value = target;
      } else {
        _dilation.animateWith(
          SpringSimulation(
            _springFor(widget.state),
            _dilation.value,
            target,
            _dilation.velocity,
          ),
        );
      }
      _syncAmbient();
    }
    if (widget.pulse != oldWidget.pulse && !context.reduceMotion) {
      _flick.forward(from: 0);
    }
  }

  /// The ambient controller only runs when it has something to express, so a
  /// finished conversation costs no frames.
  void _syncAmbient() {
    final wants = switch (widget.state) {
      AgentState.idle ||
      AgentState.thinking ||
      AgentState.streaming ||
      AgentState.working ||
      AgentState.waiting || AgentState.loading => true,
      AgentState.done || AgentState.failed || AgentState.offline || AgentState.rest => false,
    };
    if (context.reduceMotion) {
      _ambient.stop();
      return;
    }
    if (wants && !_ambient.isAnimating) {
      _ambient.repeat();
    } else if (!wants && _ambient.isAnimating) {
      _ambient.stop();
    }
  }

  /// How far the pupil opens, as a fraction of the outer radius.
  static double _targetDilation(AgentState state) => switch (state) {
    AgentState.idle => 0.30,
    AgentState.thinking => 0.52,
    AgentState.streaming => 0.62,
    AgentState.working => 0.46,
    // Contracted and hot: a narrowed pupil reads as attention, and the pulse
    // does the work of demanding it.
    AgentState.waiting => 0.24,
    AgentState.done => 0.38,
    AgentState.failed => 0.20,
    AgentState.loading => 0.40,
    AgentState.offline => 0.22,
    AgentState.rest => 0.36,
  };

  static SpringDescription _springFor(AgentState state) => switch (state) {
    AgentState.waiting || AgentState.failed => IrisSprings.snappy,
    _ => IrisSprings.ambient,
  };

  @override
  void dispose() {
    _ambient.dispose();
    _dilation.dispose();
    _flick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: widget.semanticLabel ?? _describe(widget.state),
      liveRegion: widget.state == AgentState.waiting,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ambient, _dilation, _flick]),
          builder: (context, _) {
            // Colour is animated by a tween rather than sprung: hue is an
            // appearance change, and springing it would overshoot into a hue
            // that means something else.
            return TweenAnimationBuilder<Color?>(
              duration: context.reduceMotion
                  ? Duration.zero
                  : IrisDurations.hue,
              curve: IrisCurves.standard,
              tween: ColorTween(end: palette.colorFor(widget.state)),
              builder: (context, color, _) => CustomPaint(
                painter: _AperturePainter(
                  color: color ?? palette.colorFor(widget.state),
                  ringColor: palette.line,
                  dilation: _dilation.value.clamp(0.0, 0.85),
                  ambient: _ambient.value,
                  flick: Curves.easeOut.transform(1 - _flick.value),
                  state: widget.state,
                  isDark: palette.isDark,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _describe(AgentState state) => switch (state) {
    AgentState.idle => 'Agent idle',
    AgentState.thinking => 'Agent thinking',
    AgentState.streaming => 'Agent replying',
    AgentState.working => 'Agent running a tool',
    AgentState.waiting => 'Agent waiting for you',
    AgentState.done => 'Run finished',
    AgentState.failed => 'Run failed',
    AgentState.loading => 'Connecting',
    AgentState.offline => 'Gateway offline',
    AgentState.rest => 'Run finished',
  };
}

class _AperturePainter extends CustomPainter {
  const _AperturePainter({
    required this.color,
    required this.ringColor,
    required this.dilation,
    required this.ambient,
    required this.flick,
    required this.state,
    required this.isDark,
  });

  final Color color;
  final Color ringColor;
  final double dilation;
  final double ambient;
  final double flick;
  final AgentState state;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;

    // Below this the ring and pupil merge into a smudge, so the small variant
    // drops to a plain dot. Better an honest dot than an illegible aperture.
    final isMinimal = size.width < 14;

    final breath = state == AgentState.idle
        ? 0.5 + 0.5 * math.sin(ambient * 2 * math.pi)
        : 1.0;

    // The approval pulse is deliberately not a sine: it snaps bright and decays,
    // which reads as an alert rather than as ambience.
    final urgency = state == AgentState.waiting
        ? math.pow(1 - (ambient * 2 % 1.0), 3).toDouble()
        : 0.0;

    if (isMinimal) {
      canvas.drawCircle(
        centre,
        radius * (0.62 + 0.10 * urgency),
        Paint()..color = color,
      );
      return;
    }

    final ringStroke = IrisStroke.ring * (size.width / IrisSize.aperture);
    final ringRadius = radius - ringStroke / 2;

    // The seat: a full, quiet ring so the mark has a stable outline even when
    // the pupil is nearly closed.
    canvas.drawCircle(
      centre,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStroke
        ..color = ringColor,
    );

    // A soft bloom, so an active agent glows rather than merely being coloured.
    // Only in dark themes: on a light ground a glow reads as a printing error.
    final activity = switch (state) {
      AgentState.thinking || AgentState.streaming || AgentState.working => 1.0,
      AgentState.waiting => 0.4 + 0.6 * urgency,
      _ => 0.0,
    };
    if (isDark && activity > 0) {
      // Kept well under a neon glow. An outer bloom is the signature of every
      // AI-styled dark interface, so this one has to earn its place: it appears
      // only while the agent is actually doing something, and at an alpha that
      // reads as the mark being lit rather than as decoration.
      canvas.drawCircle(
        centre,
        radius * (0.55 + 0.35 * dilation),
        Paint()
          ..color = color.withValues(alpha: 0.15 * activity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.40),
      );
    }

    // The pupil.
    final pupilRadius =
        radius * dilation * (0.94 + 0.06 * breath) * (0.88 + 0.12 * flick);
    canvas.drawCircle(
      centre,
      pupilRadius,
      Paint()
        ..color = color.withValues(
          alpha: state == AgentState.idle ? 0.85 : 1.0,
        ),
    );

    // The sweep: a short arc travelling the ring while work is happening. This
    // is what says "still alive" during a long tool call that produces no
    // output for thirty seconds — the case where a static indicator is
    // indistinguishable from a hung connection.
    final sweeps = switch (state) {
      AgentState.streaming => 1.0,
      AgentState.thinking => 0.7,
      AgentState.working => 0.85,
      _ => 0.0,
    };
    if (sweeps > 0) {
      final start =
          ambient * 2 * math.pi * (state == AgentState.working ? 1.6 : 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: ringRadius),
        start - math.pi / 2,
        math.pi * 0.42 * sweeps,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringStroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    // A failed run gets a static, complete ring in the error hue: closed, done,
    // nothing in flight.
    if (state == AgentState.failed || state == AgentState.done) {
      canvas.drawCircle(
        centre,
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringStroke
          ..color = color.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_AperturePainter old) =>
      old.color != color ||
      old.dilation != dilation ||
      old.ambient != ambient ||
      old.flick != flick ||
      old.state != state ||
      old.ringColor != ringColor;
}
