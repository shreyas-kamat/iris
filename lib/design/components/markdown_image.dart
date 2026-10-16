// lib/design/components/markdown_image.dart
/// An image a reply links to. Iris otherwise talks only to the person's own
/// server, so an image on someone else's host is fetched only when they tap
/// for it (frame B10).
///
/// A 4:3 card in four states: waiting for the tap (dashed edge, the host and
/// "Tap to load"), loading (the connecting orb), loaded (the picture with its
/// name in mono) and failed ("Couldn't load", tap to retry).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/palette.dart';
import 'dashed_border.dart';
import 'image_host_scope.dart';
import 'iris_orb.dart';
import 'primitives.dart';
import 'sheet.dart';

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
  bool _asked = false;

  /// Bumped on a retry so the image is asked for again.
  int _attempt = 0;

  String get _host => Uri.parse(widget.url).host;

  /// A host the person said to load from without asking loads at once. Read
  /// the first time only, so a later change to the list never loads an image
  /// the person has already seen waiting.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    final hosts = ImageHostScope.maybeOf(context)?.hosts;
    if (hosts != null && hosts.contains(_host.toLowerCase())) _load = true;
  }

  Future<void> _offerAlways() async {
    final scope = ImageHostScope.maybeOf(context);
    if (scope == null) return;
    final host = _host;
    final yes = await showIrisSheet<bool>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        child: IrisPressable(
          onTap: () => Navigator.of(sheetContext).pop(true),
          semanticLabel: 'Always load from $host',
          child: SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ExcludeSemantics(
                child: Text(
                  'Always load from $host',
                  style: sheetContext.type.body.copyWith(
                    color: sheetContext.palette.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (yes != true || !mounted) return;
    scope.onAllow(host);
    setState(() => _load = true);
  }

  String get _name {
    final alt = widget.alt?.trim() ?? '';
    if (alt.isNotEmpty) return alt;
    final segments = Uri.parse(widget.url).pathSegments;
    return segments.isEmpty || segments.last.isEmpty ? 'Image' : segments.last;
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).round()} KB';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    if (!_load) {
      return Semantics(
        container: true,
        button: true,
        label: '$_name. Tap to load from $_host',
        excludeSemantics: true,
        child: IrisPressable(
          onTap: () => setState(() => _load = true),
          // Without a scope a long press does nothing, but is still one: it
          // must not count as a tap and load the image.
          onLongPress: ImageHostScope.maybeOf(context) == null
              ? () {}
              : () => unawaited(_offerAlways()),
          ensureTapTarget: false,
          child: _Card(
            fill: palette.surfaceSunken,
            dashed: palette.lineStrong,
            child: _Centered(
              children: [
                Icon(Icons.image_outlined, size: 22, color: palette.inkMuted),
                const SizedBox(height: IrisSpace.sm),
                Text(
                  _host,
                  style: type.body.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to load',
                  style: type.codeSmall.copyWith(
                    fontSize: 11,
                    color: palette.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Image.network(
      widget.url,
      key: ValueKey(_attempt),
      fit: BoxFit.contain,
      semanticLabel: _name,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return _Loaded(name: _name, child: child);
        final total = progress.expectedTotalBytes;
        return _Card(
          fill: palette.surfaceSunken,
          border: palette.line,
          child: _Centered(
            children: [
              const IrisOrb(state: AgentState.loading, size: 36, glow: false),
              const SizedBox(height: IrisSpace.sm),
              Text(
                total == null ? 'Loading…' : _size(total),
                style: type.codeSmall.copyWith(
                  fontSize: 11,
                  color: palette.inkMuted,
                ),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, _, _) {
        final failed = palette.colorFor(AgentState.failed);
        return Semantics(
          container: true,
          button: true,
          label: "$_name. Couldn't load. Tap to retry",
          excludeSemantics: true,
          child: IrisPressable(
            onTap: () => setState(() => _attempt++),
            ensureTapTarget: false,
            child: _Card(
              fill: failed.withValues(alpha: .08),
              border: failed.withValues(alpha: .32),
              child: _Centered(
                children: [
                  Icon(Icons.broken_image_outlined, size: 22, color: failed),
                  const SizedBox(height: IrisSpace.sm),
                  Text(
                    "Couldn't load",
                    style: type.body.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to retry',
                    style: type.codeSmall.copyWith(
                      fontSize: 11,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The picture, with its name in mono at the corner.
class _Loaded extends StatelessWidget {
  const _Loaded({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            child,
            Container(
              margin: const EdgeInsets.all(IrisSpace.sm),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.surfaceSunken.withValues(alpha: .8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.codeSmall.copyWith(
                  fontSize: 10.5,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 4:3 card all three waiting states share.
class _Card extends StatelessWidget {
  const _Card({
    required this.fill,
    required this.child,
    this.border,
    this.dashed,
  });

  final Color fill;
  final Color? border;

  /// A dashed edge instead of a solid one: not loaded, and not yet asked.
  final Color? dashed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(14));
    return AspectRatio(
      key: const ValueKey('image-card'),
      aspectRatio: 4 / 3,
      child: CustomPaint(
        foregroundPainter: dashed == null
            ? null
            : DashedRRectPainter(color: dashed!, radius: radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: border == null
                ? null
                : Border.all(color: border!, width: IrisStroke.hairline),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}
