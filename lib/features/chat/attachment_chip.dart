/// A file named in the composer or in a sent message.
library;

import 'package:flutter/material.dart';

import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

class AttachmentChip extends StatelessWidget {
  const AttachmentChip({required this.name, this.onRemove, super.key});

  final String name;

  /// Shows a remove button. Null in a sent message.
  final VoidCallback? onRemove;

  static const _images = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic'};

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final dot = name.lastIndexOf('.');
    final image = dot >= 0 && _images.contains(name.substring(dot).toLowerCase());
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            image ? Icons.image_outlined : Icons.description_outlined,
            size: 14,
            color: palette.inkMuted,
          ),
          const SizedBox(width: IrisSpace.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption.copyWith(color: palette.ink),
            ),
          ),
          if (onRemove case final remove?) ...[
            const SizedBox(width: IrisSpace.xxs),
            IrisPressable(
              onTap: remove,
              semanticLabel: 'Remove $name',
              ensureTapTarget: false,
              child: Icon(Icons.close, size: 14, color: palette.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
