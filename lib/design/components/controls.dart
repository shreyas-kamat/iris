/// Buttons, fields, and the gauge.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/platform_feel.dart';
import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';
import 'aperture.dart';
import 'primitives.dart';

/// How much weight a button carries.
enum IrisButtonTone {
  /// The one thing this screen is for. At most one per view.
  primary,

  /// A real alternative — "Cancel" next to "Send".
  secondary,

  /// Tertiary. Reads as a link that happens to be a button.
  ghost,

  /// Destructive and irreversible. Its colour is the failure hue, not a
  /// decorative red, so it matches the error states elsewhere.
  danger,
}

/// A button.
class IrisButton extends StatelessWidget {
  const IrisButton({
    required this.label,
    this.onPressed,
    this.tone = IrisButtonTone.secondary,
    this.icon,
    this.expand = false,
    this.busy = false,
    super.key,
  });

  final String label;

  /// Null disables the button. There is no separate `enabled` flag: a button
  /// with nothing to do is the same thing as a button with no callback.
  final VoidCallback? onPressed;

  final IrisButtonTone tone;
  final Widget? icon;
  final bool expand;

  /// Shows a working state and blocks input. The label stays visible rather
  /// than being replaced by a spinner, so the button does not change width and
  /// the person can still read what they pressed.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null && !busy;

    final (background, foreground, border) = switch (tone) {
      IrisButtonTone.primary => (palette.accent, palette.accentInk, null),
      IrisButtonTone.secondary => (
        palette.surface,
        palette.ink,
        palette.lineStrong,
      ),
      IrisButtonTone.ghost => (const Color(0x00000000), palette.inkMuted, null),
      IrisButtonTone.danger => (palette.danger, palette.onDanger, null),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // A working button shows the aperture rather than a generic spinner:
        // the same mark means the same thing everywhere in the app, and the
        // label stays put so the button does not change width mid-press.
        if (busy) ...[
          const Aperture(
            state: AgentState.working,
            size: IrisSize.iconSmall,
            semanticLabel: 'Working',
          ),
          const SizedBox(width: IrisSpace.sm),
        ] else if (icon case final icon?) ...[
          IconTheme.merge(
            data: IconThemeData(color: foreground, size: IrisSize.iconSmall),
            child: icon,
          ),
          const SizedBox(width: IrisSpace.sm),
        ],
        Text(
          label,
          style: context.type.heading.copyWith(color: foreground, fontSize: 15),
        ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: IrisPressable(
        onTap: enabled
            ? () {
                // Through the named vocabulary, not HapticFeedback directly, so
                // every button in the app agrees on what a press feels like and
                // a destructive one can be told apart from an ordinary one.
                unawaited(
                  tone == IrisButtonTone.danger
                      ? IrisHaptics.gate()
                      : IrisHaptics.selection(),
                );
                onPressed!.call();
              }
            : null,
        semanticLabel: label,
        // The button already guarantees the minimum height itself, so the
        // pressable must not pad it a second time.
        ensureTapTarget: false,
        child: AnimatedContainer(
          duration: context.reduceMotion ? Duration.zero : IrisDurations.quick,
          curve: IrisCurves.standard,
          // A minimum, not a fixed height. At 200% text scale a fixed 44pt
          // button clips its own label, and someone who has turned text up is
          // exactly the person who cannot then read it.
          constraints: const BoxConstraints(minHeight: IrisSize.control),
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(
            horizontal: IrisSpace.lg,
            vertical: IrisSpace.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.all(IrisRadius.sm),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// A text field.
class IrisField extends StatefulWidget {
  const IrisField({
    this.controller,
    this.hint,
    this.label,
    this.obscure = false,
    this.mono = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.onSubmitted,
    this.autofocus = false,
    this.errorText,
    super.key,
  });

  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final bool obscure;

  /// Sets the value in mono. For URLs, paths, cron expressions and tokens —
  /// anything where character-level accuracy matters more than reading flow.
  final bool mono;

  final int maxLines;

  /// The height it starts at, growing to [maxLines] as text is added. Null
  /// keeps it [maxLines] tall from the start.
  final int? minLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? errorText;

  @override
  State<IrisField> createState() => _IrisFieldState();
}

class _IrisFieldState extends State<IrisField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  /// Only created when the caller did not supply one, and only disposed if we
  /// created it — disposing a controller the caller owns would break the next
  /// widget that uses it.
  TextEditingController? _ownedController;

  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // The hint's visibility depends on the text, so the field rebuilds on every
    // keystroke. Cheap here, and it keeps the hint from lingering under typed
    // characters.
    _controller.addListener(_onTextChange);
  }

  void _onFocusChange() => setState(() => _focused = _focus.hasFocus);

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChange);
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final hasError = widget.errorText != null;
    final borderColor = hasError
        ? palette.colorFor(AgentState.failed)
        : _focused
        ? palette.accent
        : palette.line;
    final textStyle =
        (widget.mono ? theme.typography.code : theme.typography.body).copyWith(
          color: palette.ink,
        );

    return Semantics(
      // EditableText announces its contents but not what it is for. Without
      // this, a screen-reader user reaching the password field hears the value
      // and nothing else.
      //
      // `container` forces a node of its own: without it these properties merge
      // into whatever ancestor node happens to exist, and the field stops being
      // separately reachable.
      container: true,
      textField: true,
      label: widget.label ?? widget.hint,
      hint: widget.label != null ? widget.hint : null,
      obscured: widget.obscure,
      focused: _focused,
      // The error has to be spoken when it appears, not only when the field is
      // re-read, or the person never learns why submission failed.
      liveRegion: hasError,
      value: hasError ? widget.errorText : null,
      child: _buildField(context, theme, palette, borderColor, textStyle),
    );
  }

  Widget _buildField(
    BuildContext context,
    IrisThemeData theme,
    IrisPalette palette,
    Color borderColor,
    TextStyle textStyle,
  ) {
    final hasError = widget.errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label case final label?) ...[
          IrisLabel(label),
          const SizedBox(height: IrisSpace.sm),
        ],
        AnimatedContainer(
          duration: context.reduceMotion ? Duration.zero : IrisDurations.quick,
          curve: IrisCurves.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: IrisSpace.md,
            vertical: IrisSpace.sm,
          ),
          constraints: const BoxConstraints(minHeight: IrisSize.control),
          decoration: BoxDecoration(
            color: palette.surfaceSunken,
            borderRadius: const BorderRadius.all(IrisRadius.sm),
            border: Border.all(
              color: borderColor,
              width: _focused || hasError ? IrisStroke.thick : IrisStroke.thin,
            ),
          ),
          child: Stack(
            children: [
              // EditableText has no decoration layer, so the hint is drawn
              // underneath in the same metrics — which is also why it lines up
              // exactly with the first typed character.
              if (widget.hint case final hint?)
                if (_controller.text.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: widget.maxLines == 1
                            ? Alignment.centerLeft
                            : Alignment.topLeft,
                        child: Text(
                          hint,
                          style: textStyle.copyWith(color: palette.inkFaint),
                        ),
                      ),
                    ),
                  ),
              ExcludeSemantics(
                // The wrapping Semantics node already describes this field;
                // leaving EditableText's own node in place produces two
                // announcements for one control.
                child: EditableText(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscure,
                  maxLines: widget.maxLines,
                  minLines: widget.minLines,
                  keyboardType: widget.keyboardType,
                  onSubmitted: widget.onSubmitted,
                  style: textStyle,
                  cursorColor: palette.accent,
                  backgroundCursorColor: palette.inkFaint,
                  selectionColor: palette.accent.withValues(alpha: 0.28),
                  cursorWidth: 1.5,
                  cursorRadius: const Radius.circular(1),
                ),
              ),
            ],
          ),
        ),
        if (widget.errorText case final error?) ...[
          const SizedBox(height: IrisSpace.xs),
          Text(
            error,
            style: theme.typography.caption.copyWith(
              color: palette.colorFor(AgentState.failed),
            ),
          ),
        ],
      ],
    );
  }
}

/// A fill gauge, for the context window and the cost meter.
///
/// Reads as a thin bar rather than a ring: it lives in a header beside text,
/// where a circle would compete with the aperture. The bar tints toward the
/// failure hue as it fills, so a nearly-full context window is legible without
/// reading the number.
class IrisGauge extends StatelessWidget {
  const IrisGauge({
    required this.value,
    this.label,
    this.width = 56,
    super.key,
  });

  /// Fill from 0 to 1.
  final double value;
  final String? label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clamped = value.clamp(0.0, 1.0);
    // Stays neutral until it matters. A gauge that reddens gradually from zero
    // trains people to ignore it.
    final tint = clamped < 0.7
        ? palette.inkMuted
        : Color.lerp(
            palette.colorFor(AgentState.working),
            palette.colorFor(AgentState.failed),
            ((clamped - 0.7) / 0.3).clamp(0.0, 1.0),
          )!;

    return Semantics(
      label: label == null
          ? '${(clamped * 100).round()} percent'
          : '$label: ${(clamped * 100).round()} percent',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label case final label?) ...[
            IrisLabel(label, small: true),
            const SizedBox(width: IrisSpace.sm),
          ],
          SizedBox(
            width: width,
            // 6pt, not 4: at 4 the bar reads as a hairline rule rather than as
            // a measurement, and the fill level is not legible at a glance.
            height: 6,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(IrisRadius.full),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: palette.surfaceSunken),
                  ),
                  // Positioned rather than a bare FractionallySizedBox: an
                  // unpositioned child in a Stack is centre-aligned and a
                  // ColoredBox has no intrinsic size, so the fill would be
                  // invisible.
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: clamped,
                        heightFactor: 1,
                        child: ColoredBox(color: tint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
