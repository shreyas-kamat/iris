/// The voice orb: the microphone, and the state of a call, in one mark.
///
/// A port of `design/iris-voice.js`, the renderer from the Iris Phase 4
/// design. The constants, the easing and the paint order are kept from that
/// file; where Flutter differs the difference is noted beside the code.
///
/// Colour names the mode, the ring's shape and motion say what it is doing,
/// and the level (the microphone's, or the agent's voice) swells the ring and
/// throws ripples. Every colour comes from [IrisPalette.voiceOrbColor].
///
/// Reduced motion draws O2, the design's still alternative: one frame per
/// level, with dashed outlines in place of ripples (none below .3, one below
/// .62, two above), and no ticker at all. A caller can ask for a still orb
/// that keeps a slow opacity pulse and cross-fades between level bands
/// (`still: true`); the system's reduced-motion setting always wins over that.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/palette.dart';

export '../tokens/palette.dart' show VoiceOrbMode;

/// Where the design puts the ring, as a share of the box: `s * .27`.
const double _ringShare = .27;

/// How much of its radius the ring gains at full level.
double _growthFor(VoiceOrbMode mode) => switch (mode) {
  VoiceOrbMode.hearing => .08,
  VoiceOrbMode.speaking => .07,
  _ => 0,
};

/// The ring's radius as a share of the orb's size, for [mode] at [level] (0 to
/// 1), without the idle and listening breathing. Hearing and speaking swell
/// with the level; every other mode ignores it.
@visibleForTesting
double ringRadiusFor(VoiceOrbMode mode, double level) =>
    _ringShare * (1 + _growthFor(mode) * level.clamp(0.0, 1.0));

/// Modes whose still frame breathes (opacity) when a pulse is asked for.
const _pulsing = {
  VoiceOrbMode.listening,
  VoiceOrbMode.hearing,
  VoiceOrbMode.speaking,
  VoiceOrbMode.thinking,
  VoiceOrbMode.tool,
  VoiceOrbMode.needs,
  VoiceOrbMode.offline,
  VoiceOrbMode.connecting,
};

class IrisVoiceOrb extends StatefulWidget {
  const IrisVoiceOrb({
    required this.mode,
    this.size = 120,
    this.level,
    this.still,
    this.semanticLabel,
    super.key,
  });

  final VoiceOrbMode mode;
  final double size;

  /// The microphone's level while hearing, or the agent's voice while
  /// speaking, from 0 to 1. Null uses the design's simulated level, for the
  /// gallery only.
  final ValueListenable<double>? level;

  /// Whether to draw the still alternative. Null follows the system's
  /// reduced-motion setting; true asks for a still orb that keeps a slow
  /// pulse (unless the system asks for reduced motion); false forces motion.
  final bool? still;

  /// Overrides the spoken description of [mode].
  final String? semanticLabel;

  @override
  State<IrisVoiceOrb> createState() => IrisVoiceOrbState();
}

class IrisVoiceOrbState extends State<IrisVoiceOrb>
    with SingleTickerProviderStateMixin {
  /// Created when there is something to animate, so a still orb never has
  /// one. Not created in [dispose]: a new ticker looks up TickerMode, which is
  /// illegal once the element is inactive.
  Ticker? _ticker;
  final _VoiceFrame _frame = _VoiceFrame();
  Duration _last = Duration.zero;

  bool _reduced = false;
  Color _target = Colors.transparent;
  Color _speaking = Colors.transparent;

  /// The eased level the ring is drawn with.
  @visibleForTesting
  double get smoothedLevel => _frame.shown;

  /// How present each still outline is, from 0 to 1.
  @visibleForTesting
  List<double> get ripplePresence => List.of(_frame.presence);

  /// The opacity the still pulse has reached; 1 when nothing pulses.
  @visibleForTesting
  double get pulseAlpha => _frame.alpha;

  bool get _still => widget.still ?? _reduced;

  /// The still orb may keep its slow pulse and band cross-fade.
  bool get _animateStill => widget.still == true && !_reduced;

  @override
  void initState() {
    super.initState();
    // Seeded from the object's identity rather than Random, so goldens stay
    // stable and a row of orbs does not move in lockstep.
    final seed = identityHashCode(this);
    _frame.tRaw = (seed % 2000) / 100;
    _frame.ph = (seed % 997) / 997;
    _frame.rot = (seed % 613) / 613 * 6;
    widget.level?.addListener(_onLevel);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = context.reduceMotion;
    _readPalette();
    _sync();
  }

  @override
  void didUpdateWidget(IrisVoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level?.removeListener(_onLevel);
      widget.level?.addListener(_onLevel);
    }
    _readPalette();
    _sync();
  }

  void _readPalette() {
    final palette = context.palette;
    _target = palette.voiceOrbColor(widget.mode);
    _speaking = palette.voiceOrbColor(VoiceOrbMode.speaking);
  }

  /// A new level. An animated orb reads it on its next tick; a still one has
  /// no tick, so it redraws now.
  void _onLevel() {
    if (!_still || !mounted) return;
    _step(0);
  }

  /// Brings the frame and the ticker in line with the widget.
  void _sync() {
    if (_still) {
      final moving = _step(0);
      if (_animateStill && moving) {
        _start();
      } else {
        _ticker?.stop();
      }
    } else {
      _start();
    }
  }

  void _start() {
    final ticker = _ticker ??= createTicker(_onTick);
    if (!ticker.isActive) {
      _last = Duration.zero;
      ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final moving = _step(dt);
    if (_still && !moving) _ticker?.stop();
  }

  /// Advances the frame and repaints. True when a still orb has more to do.
  bool _step(double dt) {
    final moving = _frame.advance(
      dt,
      mode: widget.mode,
      level: widget.level?.value,
      still: _still,
      animateStill: _animateStill,
      target: _target,
      speaking: _speaking,
    );
    _frame.markDirty();
    return moving;
  }

  @override
  void dispose() {
    widget.level?.removeListener(_onLevel);
    _ticker?.dispose();
    _frame.dispose();
    super.dispose();
  }

  static String _describe(VoiceOrbMode mode) => switch (mode) {
    VoiceOrbMode.idle => 'Voice idle',
    VoiceOrbMode.connecting => 'Connecting',
    VoiceOrbMode.listening => 'Listening',
    VoiceOrbMode.hearing => 'Hearing you',
    VoiceOrbMode.thinking => 'Thinking',
    VoiceOrbMode.tool => 'Running a tool',
    VoiceOrbMode.speaking => 'Speaking',
    VoiceOrbMode.interrupted => 'Interrupted',
    VoiceOrbMode.muted => 'Microphone muted',
    VoiceOrbMode.error => 'Voice error',
    VoiceOrbMode.needs => 'Needs you',
    VoiceOrbMode.offline => 'Offline',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel ?? _describe(widget.mode),
      liveRegion: widget.mode == VoiceOrbMode.needs,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _VoiceOrbPainter(frame: _frame, requested: widget.mode),
          ),
        ),
      ),
    );
  }
}

/// Everything the design keeps on the element between frames, plus what the
/// painter needs to draw the frame just advanced. Kept apart from the State so
/// a tick repaints only the orb.
class _VoiceFrame extends ChangeNotifier {
  /// `this.t` in the design: runs on whatever the clock says.
  double tRaw = 0;

  /// `this.rot`.
  double rot = 0;

  /// `this.ph`: a random phase that also advances with the ripples.
  double ph = 0;

  /// `this.L`: the level, eased with attack and release.
  double eased = 0;

  /// The eased colour, 0 to 255, lerped in sRGB as the design does.
  double r = 0;
  double g = 0;
  double b = 0;
  bool _seeded = false;

  /// How present the two still outlines are.
  final List<double> presence = [0, 0];

  // What the painter reads.
  VoiceOrbMode mode = VoiceOrbMode.idle;
  bool still = false;
  bool hold = false;

  /// The level the frame is drawn with: eased when animated, the target when
  /// still.
  double shown = 0;

  /// Time as the frame is drawn: zero when still.
  double t = 0;

  /// Rotation as drawn: zero when still.
  double drawRot = 0;

  /// Progress of the barge-in squash, 1 down to 0.
  double snap = 0;

  /// Opacity, from the still pulse and the muted and offline dimming.
  double alpha = 1;

  /// Ripple strength for the animated ripples, 0 to 1.
  double ripple = 0;

  Color speaking = Colors.transparent;

  void markDirty() => notifyListeners();

  /// Advances by [rawDt] seconds. Returns true when a still orb still has
  /// something to animate (a pulse, or outlines cross-fading).
  bool advance(
    double rawDt, {
    required VoiceOrbMode mode,
    required double? level,
    required bool still,
    required bool animateStill,
    required Color target,
    required Color speaking,
  }) {
    // A stall (a backgrounded app, a slow frame) must not make the orb leap.
    final dt = math.min(.05, math.max(0.0, rawDt));
    tRaw += dt;
    this.still = still;
    this.speaking = speaking;
    hold = level != null || still;

    var lvl = (level ?? 0).clamp(0.0, 1.0);
    if (level == null &&
        (mode == VoiceOrbMode.hearing || mode == VoiceOrbMode.speaking)) {
      lvl = .6;
    }

    var resolved = mode;
    snap = 0;
    if (mode == VoiceOrbMode.interrupted) {
      // The design loops speaking, then a barge-in that squashes the orb and
      // turns it to hearing. Still, it is the end of that moment.
      if (still) {
        resolved = VoiceOrbMode.hearing;
        lvl = .5;
      } else {
        final p = tRaw % 3.6;
        if (p < 1.4) {
          resolved = VoiceOrbMode.speaking;
        } else {
          resolved = VoiceOrbMode.hearing;
          snap = math.max(0, 1 - (p - 1.4) / .4);
        }
        lvl = math.max(lvl, .7);
      }
    }
    this.mode = resolved;
    t = still ? 0 : tRaw;

    // Colour: eased at six a second; a still orb takes it at once.
    final tr = target.r * 255;
    final tg = target.g * 255;
    final tb = target.b * 255;
    if (!_seeded || still) {
      r = tr;
      g = tg;
      b = tb;
      _seeded = true;
    } else {
      final k = math.min(1.0, dt * 6);
      r += (tr - r) * k;
      g += (tg - g) * k;
      b += (tb - b) * k;
    }

    // Level target by mode.
    var goal = 0.0;
    if (resolved == VoiceOrbMode.listening) {
      goal = hold ? 0 : .035 + .02 * math.sin(t * 5.3).abs();
    } else if (resolved == VoiceOrbMode.hearing ||
        resolved == VoiceOrbMode.speaking) {
      if (hold) {
        goal = lvl;
      } else {
        final gate =
            (math.sin(t * 1.7 + ph * 6) * (lvl > .5 ? 1.6 : 2.4) +
                    (lvl > .5 ? 1.1 : .55))
                .clamp(0.0, 1.0);
        goal =
            lvl *
            gate *
            (.4 + .6 * (math.sin(t * 9.7) * math.sin(t * 4.1 + 1)).abs());
      }
    }
    // Attack .06 s, release .28 s.
    eased += (goal - eased) * (1 - math.exp(-dt / (goal > eased ? .06 : .28)));
    shown = still ? goal : eased;
    if (still) eased = goal;
    if (!still) rot += dt;
    drawRot = still ? 0 : rot;

    // Opacity: the still pulse, then the dimming of muted and offline.
    var a = 1.0;
    final pulses = still && animateStill && _pulsing.contains(resolved);
    if (pulses) a = .86 + .14 * math.sin(tRaw * math.pi * 2 / 3.6);
    if (resolved == VoiceOrbMode.muted || resolved == VoiceOrbMode.offline) {
      a *= .7;
    }
    alpha = a;

    // Ripples. Animated: three rings drifting in or out. Still: one or two
    // dashed outlines by level band, cross-fading over 400 ms if allowed.
    final live =
        resolved == VoiceOrbMode.hearing || resolved == VoiceOrbMode.speaking;
    ripple = live && !still ? ((shown - .06) * 4).clamp(0.0, 1.0) : 0;
    if (ripple > 0) {
      ph +=
          dt *
          (resolved == VoiceOrbMode.hearing
              ? .6 + shown * 1.2
              : .5 + shown * .7);
    }
    final bands = still && resolved == VoiceOrbMode.hearing
        ? (shown < .3 ? 0 : (shown < .62 ? 1 : 2))
        : 0;
    var fading = false;
    for (var i = 0; i < presence.length; i++) {
      final want = bands > i ? 1.0 : 0.0;
      if (!animateStill) {
        presence[i] = want;
      } else {
        final step = dt / .4;
        final next = presence[i] < want
            ? math.min(want, presence[i] + step)
            : math.max(want, presence[i] - step);
        presence[i] = next;
        if (next != want) fading = true;
      }
    }
    return pulses || fading;
  }
}

class _VoiceOrbPainter extends CustomPainter {
  _VoiceOrbPainter({required this.frame, required this.requested})
    : super(repaint: frame);

  final _VoiceFrame frame;

  /// The mode the widget was given, which can be `interrupted` while the
  /// frame is drawing speaking or hearing.
  final VoiceOrbMode requested;

  static const _full = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final mode = f.mode;
    final still = f.still;
    final t = f.t;
    final level = f.shown;
    final rot = f.drawRot;
    final alpha = f.alpha;

    Color col(double a) => Color.fromRGBO(
      f.r.round().clamp(0, 255),
      f.g.round().clamp(0, 255),
      f.b.round().clamp(0, 255),
      (a * alpha).clamp(0.0, 1.0),
    );

    Paint line(double width, Color color, {bool round = true}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    void circle(double radius, Paint paint) =>
        canvas.drawCircle(c, radius, paint);

    void arc(double radius, double start, double sweep, Paint paint) =>
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          start,
          sweep,
          false,
          paint,
        );

    canvas.save();
    // The barge-in squash.
    final squash = 1 - .1 * f.snap;
    canvas
      ..translate(c.dx, c.dy)
      ..scale(squash)
      ..translate(-c.dx, -c.dy);

    var radius = s * _ringShare;
    final width = s * (.034 + .02 * level);
    if (mode == VoiceOrbMode.idle) {
      radius *= 1 + .025 * math.sin(t * _full / 4);
    }
    if (mode == VoiceOrbMode.listening) {
      radius *= 1 + .02 * math.sin(t * _full / 5);
    }
    radius *= 1 + _growthFor(mode) * level;
    final live = mode == VoiceOrbMode.hearing || mode == VoiceOrbMode.speaking;

    // Glow.
    final glowBase = switch (mode) {
      VoiceOrbMode.idle => .5,
      VoiceOrbMode.connecting => .6,
      VoiceOrbMode.listening => .6,
      VoiceOrbMode.hearing => .7,
      VoiceOrbMode.speaking => .75,
      VoiceOrbMode.thinking => .9,
      VoiceOrbMode.tool => .75,
      VoiceOrbMode.needs => .85,
      VoiceOrbMode.error => .6,
      VoiceOrbMode.muted || VoiceOrbMode.offline => 0.0,
      VoiceOrbMode.interrupted => .5,
    };
    final glow = glowBase + (live ? .5 * level : 0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          s * .5,
          [col(.32 * glow), col(.1 * glow), col(0)],
          [0, .5, 1],
        ),
    );

    // Speaking bloom.
    if (mode == VoiceOrbMode.speaking) {
      final bloom = radius * (.5 + .45 * level);
      circle(
        bloom,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            bloom,
            [col(.34 * (.4 + level)), col(.06)],
            [0, 1],
          ),
      );
    }

    // Ripples.
    if (live) {
      if (still) {
        if (mode == VoiceOrbMode.hearing) {
          for (var i = 0; i < f.presence.length; i++) {
            final p = f.presence[i];
            if (p <= 0) continue;
            _dashedCircle(
              canvas,
              c,
              radius * (1.2 + i * .2),
              line(width * .6, col((.5 - i * .15) * p), round: false),
              dash: s * .012,
              gap: s * .02,
            );
          }
        }
      } else if (f.ripple > 0) {
        for (var i = 0; i < 3; i++) {
          final phase = (f.ph + i / 3) % 1;
          final rr = mode == VoiceOrbMode.hearing
              ? radius * (1.6 - .6 * phase)
              : radius * (1 + .6 * phase);
          final al =
              (mode == VoiceOrbMode.hearing
                  ? math.sin(math.pi * phase)
                  : 1 - phase) *
              .55 *
              f.ripple *
              math.min(1.0, level * 2 + .3);
          circle(rr, line(width * .55, col(al), round: false));
        }
      }
    }

    // The squash's flash, and the moment of interruption.
    if (f.snap > 0) {
      circle(
        radius * (1.5 - .5 * (1 - f.snap)),
        line(
          width * (1 + f.snap),
          Colors.white.withValues(alpha: f.snap * .7),
          round: false,
        ),
      );
    }
    if (requested == VoiceOrbMode.interrupted && still) {
      final tone = f.speaking;
      circle(
        radius * 1.28,
        line(width * .7, tone.withValues(alpha: .3), round: false),
      );
      circle(
        radius * 1.28,
        line(width * .7, tone.withValues(alpha: .35), round: false),
      );
    }

    // The ring, by mode.
    void arcs(int n, double lengthShare, double spin, double track) {
      if (track > 0) circle(radius, line(width, col(track)));
      final slot = _full / n;
      final paint = line(width * 1.15, col(1));
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + spin + i * slot;
        arc(radius, a, slot * lengthShare, paint);
      }
    }

    var pulse = 0.0;
    var satellite = false;
    switch (mode) {
      case VoiceOrbMode.thinking:
        arcs(3, .7, rot * _full * .4, .12);
        pulse = .2 * math.sin(t * _full * 1.6);
      case VoiceOrbMode.tool:
        arcs(6, .62, rot * 1.3, .1);
        satellite = true;
        pulse = .1 * math.sin(t * _full * 1.2);
      case VoiceOrbMode.connecting:
        circle(radius, line(width, col(.14)));
        arc(
          radius,
          -math.pi / 2 + rot * 5.2,
          _full * .3,
          line(width * 1.3, col(1)),
        );
      case VoiceOrbMode.needs:
        arcs(2, .78, rot * .35, .1);
        pulse = .14 * math.sin(t * _full * .9);
      case VoiceOrbMode.offline:
        arcs(12, .55, rot * .1, 0);
        pulse = .08 * math.sin(t * _full * .5);
      case VoiceOrbMode.error:
        // A short shake at the start of every four seconds.
        final shake = still ? 0.0 : math.max(0.0, 1 - (f.tRaw % 4) / .3);
        canvas.translate(math.sin(f.tRaw * 55) * shake * shake * s * .04, 0);
        circle(radius, line(width, col(.1)));
        arc(
          radius,
          -math.pi / 2 + _full * .08,
          _full * .84,
          line(width * 1.2, col(1)),
        );
      case VoiceOrbMode.idle ||
          VoiceOrbMode.listening ||
          VoiceOrbMode.hearing ||
          VoiceOrbMode.speaking ||
          VoiceOrbMode.muted ||
          VoiceOrbMode.interrupted:
        // A closed ring whose edge is deformed by the level.
        const points = 110;
        final path = Path();
        for (var i = 0; i <= points; i++) {
          final a = i / points * _full;
          var df = 0.0;
          if (still) {
            df = 0;
          } else if (mode == VoiceOrbMode.hearing) {
            df =
                level *
                (.12 *
                        math.sin(5 * a + rot * 1.7 + t * 2.3) *
                        math.sin(3 * a - t * 1.9) +
                    .055 * math.sin(9 * a - t * 4.1 + f.ph * 6) +
                    .02 * math.sin(2 * a + t * 3));
          } else if (mode == VoiceOrbMode.listening) {
            df =
                .012 * math.sin(4 * a + t * 1.6) +
                (f.hold ? 0 : f.eased * .3 * math.sin(7 * a + t * 5));
          } else if (mode == VoiceOrbMode.speaking) {
            df = .012 * level * math.sin(3 * a + t * 2);
          }
          final rr = radius * (1 + df);
          final x = c.dx + math.cos(a) * rr;
          final y = c.dy + math.sin(a) * rr;
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        final muted = mode == VoiceOrbMode.muted;
        final ring = line(width * (muted ? .8 : 1.1), col(muted ? .8 : 1));
        canvas.drawPath(path, ring);
        if (muted) {
          final slash = line(width * .9, col(.8));
          canvas.drawLine(
            Offset(c.dx - radius * .72, c.dy - radius * .72),
            Offset(c.dx + radius * .72, c.dy + radius * .72),
            slash,
          );
        }
    }

    if (satellite) {
      final a = still ? -.8 : rot * 1.9;
      final orbit = radius + width * 2.4;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * orbit,
        width * .75,
        Paint()..color = col(1),
      );
    }

    // The core, lit from the upper left.
    final coreShare = switch (mode) {
      VoiceOrbMode.idle => .12 + .006 * math.sin(t * _full / 4),
      VoiceOrbMode.listening => .125,
      VoiceOrbMode.hearing => .125 + .045 * level,
      VoiceOrbMode.speaking => .13 + .07 * level,
      VoiceOrbMode.thinking => .115,
      VoiceOrbMode.tool => .125,
      VoiceOrbMode.connecting => .1,
      VoiceOrbMode.needs => .125,
      VoiceOrbMode.muted => .1,
      VoiceOrbMode.error => .12,
      VoiceOrbMode.offline => .1,
      VoiceOrbMode.interrupted => .12,
    };
    final core =
        s *
        coreShare *
        (1 +
            pulse +
            (mode == VoiceOrbMode.listening
                ? .04 * math.sin(t * _full * 1.1)
                : 0));
    final dim = mode == VoiceOrbMode.muted || mode == VoiceOrbMode.offline
        ? .6
        : 1.0;
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          core,
          [
            Colors.white.withValues(alpha: (.95 * dim * alpha).clamp(0.0, 1.0)),
            col(1),
            col(.85),
          ],
          [0, .35, 1],
          ui.TileMode.clamp,
          null,
          Offset(c.dx - core * .3, c.dy - core * .35),
          core * .1,
        ),
    );

    canvas.restore();
  }

  /// A circle drawn as dashes, since Flutter strokes have no dash pattern.
  static void _dashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    if (radius <= 0 || dash <= 0) return;
    final step = (dash + gap) / radius;
    final sweep = dash / radius;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var a = 0.0; a < _full - 1e-6; a += step) {
      canvas.drawArc(rect, a, math.min(sweep, _full - a), false, paint);
    }
  }

  @override
  bool shouldRepaint(_VoiceOrbPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.requested != requested;
}
