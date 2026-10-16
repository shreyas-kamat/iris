/// A brief message floating above the bottom of the screen, with at most one
/// action.
///
/// Iris has no snackbar: a Material snackbar needs a Scaffold, and its slide
/// and timing are Material's own. This rises on the standard spring, sits
/// above the floating new-chat bar, and leaves after [IrisToast.visibleFor].
/// One at a time: a new toast replaces the one showing.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'primitives.dart';

abstract final class IrisToast {
  /// Long enough to read a short line and reach Undo with a thumb.
  static const Duration visibleFor = Duration(seconds: 4);
}

OverlayEntry? _current;

void showIrisToast(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  double bottomInset = 104,
  bool top = false,
}) {
  if (_current case final previous? when previous.mounted) previous.remove();
  _current = null;
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  void dismiss() {
    if (entry.mounted) entry.remove();
    if (identical(_current, entry)) _current = null;
  }

  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      bottomInset: bottomInset,
      top: top,
      onDone: dismiss,
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.bottomInset,
    required this.onDone,
    this.top = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double bottomInset;
  final VoidCallback onDone;

  /// Sits under the header instead of above the composer, so it never
  /// covers what is pinned above the composer.
  final bool top;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Shown on the next frame, so the spring has somewhere to rise from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
    _timer = Timer(IrisToast.visibleFor, _leave);
  }

  void _leave() {
    if (!mounted) return;
    _timer?.cancel();
    if (context.reduceMotion) {
      widget.onDone();
      return;
    }
    setState(() => _shown = false);
    _timer = Timer(IrisDurations.normal, widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final reduce = context.reduceMotion;
    final depth = context.iris.depth(IrisPlane.overlay);
    return Positioned(
      left: IrisSpace.lg,
      right: IrisSpace.lg,
      top: widget.top ? MediaQuery.paddingOf(context).top + 64 : null,
      bottom: widget.top
          ? null
          : widget.bottomInset + MediaQuery.paddingOf(context).bottom,
      child: SpringBuilder(
        value: _shown || reduce ? 1 : 0,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * (widget.top ? -24 : 24)),
            child: child,
          ),
        ),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              IrisSpace.lg,
              IrisSpace.sm,
              IrisSpace.sm,
              IrisSpace.sm,
            ),
            constraints: const BoxConstraints(minHeight: IrisSize.control),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: const BorderRadius.all(IrisRadius.md),
              border: Border.all(
                color: palette.line,
                width: IrisStroke.hairline,
              ),
              boxShadow: depth.shadows,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.message,
                    style: type.body.copyWith(color: palette.ink),
                  ),
                ),
                if (widget.actionLabel case final label?)
                  IrisPressable(
                    onTap: () {
                      widget.onAction?.call();
                      widget.onDone();
                    },
                    semanticLabel: label,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: IrisSpace.md,
                      ),
                      child: Text(
                        label,
                        style: type.label.copyWith(color: palette.accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
