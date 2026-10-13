/// The iris orb: the one mark that carries the agent's state everywhere.
///
/// The app answers three questions about a machine it cannot see: is it alive,
/// what is it doing, and does it need you. The orb answers all three before
/// anything is read. It is a ring with a bright centre dot. Colour names the
/// state, the ring's shape and motion say how it is moving, and the dot's
/// pulse says how alive it is. Three channels, so it stays legible to someone
/// who cannot tell the colours apart.
///
/// This is a port of `design/iris.js`, the renderer from the Iris design. The
/// parameter table, the easing and the paint order are kept from that file so
/// the orb matches the design. Where Flutter differs, the difference is noted
/// beside the code that makes it.
///
/// It is the only place in the interface with continuous motion. Under reduced
/// motion it paints one still frame and runs no ticker, so a list of orbs costs
/// nothing and `pumpAndSettle` in tests can finish.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/palette.dart';

/// A live indicator of what the agent is doing.
class IrisOrb extends StatefulWidget {
  const IrisOrb({
    required this.state,
    this.size = IrisSize.orb,
    this.glow = true,
    this.semanticLabel,
    super.key,
  });

  final AgentState state;
  final double size;

  /// Whether the orb bleeds light into its surroundings. Off for orbs sitting
  /// on a tile, where a halo would spill over the tile's edge.
  final bool glow;

  /// Overrides the spoken description. The default describes the state in
  /// words, because the meaning of this mark is otherwise purely visual.
  final String? semanticLabel;

  @override
  State<IrisOrb> createState() => _IrisOrbState();
}

/// The parameters one state asks the orb to become. Field names follow
/// `iris.js`: `ring` is the radius as a share of the box, `w` the stroke width,
/// `arc` how much of the ring is drawn, `seg` how many separate arcs (0 for a
/// continuous ring), `spin` the rotation rate, `wob` the radial wobble, `glow`
/// the halo strength, `sat` a satellite dot, `track` the faint full ring behind
/// the arc, and `alpha` an overall opacity.
class _OrbSpec {
  const _OrbSpec({
    required this.dot,
    required this.pulse,
    required this.pf,
    required this.ring,
    required this.w,
    required this.arc,
    required this.seg,
    required this.spin,
    required this.wob,
    required this.glow,
    required this.sat,
    required this.track,
    required this.alpha,
  });

  final double dot;
  final double pulse;
  final double pf;
  final double ring;
  final double w;
  final double arc;
  final double seg;
  final double spin;
  final double wob;
  final double glow;
  final double sat;
  final double track;
  final double alpha;

  /// The fields in a fixed order, so the frame can ease them uniformly. The
  /// indices are named by the constants below and must match this order.
  List<double> get values => [
    dot,
    pulse,
    pf,
    ring,
    w,
    arc,
    seg,
    spin,
    wob,
    glow,
    sat,
    track,
    alpha,
  ];

  /// Whether this state has continuous motion of its own. Used to decide if the
  /// ticker may stop once the values have settled.
  bool get moves => spin != 0 || wob != 0 || pulse > _stillPulse;
}

/// Pulse amplitudes at or below this are imperceptible, and treating them as
/// still lets a done or failed orb stop its ticker. Their pulse is 0.03 to 0.04
/// in the design, which reads as a breath no one would see as motion.
const double _stillPulse = 0.05;

// Indices into `_OrbSpec.values`.
const int _iDot = 0;
const int _iPulse = 1;
const int _iPf = 2;
const int _iRing = 3;
const int _iW = 4;
const int _iArc = 5;
const int _iSeg = 6;
const int _iSpin = 7;
const int _iWob = 8;
const int _iGlow = 9;
const int _iSat = 10;
const int _iTrack = 11;
const int _iAlpha = 12;

/// The design's parameter table, keyed by the design's own state names:
/// idle, rest, thinking, loading, tool (our `working`), streaming, success
/// (our `done`), failed, offline. `waiting` has no design counterpart and is
/// tuned to read as urgent without being alarming.
_OrbSpec _specFor(AgentState state) => switch (state) {
  AgentState.idle => const _OrbSpec(
    dot: .15,
    pulse: .05,
    pf: .5,
    ring: .36,
    w: .032,
    arc: 1,
    seg: 0,
    spin: .25,
    wob: 0,
    glow: .55,
    sat: 0,
    track: 0,
    alpha: 1,
  ),
  AgentState.rest => const _OrbSpec(
    dot: .13,
    pulse: 0,
    pf: .5,
    ring: .35,
    w: .03,
    arc: 1,
    seg: 0,
    spin: 0,
    wob: 0,
    glow: 0,
    sat: 0,
    track: 0,
    alpha: .75,
  ),
  AgentState.thinking => const _OrbSpec(
    dot: .13,
    pulse: .2,
    pf: 1.6,
    ring: .38,
    w: .045,
    arc: .72,
    seg: 3,
    spin: 2.4,
    wob: 0,
    glow: .95,
    sat: 0,
    track: .12,
    alpha: 1,
  ),
  AgentState.loading => const _OrbSpec(
    dot: .1,
    pulse: .08,
    pf: 1,
    ring: .36,
    w: .05,
    arc: .3,
    seg: 0,
    spin: 5.2,
    wob: 0,
    glow: .7,
    sat: 0,
    track: .14,
    alpha: 1,
  ),
  AgentState.working => const _OrbSpec(
    dot: .14,
    pulse: .1,
    pf: 1.2,
    ring: .38,
    w: .04,
    arc: .62,
    seg: 6,
    spin: 1.3,
    wob: 0,
    glow: .75,
    sat: 1,
    track: .1,
    alpha: 1,
  ),
  AgentState.streaming => const _OrbSpec(
    dot: .16,
    pulse: .08,
    pf: 2.4,
    ring: .37,
    w: .04,
    arc: 1,
    seg: 0,
    spin: .7,
    wob: .07,
    glow: .9,
    sat: 0,
    track: 0,
    alpha: 1,
  ),
  AgentState.waiting => const _OrbSpec(
    dot: .15,
    pulse: .28,
    pf: 2.2,
    ring: .37,
    w: .045,
    arc: 1,
    seg: 0,
    spin: .4,
    wob: 0,
    glow: .9,
    sat: 0,
    track: 0,
    alpha: 1,
  ),
  AgentState.done => const _OrbSpec(
    dot: .17,
    pulse: .03,
    pf: .6,
    ring: .38,
    w: .045,
    arc: 1,
    seg: 0,
    spin: 0,
    wob: 0,
    glow: 1,
    sat: 0,
    track: 0,
    alpha: 1,
  ),
  AgentState.failed => const _OrbSpec(
    dot: .15,
    pulse: .04,
    pf: .8,
    ring: .37,
    w: .042,
    arc: .84,
    seg: 0,
    spin: 0,
    wob: 0,
    glow: .6,
    sat: 0,
    track: .1,
    alpha: 1,
  ),
  AgentState.offline => const _OrbSpec(
    dot: .11,
    pulse: 0,
    pf: .5,
    ring: .35,
    w: .026,
    arc: 1,
    seg: 12,
    spin: .1,
    wob: 0,
    glow: 0,
    sat: 0,
    track: 0,
    alpha: .6,
  ),
};

/// The animated values, plus the time and rotation they run on.
///
/// Kept apart from the State so the painter can repaint on it directly. Each
/// tick notifies this object rather than calling setState, so a tick repaints
/// only the orb and not the widget tree above it.
class _OrbFrame extends ChangeNotifier {
  /// The eased parameters, in `_OrbSpec.values` order.
  final List<double> v = List<double>.filled(13, 0);

  /// The eased colour. Lerped in sRGB, as the design does.
  Color color = const Color(0xFF000000);

  /// Elapsed animation time, in seconds. Drives the pulse and wobble.
  double t = 0;

  /// Rotation of the ring, in radians.
  double rot = 0;

  /// Horizontal shake after a failure, decaying at 1.6 per second.
  double shake = 0;

  /// The ring's expanding flash after completion, decaying at 1.1 per second.
  double burst = 0;

  /// Jumps straight to [target]. Used on the first frame and under reduced
  /// motion, where easing would be a motion the user asked us not to show.
  void snapTo(_OrbSpec target, Color targetColor) {
    final values = target.values;
    for (var i = 0; i < v.length; i++) {
      v[i] = values[i];
    }
    color = targetColor;
    t = 0;
    rot = 0;
    shake = 0;
    burst = 0;
    notifyListeners();
  }

  /// Advances the easing by [dt] seconds towards [target]. The step is capped
  /// at 50ms so a stall (a backgrounded app, a slow frame) does not make the
  /// orb leap.
  void step(double dt, _OrbSpec target, Color targetColor) {
    t += dt;
    // Five-per-second easing, as in iris.js. It reaches 99% of a change in
    // roughly a second, which is quick enough to feel responsive and slow
    // enough that a colour change reads as a change.
    final k = math.min(1.0, dt * 5);
    final goal = target.values;
    for (var i = 0; i < v.length; i++) {
      // The segment count is discrete, so it snaps. Easing an integer through
      // 2.5 segments would draw an arc count that does not exist.
      if (i == _iSeg) {
        v[i] = goal[i];
      } else {
        v[i] += (goal[i] - v[i]) * k;
      }
    }
    color = Color.lerp(color, targetColor, k)!;
    rot += v[_iSpin] * dt;
    shake = math.max(0, shake - dt * 1.6);
    burst = math.max(0, burst - dt * 1.1);
  }

  /// Whether nothing is left to animate: every value is at its target, no
  /// flash or shake is pending, and the target itself has no motion. Once this
  /// holds the ticker stops, which is why a settled rest orb costs no frames.
  /// Asks the painter to repaint. Exposed as a method because the State cannot
  /// call the protected [notifyListeners] itself.
  void markDirty() => notifyListeners();

  bool settled(_OrbSpec target, Color targetColor) {
    if (shake > 0 || burst > 0 || target.moves) return false;
    final goal = target.values;
    for (var i = 0; i < v.length; i++) {
      if ((v[i] - goal[i]).abs() > .001) return false;
    }
    return (color.r - targetColor.r).abs() < .002 &&
        (color.g - targetColor.g).abs() < .002 &&
        (color.b - targetColor.b).abs() < .002;
  }
}

class _IrisOrbState extends State<IrisOrb> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _OrbFrame _frame = _OrbFrame();

  /// The colour the current state wants, from the palette. Held here so the
  /// ticker does not need a BuildContext on every frame.
  Color _targetColor = const Color(0xFF000000);

  Duration _last = Duration.zero;
  bool _reduced = false;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Seeded from the object's identity rather than Random, so goldens stay
    // stable from run to run. The hash also staggers orbs on one screen, so a
    // row of them does not pulse in lockstep.
    final seed = identityHashCode(this);
    _frame.t = (seed % 1000) / 100;
    _frame.rot = (seed % 613) / 613 * 2 * math.pi;
    _frame.snapTo(_specFor(widget.state), const Color(0xFF000000));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: both the palette and the
    // reduced-motion setting are inherited, and an inherited lookup in
    // initState is illegal.
    _reduced = context.reduceMotion;
    _targetColor = context.palette.colorFor(widget.state);
    if (!_seeded) {
      // The first colour is the target, so the orb does not sweep in from black.
      _seeded = true;
      _frame.color = _targetColor;
    }
    _sync();
  }

  @override
  void didUpdateWidget(IrisOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      // A failure shakes and a completion flashes. These are one-off
      // announcements, so they are skipped under reduced motion along with
      // everything else that moves.
      if (!_reduced) {
        if (widget.state == AgentState.failed) _frame.shake = 1;
        if (widget.state == AgentState.done) _frame.burst = 1;
      }
    }
    _targetColor = context.palette.colorFor(widget.state);
    _sync();
  }

  /// Brings the frame in line with the current state and palette. Under
  /// reduced motion it snaps and stops; otherwise it starts the ticker only if
  /// there is something left to ease.
  void _sync() {
    final target = _specFor(widget.state);
    if (_reduced) {
      _ticker.stop();
      _frame.snapTo(target, _targetColor);
      return;
    }
    if (!_frame.settled(target, _targetColor) && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    // The first tick after a start arrives with elapsed near zero, so dt is
    // measured from the last tick rather than from the frame's own clock.
    final dt = math.min(.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    final target = _specFor(widget.state);
    _frame.step(dt, target, _targetColor);
    if (_frame.settled(target, _targetColor)) {
      _ticker.stop();
    }
    _frame.markDirty();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
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
    AgentState.offline => 'Offline',
    AgentState.rest => 'Finished',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel ?? _describe(widget.state),
      liveRegion: widget.state == AgentState.waiting,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _IrisOrbPainter(
              frame: _frame,
              glow: widget.glow,
              failed: widget.state == AgentState.failed,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints one frame of the orb, in the order `iris.js` paints it: halo, track,
/// ring, satellite, completion flash, centre dot.
class _IrisOrbPainter extends CustomPainter {
  _IrisOrbPainter({
    required this.frame,
    required this.glow,
    required this.failed,
  }) : super(repaint: frame);

  final _OrbFrame frame;
  final bool glow;

  /// A failed ring is not a full ring that fades out. It is an open arc at the
  /// bottom that does not fade, which reads as broken rather than as spinning.
  final bool failed;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final v = frame.v;
    final t = frame.t;
    final alpha = v[_iAlpha];
    final glowLevel = v[_iGlow];
    final glowOn = glow && glowLevel > .01;

    // Colours are the state's colour at a given alpha, scaled by the state's
    // own alpha, as `col()` does in iris.js.
    Color col(double a) =>
        frame.color.withValues(alpha: (a * alpha).clamp(0.0, 1.0));

    canvas.save();
    // The shake is a horizontal wobble that grows with the square of the decay,
    // so it is sharp at the moment of failure and dies away quickly.
    final shakeOffset = math.sin(t * 55) * frame.shake * frame.shake * s * .045;
    canvas.translate(shakeOffset, 0);

    // 1. Halo: a radial falloff across the whole box.
    if (glowOn) {
      final halo = Paint()
        ..shader = ui.Gradient.radial(
          c,
          s * .5,
          [col(.32 * glowLevel), col(.12 * glowLevel), col(0)],
          [0, .45, 1],
        );
      canvas.drawRect(Offset.zero & size, halo);
    }

    final radius = s * v[_iRing];
    final width = math.max(1.0, s * v[_iW]);
    final wobble = v[_iWob];
    final full = 2 * math.pi;
    final base = frame.rot - math.pi / 2;

    // A point on the ring at angle [a]. The radius wobbles with two
    // interfering sines, so the outline breathes without looking like a
    // circle that is merely scaling.
    Offset pointAt(double a) {
      final r =
          radius *
          (1 + wobble * math.sin(a * 5 + t * 3.2) * math.sin(a * 3 - t * 2.1));
      return c + Offset(math.cos(a), math.sin(a)) * r;
    }

    // 2. Track: a faint full ring behind the arc, for states that want the
    // shape of the whole ring even while only part of it is lit.
    if (v[_iTrack] > .01) {
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = col(v[_iTrack]);
      canvas.drawCircle(c, radius, track);
    }

    // 3. The ring. First work out which arcs to draw, as (start, length, fade).
    final arcs = <(double, double, bool)>[];
    final seg = v[_iSeg];
    final arc = v[_iArc];
    if (seg >= 1) {
      final n = seg.round();
      final slot = full / n;
      final len = slot * math.min(.92, arc);
      for (var i = 0; i < n; i++) {
        arcs.add((base + i * slot, len, false));
      }
    } else if (arc > .985) {
      arcs.add((base, full, false));
    } else if (failed) {
      arcs.add((-math.pi / 2 + full * (1 - arc) / 2 + math.pi, full * arc, false));
    } else {
      arcs.add((base, full * arc, true));
    }

    // The halo's blurred copy stands in for canvas shadowBlur. It is drawn
    // under the ring, so it reads as light from the stroke rather than a
    // second stroke.
    if (glowOn) {
      final blur = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = col(.8 * glowLevel)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          s * .04 * glowLevel,
        );
      for (final (start, len, _) in arcs) {
        canvas.drawPath(_arcPath(start, len, pointAt), blur);
      }
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final (start, len, fade) in arcs) {
      if (!fade) {
        stroke.color = col(1);
        canvas.drawPath(_arcPath(start, len, pointAt), stroke);
        continue;
      }
      // A fading arc is drawn as sub-segments whose alpha rises towards the
      // head, so the tail dissolves rather than ending in a hard edge. The
      // curve (1.6) keeps most of the arc solid and fades only the last part.
      final n = math.max(6, (len * 40).ceil());
      for (var i = 0; i < n; i++) {
        final f0 = i / n;
        final f1 = (i + 1) / n;
        final aA = start + len * f0;
        final aB = start + len * f1;
        final am = (aA + aB) / 2;
        final path = Path()
          ..moveTo(pointAt(aA).dx, pointAt(aA).dy)
          ..lineTo(pointAt(am).dx, pointAt(am).dy)
          ..lineTo(pointAt(aB).dx, pointAt(aB).dy);
        stroke.color = col(.12 + .88 * math.pow(f1, 1.6).toDouble());
        canvas.drawPath(path, stroke);
      }
    }

    // 4. Satellite: a small dot that orbits just outside the ring. Only the
    // active tool state has one.
    if (v[_iSat] > .02) {
      final a = frame.rot * 1.9;
      final orbit = radius + width * 2.2;
      final at = c + Offset(math.cos(a), math.sin(a)) * orbit;
      canvas.drawCircle(at, width * .7, Paint()..color = col(v[_iSat]));
    }

    // 5. Completion flash: a ring that expands and fades as `burst` falls.
    if (frame.burst > 0) {
      final p = 1 - frame.burst;
      final flash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * frame.burst
        ..color = col(frame.burst * .8);
      canvas.drawCircle(c, radius * (1 + p * .3), flash);
    }

    // 6. Centre dot, pulsing, lit from the upper left. The white highlight
    // sits at the focal point, which gives the dot a sphere rather than a disc.
    final dotRadius = s * v[_iDot] * (1 + v[_iPulse] * math.sin(t * v[_iPf] * full));
    if (glowOn && dotRadius > 0) {
      final dotBlur = Paint()
        ..color = col(.8 * glowLevel)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          s * .04 * glowLevel,
        );
      canvas.drawCircle(c, dotRadius, dotBlur);
    }
    if (dotRadius > 0) {
      final focal = Offset(
        c.dx - dotRadius * .3,
        c.dy - dotRadius * .35,
      );
      final dot = Paint()
        ..shader = ui.Gradient.radial(
          c,
          dotRadius,
          [
            const Color(0xFFFFFFFF).withValues(alpha: (.95 * alpha).clamp(0.0, 1.0)),
            col(1),
            col(.85),
          ],
          [0, .35, 1],
          ui.TileMode.clamp,
          null,
          focal,
          dotRadius * .1,
        );
      canvas.drawCircle(c, dotRadius, dot);
    }

    canvas.restore();
  }

  /// A path tracing the ring from [start] over [len] radians, sampled finely
  /// enough that the wobble shows.
  static Path _arcPath(double start, double len, Offset Function(double) at) {
    final n = math.max(6, (len * 40).ceil());
    final path = Path();
    for (var i = 0; i <= n; i++) {
      final p = at(start + len * i / n);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_IrisOrbPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.glow != glow ||
      oldDelegate.failed != failed;
}
