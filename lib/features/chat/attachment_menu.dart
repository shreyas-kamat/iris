/// The menu behind the composer's "+" (frame B8): Photos and Files, and the
/// limits in a mono footnote. Anchored above the button it opens from.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/attachment.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'attachment_picker.dart';

Future<AttachSource?> showAttachMenu(
  BuildContext context, {
  required Rect anchor,
}) {
  unawaited(IrisHaptics.selection());
  return showGeneralDialog<AttachSource>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: const Color(0x00000000),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) => _AttachMenu(anchor: anchor),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _AttachMenu extends StatelessWidget {
  const _AttachMenu({required this.anchor});

  final Rect anchor;

  static const _width = 240.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final size = MediaQuery.sizeOf(context);
    final left = anchor.left.clamp(
      IrisSpace.lg,
      size.width - _width - IrisSpace.lg,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          left: left,
          bottom: size.height - anchor.top + 8,
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
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: .25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Row(
                    icon: Icons.photo_outlined,
                    label: 'Photos',
                    source: AttachSource.photos,
                  ),
                  const _Row(
                    icon: Icons.folder_outlined,
                    label: 'Files',
                    source: AttachSource.files,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      'up to ${Attachment.maxPerMessage} files · 20 MB each',
                      style: type.codeSmall.copyWith(
                        fontSize: 10.5,
                        color: palette.inkMuted,
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

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.source});

  final IconData icon;
  final String label;
  final AttachSource source;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: () => Navigator.of(context).pop(source),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: palette.ink),
              const SizedBox(width: IrisSpace.md),
              Text(
                label,
                style: context.type.body.copyWith(
                  fontSize: 15,
                  color: palette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
