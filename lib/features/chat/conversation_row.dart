/// One row of a conversation list, and the way one leaves it.
library;

import 'package:flutter/material.dart';

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
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Opens the row's actions.
  final VoidCallback? onLongPress;

  /// Replaces the chevron, such as an Unarchive button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      ensureTapTarget: false,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
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
              child: const IrisOrb(
                state: AgentState.rest,
                size: 30,
                glow: false,
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
                ],
              ),
            ),
            const SizedBox(width: IrisSpace.sm),
            trailing ??
                Icon(Icons.chevron_right, size: 16, color: palette.lineStrong),
          ],
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
