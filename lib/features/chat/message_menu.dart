/// The menu that opens on a long-press of a message: Copy, Select text,
/// Branch from here, Undo.
///
/// The pressed message is spotlit: a scrim covers everything but a hole
/// around it, so the message stays crisp and the menu sits right beside it.
/// The menu opens below the message, or above it when it would reach the
/// composer.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/components/sheet.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

enum MessageAction {
  copy('Copy', Icons.copy_outlined),
  select('Select text', Icons.text_fields),
  branch('Branch from here', Icons.call_split),
  undo('Undo', Icons.undo);

  const MessageAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The chosen action, or null when the menu was dismissed.
Future<MessageAction?> showMessageMenu(
  BuildContext context, {
  required Rect anchor,
  required bool alignEnd,
  required List<MessageAction> actions,
}) {
  unawaited(IrisHaptics.selection());
  return showGeneralDialog<MessageAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: const Color(0x00000000),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) =>
        _MenuPage(anchor: anchor, alignEnd: alignEnd, actions: actions),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _MenuPage extends StatelessWidget {
  const _MenuPage({
    required this.anchor,
    required this.alignEnd,
    required this.actions,
  });

  final Rect anchor;
  final bool alignEnd;
  final List<MessageAction> actions;

  static const _width = 220.0;
  static const _rowHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final size = MediaQuery.sizeOf(context);
    final height = actions.length * _rowHeight;
    // The composer and keyboard take the bottom of the screen.
    final limit = size.height - MediaQuery.viewInsetsOf(context).bottom - 160;
    final below = anchor.bottom + 8;
    final top = below + height > limit
        ? (anchor.top - 8 - height).clamp(
            MediaQuery.paddingOf(context).top,
            limit,
          )
        : below;
    final left = alignEnd
        ? (anchor.right - _width).clamp(
            IrisSpace.lg,
            size.width - _width - IrisSpace.lg,
          )
        : anchor.left.clamp(IrisSpace.lg, size.width - _width - IrisSpace.lg);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: CustomPaint(
                painter: _Spotlight(
                  hole: anchor.inflate(4),
                  scrim: palette.surfaceSunken.withValues(alpha: .72),
                  edge: palette.lineStrong,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: palette.lineStrong,
                  width: IrisStroke.hairline,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions)
                    InkWell(
                      onTap: () => Navigator.of(context).pop(action),
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: _rowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(action.icon, size: 18, color: palette.ink),
                              const SizedBox(width: IrisSpace.md),
                              Flexible(
                                child: Text(
                                  action.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.body.copyWith(
                                    fontSize: 15,
                                    color: palette.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A scrim with a rounded hole around the pressed message.
class _Spotlight extends CustomPainter {
  const _Spotlight({
    required this.hole,
    required this.scrim,
    required this.edge,
  });

  final Rect hole;
  final Color scrim;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(18));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas
      ..drawPath(path, Paint()..color = scrim)
      ..drawRRect(
        rrect,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_Spotlight old) => old.hole != hole || old.scrim != scrim;
}

/// Shows the full text in a sheet where it can be selected, for the "Select
/// text" action. The transcript itself is not selectable, because a
/// long-press has to open this menu.
Future<void> showSelectableText(BuildContext context, String text) =>
    showIrisSheet<void>(
      context: context,
      builder: (_) => IrisSheet(
        title: 'Select text',
        child: SelectableText(text, style: context.type.body),
      ),
    );
