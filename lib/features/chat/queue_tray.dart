/// The messages waiting for the running reply to finish.
///
/// Pinned just above the composer rather than in the transcript: a reply
/// takes minutes and keeps growing, so a bubble at the bottom of the
/// transcript would keep sliding out of reach and sit between the streaming
/// reply and the person. The tray stays put, shows the order, and removes a
/// message in one tap. Four or more show the first two and a "+N more" row.
library;

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

class QueueTray extends StatefulWidget {
  const QueueTray({
    required this.items,
    required this.paused,
    required this.onRemove,
    required this.onSendNext,
    required this.onClear,
    super.key,
  });

  final List<QueuedMessage> items;

  /// A failed or stopped turn paused the tray: nothing sends until the
  /// person says.
  final bool paused;
  final ValueChanged<String> onRemove;
  final VoidCallback onSendNext;
  final VoidCallback onClear;

  @override
  State<QueueTray> createState() => _QueueTrayState();
}

class _QueueTrayState extends State<QueueTray> {
  bool _expanded = false;

  static const _collapsedLimit = 3;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final items = widget.items;
    final collapse = items.length > _collapsedLimit && !_expanded;
    final shown = collapse ? items.take(2).toList() : items;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.lineStrong,
          width: IrisStroke.hairline,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
            child: Row(
              children: [
                IrisLabel(
                  widget.paused ? 'Paused' : 'Queued · after this reply',
                  small: true,
                ),
                const Spacer(),
                if (widget.paused) ...[
                  IrisPressable(
                    onTap: widget.onSendNext,
                    semanticLabel: 'Send next',
                    child: Text(
                      'Send next',
                      style: type.label.copyWith(color: palette.accent),
                    ),
                  ),
                  const SizedBox(width: IrisSpace.md),
                  IrisPressable(
                    onTap: widget.onClear,
                    semanticLabel: 'Clear',
                    child: Text(
                      'Clear',
                      style: type.label.copyWith(color: palette.inkMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final (index, item) in shown.indexed)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.accentQuiet,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: type.codeSmall.copyWith(
                        fontSize: 11,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: IrisSpace.md),
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(
                        fontSize: 14,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  IrisPressable(
                    onTap: () => widget.onRemove(item.id),
                    semanticLabel: 'Remove message ${index + 1}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: palette.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (collapse)
            IrisPressable(
              onTap: () => setState(() => _expanded = true),
              semanticLabel: '${items.length - 2} more queued messages',
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+${items.length - 2} more',
                      style: type.codeSmall.copyWith(
                        fontSize: 12,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              'Queued messages are held on this phone',
              style: type.caption.copyWith(
                fontSize: 11,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
