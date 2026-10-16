/// Where a branched chat came from: a line under the title, and a divider at
/// the point the copy ended and the new chat began.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

/// "Branched from ‹parent›", tappable. At least 44 high, inset to clear the back
/// button and orb.
class BranchedHeader extends StatelessWidget {
  const BranchedHeader({
    required this.parentTitle,
    required this.onOpen,
    super.key,
  });

  final String parentTitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onOpen,
      ensureTapTarget: false,
      semanticLabel: 'Branched from $parentTitle. Open it',
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        margin: const EdgeInsets.fromLTRB(64, 0, IrisSpace.lg, IrisSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.call_split, size: 16, color: palette.accent),
            const SizedBox(width: IrisSpace.sm),
            Flexible(
              child: Text.rich(
                TextSpan(
                  style: type.codeSmall.copyWith(
                    fontSize: 11.5,
                    color: palette.inkMuted,
                  ),
                  children: [
                    const TextSpan(text: 'Branched from '),
                    TextSpan(
                      text: parentTitle,
                      style: TextStyle(color: palette.ink),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mono divider: `BRANCHED HERE · 14:02`.
class BranchedDivider extends StatelessWidget {
  const BranchedDivider({required this.at, this.known = true, super.key});

  final DateTime at;

  /// Whether [at] is a real time; a record from before the time was kept
  /// has none, and the divider just says where.
  final bool known;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    String two(int n) => n.toString().padLeft(2, '0');
    return Row(
      children: [
        Expanded(
          child: Container(height: IrisStroke.hairline, color: palette.line),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IrisSpace.md),
          child: IrisLabel(
            known
                ? 'Branched here · ${two(at.hour)}:${two(at.minute)}'
                : 'Branched here',
            small: true,
          ),
        ),
        Expanded(
          child: Container(height: IrisStroke.hairline, color: palette.line),
        ),
      ],
    );
  }
}

/// Shows "Branching…" over everything while [work] runs, then closes. The
/// orb is in the connecting state, as the design shows.
Future<T> withBranchingOverlay<T>(
  BuildContext context,
  String title,
  Future<T> work,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showGeneralDialog<void>(
      context: context,
      barrierColor: context.palette.surfaceSunken.withValues(alpha: .86),
      pageBuilder: (_, _, _) => PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IrisOrb(state: AgentState.loading, size: 72),
              const SizedBox(height: IrisSpace.lg),
              Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    IrisLabel(
                      'Branching…',
                      color: context.palette.colorFor(AgentState.loading),
                    ),
                    const SizedBox(height: IrisSpace.xs),
                    SizedBox(
                      width: 260,
                      child: Text(
                        'Copying ‘$title’ into a new chat. It opens as soon as Hermes has it.',
                        textAlign: TextAlign.center,
                        style: context.type.body.copyWith(
                          color: context.palette.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    if (navigator.canPop()) navigator.pop();
  }
}
