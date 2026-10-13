/// How each kind of transcript entry looks.
library;

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

/// One entry, dispatched on its kind.
class TranscriptEntry extends StatelessWidget {
  const TranscriptEntry(this.item, {super.key});

  final TranscriptItem item;

  @override
  Widget build(BuildContext context) => switch (item) {
    final UserTurn turn => _UserBubble(turn),
    final AssistantTurn turn => _AssistantBlock(turn),
    final ToolCall call => ToolCard(call),
    final Notice notice => _NoticeLine(notice),
  };
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.turn);

  final UserTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.palette.accentQuiet,
            borderRadius: const BorderRadius.all(IrisRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IrisSpace.md,
              vertical: IrisSpace.sm,
            ),
            child: SelectableText(
              turn.text,
              style: theme.typography.body.copyWith(color: theme.palette.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock(this.turn);

  final AssistantTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final hasText = turn.text.trim().isNotEmpty;
    final reasoning = turn.reasoning.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reasoning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: IrisSpace.xs),
            child: Text(
              reasoning,
              // While it is the only thing arriving, show more of it.
              maxLines: turn.streaming && !hasText ? 6 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption.copyWith(
                color: theme.palette.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (hasText)
          SelectableText(
            turn.text,
            style: theme.typography.bodyLarge.copyWith(
              color: theme.palette.ink,
            ),
          )
        else if (turn.streaming)
          Text(
            'Thinking…',
            style: theme.typography.caption.copyWith(
              color: theme.palette.inkMuted,
            ),
          ),
      ],
    );
  }
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine(this.notice);

  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Text(
        notice.text,
        textAlign: TextAlign.center,
        style: context.type.caption.copyWith(
          color: notice.isError
              ? palette.colorFor(AgentState.failed)
              : palette.inkMuted,
        ),
      ),
    );
  }
}

/// A tool the agent ran: what, with what, and what came back. Tap to expand.
class ToolCard extends StatefulWidget {
  const ToolCard(this.call, {super.key});

  final ToolCall call;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _open = false;

  /// Long outputs are cut here even when open; the full text stays on the
  /// server.
  static const _limit = 4000;

  static String _clip(String text) =>
      text.length <= _limit ? text : '${text.substring(0, _limit)}…';

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final call = widget.call;
    final (state, label) = switch (call.status) {
      ToolStatus.running => (AgentState.working, 'Running'),
      ToolStatus.done => (AgentState.done, 'Done'),
      ToolStatus.failed => (AgentState.failed, 'Failed'),
    };
    final arguments = call.arguments?.trim() ?? '';
    final output = call.output?.trim() ?? '';
    return IrisPressable(
      onTap: arguments.isEmpty && output.isEmpty
          ? null
          : () => setState(() => _open = !_open),
      semanticLabel: '${call.name}, $label',
      ensureTapTarget: false,
      child: IrisCard(
        accent: call.status == ToolStatus.failed
            ? palette.colorFor(AgentState.failed)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IrisChip.state(label, state, palette),
                const SizedBox(width: IrisSpace.sm),
                Expanded(
                  child: Text(
                    call.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.code.copyWith(color: palette.ink),
                  ),
                ),
              ],
            ),
            if (arguments.isNotEmpty) ...[
              const SizedBox(height: IrisSpace.xs),
              Text(
                _clip(arguments),
                maxLines: _open ? null : 2,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: theme.typography.codeSmall.copyWith(
                  color: palette.inkMuted,
                ),
              ),
            ],
            if (output.isNotEmpty) ...[
              const SizedBox(height: IrisSpace.xs),
              Text(
                _clip(output),
                maxLines: _open ? null : 3,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: theme.typography.codeSmall.copyWith(color: palette.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
