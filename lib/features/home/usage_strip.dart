/// How much of each chosen provider's subscription is used, under the hero.
///
/// Ambient: it never shows an error and never a spinner. It is hidden until
/// there is something to show, then grows in, because a skeleton for a strip
/// that may turn out to be empty would flash for nothing.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/usage.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';
import '../chat/relative_time.dart';

class UsageStrip extends ConsumerWidget {
  const UsageStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(providerUsageProvider).value ?? const <UsageRow>[];
    final now = ref.read(clockProvider)();
    final gutter = context.window.gutter;
    return IrisAnimatedSize(
      child: rows.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.sm),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: const BorderRadius.all(IrisRadius.md),
                  border: Border.all(
                    color: context.palette.line,
                    width: IrisStroke.hairline,
                  ),
                ),
                child: Column(
                  children: [
                    for (final (index, row) in rows.indexed) ...[
                      if (index > 0) const IrisDivider(),
                      _ProviderRow(key: ValueKey(row.slug), row: row, now: now),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// Meters are the accent; they turn needs-you only when the person has to
/// act, from 85% used.
Color _meterTint(IrisPalette palette, double usedPercent) =>
    usedPercent >= 85 ? palette.colorFor(AgentState.waiting) : palette.accent;

/// "73% used · resets in 2h 36m": what is used, and when it comes back.
String _caption(UsageWindow window, DateTime now) {
  final used = '${window.usedPercent.round()}% used';
  final reset = window.resetsAt;
  return reset == null ? used : '$used · resets ${timeUntil(reset, now)}';
}

class _ProviderRow extends StatefulWidget {
  const _ProviderRow({required this.row, required this.now, super.key});

  final UsageRow row;
  final DateTime now;

  @override
  State<_ProviderRow> createState() => _ProviderRowState();
}

class _ProviderRowState extends State<_ProviderRow>
    with SingleTickerProviderStateMixin {
  bool _open = false;

  /// Drives the windows' staggered arrival when the row opens.
  late final AnimationController _stagger;

  @override
  void initState() {
    super.initState();
    _stagger = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  void _toggle() {
    unawaited(IrisHaptics.selection());
    setState(() => _open = !_open);
    if (!_open) return;
    if (context.reduceMotion) {
      _stagger.value = 1;
    } else {
      _stagger.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  /// Each detail line fades and rises in a little after the one before it.
  Widget _staggered(int index, Widget child) {
    final start = (index * 0.08).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: _stagger,
      curve: Interval(
        start,
        (start + 0.4).clamp(0.0, 1.0),
        curve: IrisCurves.standard,
      ),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .3),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final usage = widget.row.usage;
    final tightest = usage.tightest;
    final details = <Widget>[
      for (final window in usage.windows)
        _WindowLine(window: window, now: widget.now),
      for (final account in usage.accounts) ...[
        _AccountHeader(account: account),
        for (final window in account.windows)
          _WindowLine(window: window, now: widget.now),
      ],
    ];
    // Placed in whichever header layout the text size calls for.
    final chevron = SpringBuilder(
      value: _open ? .5 : 0,
      spring: IrisSprings.snappy,
      builder: (context, turns, child) =>
          Transform.rotate(angle: turns * 2 * math.pi, child: child),
      child: Icon(Icons.keyboard_arrow_down, size: 16, color: palette.inkMuted),
    );
    return IrisPressable(
      onTap: _toggle,
      semanticLabel:
          '${widget.row.name} usage, ${_open ? 'collapse' : 'expand'}',
      child: Padding(
        padding: const EdgeInsets.all(IrisSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // At a large text size the name and the figure each take a line
            // rather than squeezing the name to one letter.
            if (MediaQuery.textScalerOf(context).scale(14) > 21)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: IrisSpace.xs,
                children: [
                  Text(
                    widget.row.name,
                    style: type.body.copyWith(fontSize: 14, color: palette.ink),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tightest != null)
                        Flexible(
                          child: _UsedCaption(
                            window: tightest,
                            now: widget.now,
                          ),
                        ),
                      const SizedBox(width: IrisSpace.xs),
                      chevron,
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.row.name,
                      style: type.body.copyWith(
                        fontSize: 14,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  if (tightest != null)
                    _UsedCaption(window: tightest, now: widget.now),
                  const SizedBox(width: IrisSpace.xs),
                  chevron,
                ],
              ),
            if (tightest != null) ...[
              const SizedBox(height: IrisSpace.sm),
              IrisGauge(
                value: tightest.usedPercent / 100,
                width: null,
                tint: _meterTint(palette, tightest.usedPercent),
              ),
            ],
            IrisAnimatedSize(
              child: _open && details.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: IrisSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, line) in details.indexed)
                            _staggered(i, line),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// The used figure in ink and medium weight, the reset after it muted.
class _UsedCaption extends StatelessWidget {
  const _UsedCaption({required this.window, required this.now});

  final UsageWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final reset = window.resetsAt;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${window.usedPercent.round()}% used',
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w500),
          ),
          if (reset != null)
            TextSpan(
              text: ' · resets ${timeUntil(reset, now)}',
              style: window.usedPercent >= 85
                  ? TextStyle(color: palette.colorFor(AgentState.waiting))
                  : null,
            ),
        ],
      ),
      style: type.caption.copyWith(color: palette.inkMuted),
    );
  }
}

class _WindowLine extends StatelessWidget {
  const _WindowLine({required this.window, required this.now});

  final UsageWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: IrisSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  window.label,
                  style: type.caption.copyWith(color: palette.ink),
                ),
              ),
              Text(
                _caption(window, now),
                style: type.caption.copyWith(
                  color: window.usedPercent >= 85
                      ? palette.colorFor(AgentState.waiting)
                      : palette.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: IrisSpace.xs),
          IrisGauge(
            value: window.usedPercent / 100,
            width: null,
            tint: _meterTint(palette, window.usedPercent),
          ),
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});

  final UsageAccount account;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (label, state) = switch (account.state) {
      UsageAccountState.ready => (null, AgentState.done),
      UsageAccountState.limited => ('Limited', AgentState.waiting),
      UsageAccountState.unavailable => ('Unavailable', AgentState.failed),
      UsageAccountState.unknown => ('Unknown', AgentState.rest),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IrisSpace.xs),
      child: Row(
        children: [
          Expanded(child: IrisLabel(account.label, color: palette.inkMuted)),
          if (label != null) IrisChip.state(label, state, palette),
        ],
      ),
    );
  }
}
