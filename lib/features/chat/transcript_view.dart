/// How each kind of transcript entry looks.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../demo/demo_content.dart';
import '../../demo/demo_mode.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/markdown.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';
import 'attachment_chip.dart';
import 'links.dart';

/// One entry, dispatched on its kind.
///
/// [live] is the turn's current state, passed only to the assistant turn that
/// is still arriving. It drives that turn's orb and meta line; a finished turn
/// gets no live state and settles into the resting orb.
class TranscriptEntry extends StatelessWidget {
  const TranscriptEntry(
    this.item, {
    this.live,
    this.onRetry,
    this.retrying = false,
    this.onHold,
    this.collapsing = false,
    super.key,
  });

  final TranscriptItem item;
  final AgentState? live;

  /// Retries the failed turn. Only a retryable notice uses it.
  final VoidCallback? onRetry;

  /// A retry is on its way.
  final bool retrying;

  /// Called with the entry's screen rectangle on a long-press, to open its
  /// menu. Only the person's and the agent's messages are held.
  final void Function(Rect anchor)? onHold;

  /// The entry is part of an undone exchange, folding away.
  final bool collapsing;

  @override
  Widget build(BuildContext context) {
    final entry = _entry();
    final holdable = item is UserTurn || item is AssistantTurn;
    final held = holdable && onHold != null
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () => onHold!(_rectOf(context)),
            child: entry,
          )
        : entry;
    return collapsing ? _Collapse(child: held) : held;
  }

  Widget _entry() => switch (item) {
    final UserTurn turn => _UserBubble(turn),
    final AssistantTurn turn => _AssistantBlock(turn, live: live),
    final ToolCall call => ToolCard(call),
    final Notice notice when notice.retryable && onRetry != null => _FailedCard(
      notice,
      onRetry: onRetry!,
      retrying: retrying,
    ),
    final Notice notice => _NoticeLine(notice),
  };
}

Rect _rectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The last exchange folds away: height to 0, scaled to .96, faded by 60% of
/// the way, blurred a pixel (frame A3). Under reduced motion it only fades.
class _Collapse extends StatelessWidget {
  const _Collapse({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 150),
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: child,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 300),
      curve: IrisCurves.exit,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: t,
          child: Opacity(
            opacity: (t / .4).clamp(0.0, 1.0),
            child: Transform.scale(scale: .96 + .04 * t, child: child),
          ),
        ),
      ),
      child: child,
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.turn);

  final UserTurn turn;

  /// The design's bubble: a soft rounded shape with the bottom-right corner
  /// pulled in, so the bubble reads as sent from the right.
  static const _shape = BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
    bottomRight: Radius.circular(6),
    bottomLeft: Radius.circular(20),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        // Eighty-two percent of the column, so a short message stays short and
        // a long one never runs the full width into the agent's replies.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (turn.attachments.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: IrisSpace.xs,
                runSpacing: IrisSpace.xs,
                children: [
                  for (final name in turn.attachments)
                    AttachmentChip(name: name),
                ],
              ),
            if (turn.attachments.isNotEmpty && turn.text.isNotEmpty)
              const SizedBox(height: IrisSpace.xs),
            if (turn.text.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .82,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.palette.accentQuiet,
                    borderRadius: _shape,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                    child: Text(
                      turn.text,
                      style: theme.typography.body.copyWith(
                        fontSize: 15,
                        height: 1.45,
                        color: theme.palette.ink,
                      ),
                    ),
                  ),
                ),
              ),
            if (turn.steered) ...[
              const SizedBox(height: IrisSpace.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 12,
                    color: theme.palette.inkMuted,
                  ),
                  const SizedBox(width: IrisSpace.xxs),
                  Text(
                    'Steered',
                    style: theme.typography.caption.copyWith(
                      color: theme.palette.inkMuted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The agent's turn: a header with the orb and the live state, the thoughts,
/// and the reply.
class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock(this.turn, {this.live});

  final AssistantTurn turn;

  /// Non-null only while this turn is the one arriving.
  final AgentState? live;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final hasText = turn.text.trim().isNotEmpty;
    final reasoning = turn.reasoning.trim();
    final streaming = turn.streaming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Resting once finished, so a long history is a quiet column of
            // marks rather than a column of motion.
            IrisOrb(state: live ?? AgentState.rest, size: 20),
            const SizedBox(width: IrisSpace.sm),
            Text(
              'Iris',
              style: theme.typography.heading.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (live case final state?) ...[
              const SizedBox(width: IrisSpace.sm),
              Text(
                state.label.toLowerCase(),
                style: theme.typography.codeSmall.copyWith(
                  fontSize: 11,
                  color: palette.inkFaint,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: IrisSpace.sm),
        if (reasoning.isNotEmpty) ...[
          _ThoughtsCard(
            text: reasoning,
            streaming: streaming,
            hasText: hasText,
          ),
          const SizedBox(height: IrisSpace.sm),
        ],
        if (hasText)
          IrisMarkdown(
            turn.text,
            highlight: !streaming,
            onTapLink: (href) => href == leaveDemoLink
                ? leaveDemo(context)
                : unawaited(openLink(href)),
          ),
        if (streaming) ...[
          if (hasText) const SizedBox(height: IrisSpace.xs),
          const _Caret(),
        ],
      ],
    );
  }
}

/// The model's visible reasoning, collapsible.
///
/// It opens while the model is thinking and nothing else has arrived, because
/// that is when someone wants to see what is happening. It closes itself once
/// the reply starts, unless the person opened or closed it, which they then
/// keep. A finished turn starts closed.
class _ThoughtsCard extends StatefulWidget {
  const _ThoughtsCard({
    required this.text,
    required this.streaming,
    required this.hasText,
  });

  final String text;
  final bool streaming;
  final bool hasText;

  @override
  State<_ThoughtsCard> createState() => _ThoughtsCardState();
}

class _ThoughtsCardState extends State<_ThoughtsCard> {
  late bool _open = widget.streaming && !widget.hasText;

  /// Set once the person has opened or closed the card, after which the
  /// automatic behaviour leaves it alone.
  bool _touched = false;

  @override
  void didUpdateWidget(_ThoughtsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.hasText && widget.hasText && !_touched) {
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final thinking = palette.colorFor(AgentState.thinking);
    final title = widget.streaming && !widget.hasText
        ? 'Thinking…'
        : 'Thought process';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: thinking.withValues(alpha: .14),
          width: IrisStroke.hairline,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IrisPressable(
              ensureTapTarget: false,
              semanticLabel: title,
              onTap: () => setState(() {
                _touched = true;
                _open = !_open;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: type.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: thinking,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: context.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      curve: IrisCurves.standard,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: thinking,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            () {
              final body = _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text(
                        widget.text,
                        style: type.body.copyWith(
                          fontSize: 13,
                          height: 1.55,
                          fontStyle: FontStyle.italic,
                          color: palette.inkMuted,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity);
              // A zero-length AnimatedSize restarts during layout, which
              // Flutter asserts on; with motion reduced there is nothing to
              // animate, so it is left out, as IrisAnimatedSize does.
              if (context.reduceMotion) return body;
              return AnimatedSize(
                duration: const Duration(milliseconds: 450),
                curve: IrisCurves.standard,
                alignment: Alignment.topCenter,
                child: body,
              );
            }(),
          ],
        ),
      ),
    );
  }
}

/// The blinking caret that marks a reply still being written.
///
/// Under reduced motion it is a solid block and runs no ticker, because a
/// blinking cursor is exactly the kind of motion that setting asks to remove.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = context.reduceMotion;
    if (_reduced) {
      _blink.stop();
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.palette.colorFor(AgentState.streaming);
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(
        // Stepped, not faded: the on and off halves are hard edges, as the
        // design's steps(1) keyframe is.
        opacity: _reduced || _blink.value < .5 ? 1 : 0,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 8,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// A turn that failed, with a way to run it again: the design's failed-turn
/// card. While the retry is on its way the pill shows it working, so a second
/// tap cannot send a second retry.
class _FailedCard extends StatelessWidget {
  const _FailedCard(
    this.notice, {
    required this.onRetry,
    required this.retrying,
  });

  final Notice notice;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final failed = palette.colorFor(AgentState.failed);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: failed.withValues(alpha: .08),
        borderRadius: const BorderRadius.all(IrisRadius.lg),
        border: Border.all(
          color: failed.withValues(alpha: .22),
          width: IrisStroke.hairline,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              notice.text,
              style: type.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: failed,
              ),
            ),
          ),
          const SizedBox(width: IrisSpace.md),
          AnimatedSwitcher(
            duration: context.reduceMotion
                ? Duration.zero
                : IrisDurations.normal,
            switchInCurve: IrisCurves.standard,
            child: retrying
                ? Semantics(
                    key: const ValueKey('retrying'),
                    container: true,
                    excludeSemantics: true,
                    label: 'Retrying',
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: IrisOrb(
                          state: AgentState.loading,
                          size: 22,
                          glow: false,
                        ),
                      ),
                    ),
                  )
                : IrisPressable(
                    key: const ValueKey('retry'),
                    onTap: () {
                      unawaited(IrisHaptics.commit());
                      onRetry();
                    },
                    scale: .95,
                    semanticLabel: 'Retry',
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: failed,
                        borderRadius: const BorderRadius.all(IrisRadius.full),
                      ),
                      child: Text(
                        'Retry',
                        style: type.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.inkInverse,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine(this.notice);

  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    if (notice.isError) {
      // An error gets a tinted notice, not just red text, so it is found
      // without reading. The text carries the colour too, for contrast.
      final failed = palette.colorFor(AgentState.failed);
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: failed.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: failed.withValues(alpha: .22),
            width: IrisStroke.hairline,
          ),
        ),
        child: Text(
          notice.text,
          style: type.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: failed,
          ),
        ),
      );
    }
    return Center(
      child: Text(
        notice.text,
        textAlign: TextAlign.center,
        style: type.caption.copyWith(color: palette.inkMuted),
      ),
    );
  }
}

/// A tool the agent ran: what, with what, and how it ended. Tap to expand and
/// see the output.
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
    final arguments = call.arguments?.trim() ?? '';
    final output = call.output?.trim() ?? '';
    final (statusColor, statusText) = switch (call.status) {
      ToolStatus.running => (palette.colorFor(AgentState.working), 'running'),
      ToolStatus.done => (palette.inkFaint, 'done'),
      ToolStatus.failed => (palette.colorFor(AgentState.failed), 'failed'),
    };
    return IrisPressable(
      onTap: arguments.isEmpty && output.isEmpty
          ? null
          : () => setState(() => _open = !_open),
      semanticLabel: '${call.name}, $statusText',
      ensureTapTarget: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.line, width: IrisStroke.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: switch (call.status) {
                    ToolStatus.running => const IrisOrb(
                      state: AgentState.working,
                      size: 24,
                      glow: false,
                    ),
                    ToolStatus.done => Icon(
                      Icons.check,
                      size: 14,
                      color: palette.colorFor(AgentState.done),
                    ),
                    ToolStatus.failed => Icon(
                      Icons.close,
                      size: 14,
                      color: palette.colorFor(AgentState.failed),
                    ),
                  },
                ),
                const SizedBox(width: IrisSpace.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        call.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.code.copyWith(
                          fontSize: 12.5,
                          height: 1.3,
                          color: palette.ink,
                        ),
                      ),
                      if (arguments.isNotEmpty)
                        Text(
                          _clip(arguments),
                          maxLines: _open ? null : 1,
                          overflow: _open ? null : TextOverflow.ellipsis,
                          style: theme.typography.codeSmall.copyWith(
                            fontSize: 11,
                            color: palette.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: IrisSpace.sm),
                Text(
                  statusText,
                  style: theme.typography.caption.copyWith(
                    fontSize: 11,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            if (_open && output.isNotEmpty) ...[
              const SizedBox(height: IrisSpace.sm),
              Text(
                _clip(output),
                style: theme.typography.codeSmall.copyWith(
                  fontSize: 11.5,
                  color: palette.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
