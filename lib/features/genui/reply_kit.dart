/// Reply kits (plan 4.4): a display the assistant marked `placement: "reply_kit"`, docked above the composer so a
/// decision or a few choices are one tap away instead of scrolled past in the transcript.
///
/// One kit at a time: the newest one, and only while nothing the person said comes after it. The screen also hides it
/// while a reply is running, once the person types, and after they tap something that sends a message or dismiss it.
library;

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../data/genui/genui_models.dart';
import '../../data/genui/genui_parser.dart';
import '../../data/genui/signals.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'render/node_builder.dart';
import 'surface_block.dart';

/// The kit to dock for a conversation: the newest reply kit in [items], unless the person has said something since.
UiSurfaceItem? currentReplyKit(List<TranscriptItem> items) {
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (item is UserTurn) return null;
    if (item is UiSurfaceItem &&
        item.ref.placement == SurfacePlacement.replyKit) {
      return item;
    }
  }
  return null;
}

/// Tells one kit, at one revision, from another: a dismissed kit stays dismissed until the assistant updates it.
String replyKitKey(UiSurfaceItem item) =>
    '${item.ref.surfaceId}@${item.ref.rev ?? 0}';

/// The most a kit may take before "Show all": enough for a question's choices, never the whole conversation.
const double kReplyKitMaxHeight = 200;

class ReplyKitDock extends StatelessWidget {
  const ReplyKitDock({
    required this.item,
    required this.onDismiss,
    this.loadSurface,
    this.onUiAction,
    this.onSignal,
    this.onOpenUrl,
    super.key,
  });

  final UiSurfaceItem item;
  final VoidCallback onDismiss;
  final SurfaceLoader? loadSurface;

  /// A tap that asks the assistant something. The kit goes once it has been sent.
  final void Function(String text, IrisActionEnvelope action)? onUiAction;
  final ValueChanged<String>? onOpenUrl;

  /// Reports that the kit was seen or closed without being used.
  final SignalSink? onSignal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      // Without this the buttons would merge into the group's one node and a screen reader could not reach them.
      explicitChildNodes: true,
      label: 'Suggested replies',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.all(IrisRadius.md),
          border: Border.all(color: palette.line, width: IrisStroke.hairline),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IrisSpace.md,
                IrisSpace.md,
                IrisSpace.xxl + IrisSpace.sm,
                IrisSpace.md,
              ),
              child: SurfaceBlock(
                item,
                docked: true,
                maxHeight: kReplyKitMaxHeight,
                loadSurface: loadSurface,
                env: NodeEnv(onOpenUrl: onOpenUrl),
                onSignal: onSignal,
                onUiAction: (text, action) {
                  onUiAction?.call(text, action);
                  onDismiss();
                },
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IrisPressable(
                onTap: () {
                  onSignal?.call(
                    DisplaySignal.dismissed,
                    surface: item.ref.surfaceId,
                    template: item.ref.template,
                  );
                  onDismiss();
                },
                semanticLabel: 'Dismiss suggested replies',
                child: Padding(
                  padding: const EdgeInsets.all(IrisSpace.sm),
                  child: Icon(
                    Icons.close,
                    size: IrisSize.iconSmall,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
