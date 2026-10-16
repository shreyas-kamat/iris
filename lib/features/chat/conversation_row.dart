/// One row of a conversation list, and the way one leaves it.
library;

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';

/// One conversation: a tile holding the resting orb, the title and its
/// metadata. Rows carry no fill at rest, so the list reads as text on the page.
class ConversationRow extends StatelessWidget {
  const ConversationRow({
    required this.title,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.pinned = false,
    this.lifted = false,
    this.live,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Opens the row's actions.
  final VoidCallback? onLongPress;

  /// Replaces the chevron, such as an Unarchive button.
  final Widget? trailing;

  /// A pin mark trails the row.
  final bool pinned;

  /// The row is held under its action sheet: raised, with a stronger edge.
  final bool lifted;

  /// The chat is replying: a state chip joins the meta line.
  final LiveStatus? live;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      ensureTapTarget: false,
      semanticLabel: title,
      child: AnimatedScale(
        scale: lifted ? 1.015 : 1,
        duration: context.reduceMotion ? Duration.zero : IrisDurations.quick,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: lifted
              ? BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: palette.lineStrong,
                    width: IrisStroke.hairline,
                  ),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surfaceSunken,
                  borderRadius: const BorderRadius.all(IrisRadius.md),
                ),
                child: IrisOrb(
                  state: live == null
                      ? AgentState.rest
                      : (live!.waiting
                            ? AgentState.waiting
                            : AgentState.thinking),
                  size: 30,
                  glow: live != null,
                ),
              ),
              const SizedBox(width: IrisSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(
                        fontSize: 14,
                        height: 1.25,
                        color: palette.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: IrisSpace.xs - 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.codeSmall.copyWith(
                          fontSize: 11,
                          color: palette.inkFaint,
                        ),
                      ),
                    ],
                    if (live case final status?) ...[
                      const SizedBox(height: IrisSpace.xs),
                      IrisChip.state(
                        status.waiting ? 'Needs you' : 'Replying',
                        status.waiting
                            ? AgentState.waiting
                            : AgentState.thinking,
                        palette,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: IrisSpace.sm),
              trailing ??
                  (pinned
                      ? Icon(
                          Icons.push_pin_outlined,
                          size: 14,
                          color: palette.inkMuted,
                        )
                      : Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: palette.lineStrong,
                        )),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row that slides out to the leading edge and folds its height when
/// [gone], and springs back when it is not, as it does when an archive is
/// undone. Kept in the tree while gone, so the undo has something to spring.
class Leaving extends StatelessWidget {
  const Leaving({required this.gone, required this.child, super.key});

  final bool gone;
  final Widget child;

  @override
  Widget build(BuildContext context) => SpringBuilder(
    value: gone ? 0 : 1,
    builder: (context, t, child) {
      final shown = t.clamp(0.0, 1.0);
      if (shown == 0) return const SizedBox(width: double.infinity);
      return ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: shown,
          child: Opacity(
            opacity: shown,
            child: Transform.translate(
              offset: Offset(-(1 - shown) * 48, 0),
              child: child,
            ),
          ),
        ),
      );
    },
    child: child,
  );
}
