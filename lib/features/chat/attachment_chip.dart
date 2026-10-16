/// A file named in the composer or in a sent message (frame B8): a 52 high
/// chip with a 40 point thumb, the name and, in the composer, the size.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

class AttachmentChip extends StatelessWidget {
  const AttachmentChip({
    required this.name,
    this.bytes,
    this.size,
    this.onRemove,
    super.key,
  });

  final String name;

  /// The picture itself, for the thumb. Null in a sent message: nothing is
  /// kept after a restart, so it shows the glyph.
  final Uint8List? bytes;

  /// Size in bytes, shown in mono.
  final int? size;

  /// Shows a remove button. Null in a sent message.
  final VoidCallback? onRemove;

  static const _images = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic'};

  static String sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final dot = name.lastIndexOf('.');
    final image =
        dot >= 0 && _images.contains(name.substring(dot).toLowerCase());
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
            ),
            child: image && bytes != null
                ? Image.memory(
                    bytes!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: palette.inkMuted,
                    ),
                  )
                : Icon(
                    image ? Icons.image_outlined : Icons.description_outlined,
                    size: 18,
                    color: palette.inkMuted,
                  ),
          ),
          const SizedBox(width: IrisSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: palette.ink,
                  ),
                ),
                if (size case final size?)
                  Text(
                    sizeLabel(size),
                    style: theme.typography.codeSmall.copyWith(
                      fontSize: 10.5,
                      color: palette.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (onRemove case final remove?)
            IrisPressable(
              onTap: remove,
              semanticLabel: 'Remove $name',
              ensureTapTarget: false,
              child: SizedBox(
                width: 40,
                height: 44,
                child: Icon(Icons.close, size: 16, color: palette.inkMuted),
              ),
            )
          else
            const SizedBox(width: IrisSpace.md),
        ],
      ),
    );
  }
}
