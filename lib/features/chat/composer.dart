/// Where the person writes to the agent, stops it, and finds slash commands.
///
/// The box is one rounded surface holding the field and a row beneath it: the
/// model the turn will use, and the one action, send or stop. While a turn is
/// running the box's border takes the agent's state colour, so the composer
/// itself says what the agent is doing.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/attachment.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/send_glyph.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';
import 'attachment_chip.dart';
import 'attachment_menu.dart';
import 'attachment_picker.dart';

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
    this.recording,
    this.level,
    this.transcribing = false,
    this.onMic,
    this.onStopRecording,
    this.onCancelRecording,
    this.onContext,
    this.busyMode = BusyMode.interrupt,
    super.key,
  });

  final TextEditingController controller;

  /// A turn is in progress: the action is Stop until there is text, then it is
  /// the glyph of what sending will do ([busyMode]).
  final bool running;

  /// What sending does while a turn runs; picks the glyph and its tag.
  final BusyMode busyMode;
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
  final List<Attachment> attachments;

  /// Called with what the person chose from the "+" menu. Null hides the
  /// button.
  final ValueChanged<AttachSource>? onAttach;
  final ValueChanged<int>? onRemoveAttachment;

  /// How long the current clip has run; null when not recording.
  final Duration? recording;

  /// The loudness of what is being recorded, 0 to 1, about ten a second.
  final Stream<double>? level;

  /// The clip is with Hermes being turned into text.
  final bool transcribing;
  final VoidCallback? onMic;
  final VoidCallback? onStopRecording;
  final VoidCallback? onCancelRecording;

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
        final typed = value.text.trimLeft();
        final busyCommand = RegExp(r'^/(queue|steer)\s+\S').firstMatch(typed);
        // While a reply runs, the action is Stop until there is something to
        // send; then it is the glyph of what sending will do.
        final busyKind = !running || !canSend
            ? null
            : busyCommand != null
            ? (busyCommand.group(1) == 'queue'
                  ? SendKind.queue
                  : SendKind.steer)
            : typed.startsWith('/')
            ? null
            : SendKind.forMode(busyMode);
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
              if (recording != null || transcribing)
                _RecordingBar(
                  elapsed: recording,
                  transcribing: transcribing,
                  level: level,
                  onStop: onStopRecording ?? () {},
                  onCancel: onCancelRecording ?? () {},
                )
              else
                AnimatedContainer(
                  duration: context.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 400),
                  curve: IrisCurves.standard,
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: border,
                      width: IrisStroke.hairline,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (attachments.isNotEmpty) ...[
                        SizedBox(
                          height: 52,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: attachments.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: IrisSpace.xs),
                            itemBuilder: (context, i) => AttachmentChip(
                              name: attachments[i].name,
                              bytes: attachments[i].bytes,
                              size: attachments[i].bytes.length,
                              onRemove: onRemoveAttachment == null
                                  ? null
                                  : () => onRemoveAttachment!(i),
                            ),
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 2,
                          ),
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
                          if (onAttach != null &&
                              !running &&
                              recording == null) ...[
                            _AttachButton(
                              enabled: enabled,
                              full:
                                  attachments.length >=
                                  Attachment.maxPerMessage,
                              onPick: onAttach!,
                            ),
                            if (attachments.length >= Attachment.maxPerMessage)
                              const IrisLabel('5 / 5 files', small: true),
                            const SizedBox(width: IrisSpace.xs),
                          ],
                          if (model case final model?
                              when recording == null) ...[
                            _ModelChip(model: model, onTap: onModel),
                            const SizedBox(width: IrisSpace.xs),
                          ],
                          if (contextUsage case final usage?)
                            _ContextRing(usage: usage, onTap: onContext),
                          const Spacer(),
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
                            child: busyKind != null
                                ? Row(
                                    key: ValueKey('busy-${busyKind.name}'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: IrisSpace.sm,
                                        ),
                                        child: Text(
                                          busyKind.semanticLabel.toUpperCase(),
                                          style: theme.typography.codeSmall
                                              .copyWith(
                                                fontSize: 10.5,
                                                letterSpacing: 1,
                                                color: palette.inkMuted,
                                              ),
                                        ),
                                      ),
                                      _ModeButton(
                                        kind: busyKind,
                                        onTap: onSend,
                                      ),
                                    ],
                                  )
                                : running
                                ? _StopButton(
                                    key: const ValueKey('stop'),
                                    state: state,
                                    onTap: onStop,
                                  )
                                : !canSend && onMic != null && recording == null
                                ? _MicButton(
                                    key: const ValueKey('mic'),
                                    onTap: enabled ? onMic : null,
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
          child: SendGlyph(SendKind.send, color: palette.accentInk, size: 22),
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

/// The action while a reply runs and text is typed: an accent button with
/// the glyph of what sending will do (frame A4).
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.kind, required this.onTap});

  final SendKind kind;
  final VoidCallback onTap;

  static String _hint(SendKind kind) => switch (kind) {
    SendKind.queue => 'Queue, sends after the running reply',
    SendKind.steer => 'Steer, joins the running reply at its next step',
    SendKind.interrupt => 'Interrupt, stops the running reply and sends this',
    _ => 'Send',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IrisPressable(
      onTap: () {
        unawaited(IrisHaptics.commit());
        onTap();
      },
      semanticLabel: _hint(kind),
      scale: .92,
      ensureTapTarget: false,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        child: SendGlyph(kind, color: palette.accentInk, size: 22),
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
    final palette = context.palette;
    final percent = usage.percent.round();
    // Accent until the window is nearly full, then needs-you: the one moment
    // the ring asks anything of the person.
    final tint = percent >= 90
        ? palette.colorFor(AgentState.waiting)
        : palette.accent;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Context window, $percent percent',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IrisRing(
              value: usage.percent / 100,
              semanticLabel: 'Context window, $percent percent',
              size: 26,
              color: tint,
            ),
            if (percent >= 50) ...[
              const SizedBox(width: IrisSpace.xs),
              Text(
                '$percent%',
                style: context.type.codeSmall.copyWith(
                  fontSize: 11.5,
                  color: percent >= 90 ? tint : palette.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "+" : rotates to an x while its menu is open, and is off at the limit.
class _AttachButton extends StatefulWidget {
  const _AttachButton({
    required this.enabled,
    required this.full,
    required this.onPick,
  });

  final bool enabled;
  final bool full;
  final ValueChanged<AttachSource> onPick;

  @override
  State<_AttachButton> createState() => _AttachButtonState();
}

class _AttachButtonState extends State<_AttachButton> {
  bool _open = false;

  Future<void> _show() async {
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = true);
    final source = await showAttachMenu(context, anchor: anchor);
    if (!mounted) return;
    setState(() => _open = false);
    if (source != null) widget.onPick(source);
  }

  @override
  Widget build(BuildContext context) {
    final off = !widget.enabled || widget.full;
    return Opacity(
      opacity: widget.full ? .38 : 1,
      child: IrisPressable(
        onTap: off ? null : () => unawaited(_show()),
        semanticLabel: 'Attach',
        child: AnimatedRotation(
          turns: _open ? .125 : 0,
          duration: context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          child: Icon(Icons.add, size: 20, color: context.palette.inkMuted),
        ),
      ),
    );
  }
}

/// Shown above the composer once the context window is 95% full: Branch
/// starts a fresh chat that carries a summary.
class ContextStrip extends StatelessWidget {
  const ContextStrip({required this.onBranch, super.key});

  final VoidCallback onBranch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final needs = palette.colorFor(AgentState.waiting);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: IrisSpace.md),
      decoration: BoxDecoration(
        color: needs.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: needs.withValues(alpha: .32),
          width: IrisStroke.hairline,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Context is nearly full. Older turns will be summarised.',
              style: context.type.body.copyWith(
                fontSize: 13,
                color: palette.ink,
              ),
            ),
          ),
          IrisPressable(
            onTap: onBranch,
            semanticLabel: 'Branch with a summary',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.md),
              child: Text(
                'Branch',
                style: context.type.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The composer while dictating (frame B9): a 72 high bar. Cancel on the left,
/// a listening orb whose wobble is the live level, the time, and Stop. While
/// the clip is being turned into text the orb thinks and the Stop slot stays
/// empty, so nothing shifts. Reduced motion: the orb holds still and the level
/// shows as ring weight in three steps, at most four times a second.
class _RecordingBar extends StatefulWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.transcribing,
    required this.level,
    required this.onStop,
    required this.onCancel,
  });

  final Duration? elapsed;
  final bool transcribing;
  final Stream<double>? level;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar> {
  final _level = ValueNotifier<double>(0);
  StreamSubscription<double>? _sub;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Read in build, where it is safe to ask; the stream callback only reads it.
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(_RecordingBar old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) _listen();
  }

  void _listen() {
    unawaited(_sub?.cancel());
    _sub = widget.level?.listen((value) {
      // Under reduced motion the level changes at most four times a second.
      final now = DateTime.now();
      if (_reduced &&
          now.difference(_last) < const Duration(milliseconds: 250)) {
        return;
      }
      _last = now;
      _level.value = value.clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final listening = palette.colorFor(AgentState.loading);
    final reduced = _reduced = context.reduceMotion;
    final seconds = widget.elapsed?.inSeconds ?? 0;
    final clock =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      key: const ValueKey('recording-bar'),
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: IrisSpace.sm),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: listening.withValues(alpha: .33),
          width: IrisStroke.hairline,
        ),
      ),
      child: Row(
        children: [
          if (widget.transcribing)
            const SizedBox(width: 44)
          else
            IrisPressable(
              onTap: widget.onCancel,
              semanticLabel: 'Cancel recording',
              child: SizedBox(
                height: 44,
                child: Center(
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: IrisSpace.sm,
                      ),
                      child: Text(
                        'Cancel',
                        style: theme.typography.label.copyWith(
                          color: palette.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (widget.transcribing)
            Semantics(
              label: 'Transcribing',
              excludeSemantics: true,
              child: const IrisOrb(
                state: AgentState.thinking,
                size: 56,
                glow: false,
              ),
            )
          else
            ExcludeSemantics(
              child: ValueListenableBuilder<double>(
                valueListenable: _level,
                builder: (context, level, _) => AnimatedScale(
                  key: const ValueKey('level-orb'),
                  scale: reduced ? 1 : 1 + .15 * level,
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 100),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: reduced
                          ? Border.all(
                              color: listening,
                              width: level < .2
                                  ? 1
                                  : level < .6
                                  ? 2
                                  : 3.5,
                            )
                          : null,
                    ),
                    child: const IrisOrb(
                      state: AgentState.loading,
                      size: 56,
                      glow: false,
                    ),
                  ),
                ),
              ),
            ),
          if (!widget.transcribing) ...[
            const SizedBox(width: IrisSpace.sm),
            Text(
              clock,
              style: theme.typography.codeSmall.copyWith(
                fontSize: 12,
                color: listening,
              ),
            ),
          ],
          const Spacer(),
          if (widget.transcribing)
            const SizedBox(width: 44, height: 44)
          else
            IrisPressable(
              onTap: widget.onStop,
              semanticLabel: 'Stop recording',
              ensureTapTarget: false,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: SendGlyph(
                    SendKind.stop,
                    color: palette.accentInk,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.iris.palette;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Dictate',
      ensureTapTarget: false,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.accentQuiet,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.mic_none, size: 22, color: palette.accent),
      ),
    );
  }
}
