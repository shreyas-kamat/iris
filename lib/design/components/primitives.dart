/// The primitives every screen is built from.
library;

import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';

/// The interface speaking in its own voice: small, mono, uppercase, tracked.
///
/// Used for section headings, tool names, status words, field labels — anything
/// the app says *about* the conversation rather than as part of it. The
/// uppercasing happens at render time so the semantic string stays sentence
/// case for screen readers, which would otherwise spell out short labels letter
/// by letter.
class IrisLabel extends StatelessWidget {
  const IrisLabel(this.text, {this.color, this.small = false, super.key});

  final String text;
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Text(
        text.toUpperCase(),
        // Labels are already near the floor of legible size, so they scale with
        // the user's setting like everything else - but only to a point. Tracked
        // uppercase mono grows wider much faster than it grows taller, and past
        // about 1.6x a two-word label wraps mid-word and stops being a label.
        // Above that the size is capped and the space goes to the content the
        // label is naming, which is what the person actually came to read.
        textScaler: TextScaler.linear(
          MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
        ),
        style: (small ? type.labelSmall : type.label).copyWith(
          color: color ?? context.palette.inkMuted,
        ),
      ),
    );
  }
}

/// A hairline.
///
/// Sub-pixel by default so it reads as a seam between surfaces rather than a
/// drawn rule — the difference between a layout that feels assembled and one
/// that feels ruled.
class IrisDivider extends StatelessWidget {
  const IrisDivider({this.indent = 0, this.vertical = false, super.key});

  final double indent;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final line = context.palette.line;
    if (vertical) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: indent),
        child: SizedBox(
          width: IrisStroke.hairline,
          child: ColoredBox(color: line),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: SizedBox(
        height: IrisStroke.hairline,
        child: ColoredBox(color: line),
      ),
    );
  }
}

/// A surface on one of the three planes.
class IrisCard extends StatelessWidget {
  const IrisCard({
    required this.child,
    this.plane = IrisPlane.raised,
    this.padding = const EdgeInsets.all(IrisSpace.md),
    this.radius = IrisRadius.md,
    this.accent,
    super.key,
  });

  final Widget child;
  final IrisPlane plane;
  final EdgeInsetsGeometry padding;
  final Radius radius;

  /// Tints the border and adds a leading edge, for cards that carry state —
  /// a failed tool call, a blocked approval.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final depth = theme.depth(plane);
    final surface = switch (plane) {
      IrisPlane.ground => theme.palette.canvas,
      IrisPlane.raised => theme.palette.surface,
      IrisPlane.overlay => theme.palette.surfaceRaised,
    };
    final borderColor = accent ?? depth.border;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.all(radius),
        boxShadow: depth.shadows,
        border: borderColor == null
            ? null
            : Border.all(
                color: accent == null
                    ? borderColor
                    : borderColor.withValues(alpha: 0.45),
                width: IrisStroke.hairline,
              ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A small piece of status: a tool name, a tag, a model.
class IrisChip extends StatelessWidget {
  const IrisChip(
    this.text, {
    this.color,
    this.background,
    this.leading,
    this.onTap,
    super.key,
  });

  /// A chip in the colour of an agent state.
  factory IrisChip.state(
    String text,
    AgentState state,
    IrisPalette palette, {
    Widget? leading,
    Key? key,
  }) => IrisChip(
    text,
    key: key,
    color: palette.colorFor(state),
    background: palette.quietFor(state),
    leading: leading,
  );

  final String text;
  final Color? color;
  final Color? background;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = color ?? palette.inkMuted;
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? palette.surfaceSunken,
        borderRadius: const BorderRadius.all(IrisRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IrisSpace.sm,
          vertical: IrisSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading case final leading?) ...[
              leading,
              const SizedBox(width: IrisSpace.xs),
            ],
            IrisLabel(text, color: foreground, small: true),
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    return IrisPressable(onTap: onTap, child: chip);
  }
}

/// Adds a spring-driven press response to anything tappable.
///
/// The scale is deliberately small — a 2% dip. Large press animations read as
/// playful, and the things being pressed here include "allow this command to
/// delete files". It should feel responsive, not fun.
class IrisPressable extends StatefulWidget {
  const IrisPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.98,
    this.semanticLabel,
    this.ensureTapTarget = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  /// Reserves at least [IrisSize.minTapTarget] in both axes around [child].
  ///
  /// On by default, because the thing most likely to be too small is the thing
  /// nobody measured. A chip is visually 24pt tall; leaving its hit area at 24pt
  /// makes it a coin-flip to tap on a moving train, and every platform's
  /// guidelines put the floor at 44-48.
  ///
  /// Turn it off only where the child already guarantees the size itself, so the
  /// constraint does not add padding a second time.
  final bool ensureTapTarget;

  @override
  State<IrisPressable> createState() => _IrisPressableState();
}

class _IrisPressableState extends State<IrisPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;

    Widget content = SpringBuilder(
      value: _down && enabled ? widget.scale : 1.0,
      spring: IrisSprings.snappy,
      child: widget.child,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
    );

    if (widget.ensureTapTarget && enabled) {
      // The visual child keeps its own size; the constraint only grows the box
      // around it, so the extra area is transparent and reachable without
      // changing how the component looks.
      content = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: IrisSize.minTapTarget,
          minHeight: IrisSize.minTapTarget,
        ),
        child: Center(widthFactor: 1, heightFactor: 1, child: content),
      );
    }

    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: content,
      ),
    );
  }
}

/// A loading placeholder.
///
/// A slow shimmer rather than a spinner, because these appear in lists where
/// several would be on screen at once and a field of spinners is agitating.
/// The shimmer is also honest about shape: it occupies the space the real
/// content will, so nothing jumps when it arrives.
class IrisSkeleton extends StatefulWidget {
  const IrisSkeleton({
    this.width,
    this.height = 14,
    this.radius = IrisRadius.xs,
    super.key,
  });

  final double? width;
  final double height;
  final Radius radius;

  @override
  State<IrisSkeleton> createState() => _IrisSkeletonState();
}

class _IrisSkeletonState extends State<IrisSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            // Lerps toward lineStrong, not line: on a dark skin the gap
            // between sunken and line is a couple of percent of lightness and
            // the placeholder disappears entirely. It has to read as an object
            // occupying space, or it is not doing its job.
            color: Color.lerp(
              palette.line,
              palette.lineStrong,
              0.15 + 0.7 * _controller.value,
            ),
            borderRadius: BorderRadius.all(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// What a screen shows when there is nothing to show.
///
/// Every empty state names an action. "No sessions yet" describes a void;
/// "Start a conversation" offers a way out of it — and an empty screen is the
/// moment a person is most likely to leave.
class IrisEmptyState extends StatelessWidget {
  const IrisEmptyState({
    required this.title,
    required this.message,
    this.action,
    this.icon,
    super.key,
  });

  final String title;
  final String message;
  final Widget? action;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IrisSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?) ...[
              icon,
              const SizedBox(height: IrisSpace.lg),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.typography.display.copyWith(
                color: theme.palette.ink,
              ),
            ),
            const SizedBox(height: IrisSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.typography.body.copyWith(
                color: theme.palette.inkMuted,
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: IrisSpace.xl),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
