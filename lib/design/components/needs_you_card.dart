/// The card every prompt that needs the person shares: the password
/// manager's unlock, code and save-login, sudo, and secrets.
///
/// One card, so the whole family reads as one thing: the needs-you colour
/// at 45% on the border, a mono eyebrow, the orb in the needs-you state. Once
/// answered, skipped or withdrawn it collapses to a [SettledLine] that never
/// shows what was typed.
library;

import 'package:flutter/material.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/palette.dart';
import 'dashed_border.dart';
import 'iris_orb.dart';
import 'primitives.dart';

class NeedsYouCard extends StatelessWidget {
  const NeedsYouCard({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    super.key,
  });

  /// Mono caps above the title, such as `Needs you · unlock`.
  final String eyebrow;
  final String title;
  final String? subtitle;

  /// The fields.
  final Widget child;

  /// The buttons, pinned under the fields.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final needs = palette.colorFor(AgentState.waiting);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: needs.withValues(alpha: .45),
          width: IrisStroke.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IrisOrb(state: AgentState.waiting, size: 28),
                const SizedBox(width: IrisSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IrisLabel(eyebrow, color: needs, small: true),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: type.body.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: palette.ink,
                        ),
                      ),
                      if (subtitle case final text?) ...[
                        const SizedBox(height: 2),
                        Text(
                          text,
                          style: type.body.copyWith(
                            fontSize: 13.5,
                            color: palette.inkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
            if (actions case final buttons?) ...[
              const SizedBox(height: 14),
              buttons,
            ],
          ],
        ),
      ),
    );
  }
}

enum SettledOutcome { answered, skipped, expired }

/// What is left of a [NeedsYouCard] once it is over: one 56-high line. It
/// carries the title and a short detail ("answered · 14:02"), never a value.
class SettledLine extends StatelessWidget {
  const SettledLine({
    required this.title,
    required this.outcome,
    this.detail = '',
    super.key,
  });

  final String title;
  final SettledOutcome outcome;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final tint = switch (outcome) {
      SettledOutcome.answered => palette.colorFor(AgentState.done),
      SettledOutcome.skipped => palette.colorFor(AgentState.rest),
      SettledOutcome.expired => palette.inkMuted,
    };
    final icon = switch (outcome) {
      SettledOutcome.answered => Icons.check,
      SettledOutcome.skipped => Icons.remove,
      SettledOutcome.expired => Icons.hourglass_empty,
    };
    final decoration = BoxDecoration(
      color: outcome == SettledOutcome.expired
          ? null
          : tint.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      border: outcome == SettledOutcome.expired
          ? null
          : Border.all(
              color: tint.withValues(alpha: .25),
              width: IrisStroke.hairline,
            ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: IrisSpace.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.body.copyWith(fontSize: 14, color: palette.ink),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.codeSmall.copyWith(
                      fontSize: 11,
                      color: palette.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: [title, if (detail.isNotEmpty) detail].join(', '),
      excludeSemantics: true,
      child: outcome == SettledOutcome.expired
          ? CustomPaint(
              painter: DashedRRectPainter(
                color: palette.lineStrong,
                radius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Align(alignment: Alignment.centerLeft, child: row),
              ),
            )
          : DecoratedBox(
              decoration: decoration,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Align(alignment: Alignment.centerLeft, child: row),
              ),
            ),
    );
  }
}

/// Skip on the left, the main action on the right at twice the width, both
/// 48 high (frame A7).
class NeedsYouActions extends StatelessWidget {
  const NeedsYouActions({
    required this.skipLabel,
    required this.primaryLabel,
    this.onSkip,
    this.onPrimary,
    this.busy = false,
    super.key,
  });

  final String skipLabel;
  final String primaryLabel;
  final VoidCallback? onSkip;

  /// Null disables the main action.
  final VoidCallback? onPrimary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final needs = palette.colorFor(AgentState.waiting);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: skipLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onSkip,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.lineStrong,
                    width: IrisStroke.hairline,
                  ),
                ),
                child: Text(
                  skipLabel,
                  style: type.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: IrisSpace.sm),
        Expanded(
          flex: 2,
          child: Semantics(
            button: true,
            enabled: onPrimary != null && !busy,
            label: primaryLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onPrimary,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: onPrimary == null ? palette.lineStrong : needs,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  primaryLabel,
                  style: type.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: onPrimary == null
                        ? palette.inkMuted
                        : palette.accentInk,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
