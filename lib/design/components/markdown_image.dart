// lib/design/components/markdown_image.dart
/// An image a reply links to. Iris otherwise talks only to the person's own
/// server, so an image on someone else's host is fetched only when they tap
/// for it.
library;

import 'package:flutter/material.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import 'primitives.dart';

class MarkdownImage extends StatefulWidget {
  const MarkdownImage({required this.url, this.alt, super.key});

  final String url;
  final String? alt;

  /// Only web images are offered: a `file:` or `data:` source from a reply
  /// is never one the person meant to open.
  static bool canShow(String? url) {
    final uri = Uri.tryParse(url ?? '');
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  @override
  State<MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<MarkdownImage> {
  bool _load = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final label = (widget.alt?.trim().isNotEmpty ?? false)
        ? widget.alt!.trim()
        : 'Image';
    if (!_load) {
      return IrisPressable(
        onTap: () => setState(() => _load = true),
        semanticLabel: '$label. Tap to load from ${Uri.parse(widget.url).host}',
        child: Container(
          padding: const EdgeInsets.all(IrisSpace.md),
          decoration: BoxDecoration(
            color: palette.surfaceSunken,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.line, width: IrisStroke.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 18, color: palette.inkMuted),
              const SizedBox(width: IrisSpace.sm),
              Flexible(
                child: Text(
                  '$label · ${Uri.parse(widget.url).host} · Tap to load',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: type.caption.copyWith(color: palette.inkMuted),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          semanticLabel: label,
          errorBuilder: (context, _, _) => Text(
            "$label (couldn't load)",
            style: type.caption.copyWith(color: palette.inkMuted),
          ),
        ),
      ),
    );
  }
}
