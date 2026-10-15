/// Where the person writes to the agent, stops it, and finds slash commands.
///
/// The box is one rounded surface holding the field and a row beneath it: the
/// model the turn will use, and the one action, send or stop. While a turn is
/// running the box's border takes the agent's state colour, so the composer
/// itself says what the agent is doing.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';
import 'attachment_chip.dart';

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.running,
    required this.onSend,
    required this.onStop,
    this.enabled = true,
    this.commands = const [],
    this.model,
    this.onModel,
    this.state = AgentState.idle,
    this.contextUsage,
    this.attachments = const [],
    this.onAttach,
    this.onRemoveAttachment,
    this.onContext,
    super.key,
  });

  final TextEditingController controller;

  /// A turn is in progress: the action becomes Stop, and text steers the turn.
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// False while the conversation cannot take a message.
  final bool enabled;

  /// Slash commands to suggest while the person types one.
  final List<SlashCommand> commands;

  /// The model the next turn will use, shown as a chip. Null hides the chip.
  final String? model;

  /// Opens the model picker. Null shows the chip as read-only.
  final VoidCallback? onModel;

  /// The turn's current state. Tints the border and the stop orb while running.
  final AgentState state;

  /// How full the context window is; null hides the ring until the gateway
  /// first says, which it does after a turn.
  final ContextUsage? contextUsage;

  /// Opens the context sheet.
  final VoidCallback? onContext;

  /// Files waiting to go with the next message.
  final List<String> attachments;

  /// Opens the file picker. Null hides the button.
  final VoidCallback? onAttach;
  final ValueChanged<int>? onRemoveAttachment;

  /// At most this many suggestions show, so they never hide the transcript.
  static const suggestions = 5;

  /// Commands matching what has been typed: a slash and the start of a name,
  /// before any argument.
  List<SlashCommand> _matching(String text) {
    if (!text.startsWith('/') || text.contains(' ') || commands.isEmpty) {
      return const [];
    }
    final query = text.toLowerCase();
    return commands
        .where((command) => command.name.toLowerCase().startsWith(query))
        .take(suggestions)
        .toList();
  }

  void _choose(SlashCommand command) {
    final text = '${command.name} ';
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final matching = _matching(value.text);
        final canSend =
            enabled && (value.text.trim().isNotEmpty || attachments.isNotEmpty);
        // Text during a run steers it. A slash command is not a steer, so it
        // gets no button.
        final canSteer =
            running && canSend && !value.text.trimLeft().startsWith('/');
        final border = running
            ? palette.colorFor(state).withValues(alpha: .33)
            : palette.line;
        return Padding(
          // The scaffold already clears the home indicator and the keyboard,
          // so only the gutter and a little air are added here.
          padding: EdgeInsets.fromLTRB(
            IrisSpace.md,
            IrisSpace.sm,
            IrisSpace.md,
            IrisSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final command in matching)
                IrisPressable(
                  onTap: () => _choose(command),
                  semanticLabel: '${command.name}, ${command.description}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: IrisSpace.xs),
                    child: Row(
                      children: [
                        Text(
                          command.name,
                          style: theme.typography.code.copyWith(
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(width: IrisSpace.sm),
                        Expanded(
                          child: Text(
                            command.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.caption.copyWith(
                              color: palette.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (matching.isNotEmpty) const SizedBox(height: IrisSpace.xs),
              AnimatedContainer(
                duration: context.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 400),
                curve: IrisCurves.standard,
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border, width: IrisStroke.hairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (attachments.isNotEmpty) ...[
                      Wrap(
                        spacing: IrisSpace.xs,
                        runSpacing: IrisSpace.xs,
                        children: [
                          for (final (i, name) in attachments.indexed)
                            AttachmentChip(
                              name: name,
                              onRemove: onRemoveAttachment == null
                                  ? null
                                  : () => onRemoveAttachment!(i),
                            ),
                        ],
                      ),
                      const SizedBox(height: IrisSpace.sm),
                    ],
                    // Borderless: the box is the chrome, so the field inside
                    // it must not draw its own.
                    TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      cursorColor: palette.accent,
                      style: theme.typography.body.copyWith(
                        fontSize: 15,
                        height: 1.45,
                        color: palette.ink,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 2),
                        hintText: 'Message Iris…',
                        hintStyle: theme.typography.body.copyWith(
                          fontSize: 15,
                          height: 1.45,
                          color: palette.inkFaint,
                        ),
                      ),
                    ),
                    const SizedBox(height: IrisSpace.xs),
                    Row(
                      children: [
                        if (onAttach != null && !running) ...[
                          IrisPressable(
                            onTap: enabled ? onAttach : null,
                            semanticLabel: 'Attach',
                            child: Icon(
                              Icons.add,
                              size: 20,
                              color: palette.inkMuted,
                            ),
                          ),
                          const SizedBox(width: IrisSpace.xs),
                        ],
                        if (model case final model?) ...[
                          _ModelChip(model: model, onTap: onModel),
                          const SizedBox(width: IrisSpace.xs),
                        ],
                        if (contextUsage case final usage?)
                          _ContextRing(usage: usage, onTap: onContext),
                        const Spacer(),
                        AnimatedSwitcher(
                          duration: context.reduceMotion
                              ? Duration.zero
                              : IrisDurations.normal,
                          switchInCurve: IrisCurves.standard,
                          switchOutCurve: IrisCurves.exit,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween(
                                    begin: .8,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: canSteer
                              ? Padding(
                                  key: const ValueKey('steer'),
                                  padding: const EdgeInsets.only(
                                    right: IrisSpace.sm,
                                  ),
                                  child: _SteerButton(onTap: onSend),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('no-steer'),
                                ),
                        ),
                        // Send and Stop share one slot, so the action changes
                        // in place rather than the row reflowing.
                        AnimatedSwitcher(
                          duration: context.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          switchInCurve: IrisCurves.standard,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween(
                                    begin: .9,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: running
                              ? _StopButton(
                                  key: const ValueKey('stop'),
                                  state: state,
                                  onTap: onStop,
                                )
                              : _SendButton(
                                  key: const ValueKey('send'),
                                  enabled: canSend,
                                  onTap: onSend,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The model the next turn will use. Tapping it opens the picker; when there is
/// no picker (the conversation is not live) it is a label and carries no chevron.
class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.model, this.onTap});

  final String model;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Model: $model',
      ensureTapTarget: false,
      child: Container(
        height: IrisSize.controlSmall,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(IrisRadius.full),
          border: Border.all(color: palette.line, width: IrisStroke.hairline),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.codeSmall.copyWith(
                  fontSize: 12,
                  color: palette.inkMuted,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: IrisSpace.xs),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 12,
                  color: palette.inkMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Send: the accent circle with an up arrow. Faded when there is nothing to
/// send, so it never looks live when it is not.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap, super.key});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: IrisPressable(
        onTap: enabled ? onTap : null,
        semanticLabel: 'Send',
        ensureTapTarget: false,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.arrow_upward, size: 18, color: palette.accentInk),
        ),
      ),
    );
  }
}

/// Stop: a dark circle holding the agent's own orb with a square in its
/// middle. The orb shows which state is being stopped.
class _StopButton extends StatelessWidget {
  const _StopButton({required this.state, required this.onTap, super.key});

  final AgentState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Stop',
      ensureTapTarget: false,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.surface,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: IrisOrb(state: state, size: 40, glow: false),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: palette.ink,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Steer: a ring of the thinking hue around a turning arrow. It sits beside
/// Stop rather than replacing it, because during a run both are real choices.
class _SteerButton extends StatelessWidget {
  const _SteerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thinking = context.palette.colorFor(AgentState.thinking);
    return IrisPressable(
      onTap: () {
        unawaited(IrisHaptics.commit());
        onTap();
      },
      semanticLabel: 'Steer',
      scale: .92,
      ensureTapTarget: false,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: thinking.withValues(alpha: .14),
          shape: BoxShape.circle,
          border: Border.all(
            color: thinking.withValues(alpha: .4),
            width: IrisStroke.hairline,
          ),
        ),
        child: Icon(Icons.subdirectory_arrow_right, size: 18, color: thinking),
      ),
    );
  }
}

/// The context window as a ring beside the model chip. Tapping it opens the
/// numbers.
class _ContextRing extends StatelessWidget {
  const _ContextRing({required this.usage, this.onTap});

  final ContextUsage usage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final percent = usage.percent.round();
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Context window, $percent percent',
      child: ExcludeSemantics(
        child: IrisRing(
          value: usage.percent / 100,
          semanticLabel: 'Context window, $percent percent',
        ),
      ),
    );
  }
}
