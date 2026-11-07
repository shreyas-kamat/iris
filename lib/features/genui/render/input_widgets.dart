/// The inputs of the GenUI library (plan 4.2): text, chips, a switch, a slider, a stepper and a date. Each reads and
/// writes one `$variable` in the display's [StateStore] when the program bound one, and keeps its value locally when it
/// did not. They take plain Dart values and know nothing of OpenUI's tree.
///
/// What the person types lives in the store, not in the program, so a new revision of the display (the model updating
/// it) re-parses without touching it: the store never overwrites a value a person wrote.
library;

import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:openui_lang/openui_lang.dart' show StateStore;

import '../../../design/components/controls.dart';
import '../../../design/components/primitives.dart';
import '../../../design/components/sheet.dart';
import '../../../design/platform/platform_feel.dart';
import '../../../design/theme/iris_theme.dart';
import '../../../design/tokens/metrics.dart';

/// A number as a person writes it: no trailing `.0`, at most two decimals.
String formatNumber(num v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
}

/// An ISO date (`2026-11-07`) as a date, or null for anything else.
DateTime? parseIsoDate(Object? v) {
  if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return null;
  final d = DateTime.tryParse(v);
  return d == null || formatIsoDate(d) != v ? null : d;
}

String formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _writtenDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

typedef BoundBuilder =
    Widget Function(
      BuildContext context,
      Object? value,
      ValueChanged<Object?> set,
    );

/// One value that is the store's `$name` when [name] and [store] are given, and this widget's own otherwise. Rebuilds
/// when the store changes, so two inputs bound to the same variable stay in step.
class BoundValue extends StatefulWidget {
  const BoundValue({
    required this.builder,
    this.store,
    this.name,
    this.initial,
    super.key,
  });

  final StateStore? store;

  /// The variable, with its `$`.
  final String? name;

  /// The program's own value, used when nothing is bound.
  final Object? initial;
  final BoundBuilder builder;

  @override
  State<BoundValue> createState() => _BoundValueState();
}

class _BoundValueState extends State<BoundValue> {
  late Object? _local = widget.initial;
  bool _touched = false;
  void Function()? _unlisten;

  bool get _bound => widget.store != null && widget.name != null;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _unlisten?.call();
    _unlisten = _bound
        ? widget.store!.listen(() {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void didUpdateWidget(BoundValue old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store || old.name != widget.name) _listen();
    if (!_bound && !_touched && old.initial != widget.initial) {
      _local = widget.initial;
    }
  }

  @override
  void dispose() {
    _unlisten?.call();
    super.dispose();
  }

  void _set(Object? v) {
    if (_bound) {
      widget.store!.set(widget.name!, v);
    } else {
      setState(() {
        _touched = true;
        _local = v;
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _bound ? widget.store!.get(widget.name!) : _local,
    _set,
  );
}

// -- text ---------------------------------------------------------------------------------------------------------

enum InputKind { text, number, multiline }

class IrisTextInput extends StatefulWidget {
  const IrisTextInput({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.kind = InputKind.text,
    super.key,
  });

  final String label;

  /// A String for text, a num (or null) for a number input.
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? placeholder;
  final InputKind kind;

  @override
  State<IrisTextInput> createState() => _IrisTextInputState();
}

class _IrisTextInputState extends State<IrisTextInput> {
  late final TextEditingController _controller = TextEditingController(
    text: _shown(widget.value),
  );

  String _shown(Object? v) => switch (v) {
    null => '',
    num() => formatNumber(v),
    _ => v.toString(),
  };

  Object? _parse(String text) {
    if (widget.kind != InputKind.number) return text;
    return num.tryParse(text.trim());
  }

  @override
  void didUpdateWidget(IrisTextInput old) {
    super.didUpdateWidget(old);
    // Something else wrote the variable (another input, an action): show it. What was just typed already matches.
    if (_parse(_controller.text) != widget.value &&
        !(widget.value == null && _controller.text.trim().isEmpty)) {
      final text = _shown(widget.value);
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.kind == InputKind.multiline;
    return IrisField(
      controller: _controller,
      label: widget.label,
      hint: widget.placeholder,
      keyboardType: switch (widget.kind) {
        InputKind.number => const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        InputKind.multiline => TextInputType.multiline,
        InputKind.text => TextInputType.text,
      },
      minLines: multiline ? 2 : null,
      maxLines: multiline ? 5 : 1,
      onChanged: (text) => widget.onChanged(
        widget.kind == InputKind.number && text.trim().isEmpty
            ? null
            : _parse(text),
      ),
    );
  }
}

// -- chips ----------------------------------------------------------------------------------------------------------

class IrisChoiceChips extends StatelessWidget {
  const IrisChoiceChips({
    required this.options,
    required this.value,
    required this.onChanged,
    this.multi = false,
    this.label,
    super.key,
  });

  final List<String> options;

  /// A String when single, a list of Strings when [multi].
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool multi;
  final String? label;

  Set<String> get _chosen => switch (value) {
    final String s => {s},
    final List<Object?> l when multi => {for (final x in l) x.toString()},
    _ => const {},
  };

  void _tap(String option) {
    if (!multi) return onChanged(option);
    final chosen = _chosen.toList();
    chosen.contains(option) ? chosen.remove(option) : chosen.add(option);
    // Keep the order the options were written in, whatever order they were tapped.
    onChanged([
      for (final o in options)
        if (chosen.contains(o)) o,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chosen = _chosen;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            ExcludeSemantics(child: IrisLabel(label!, small: true)),
            const SizedBox(height: IrisSpace.xs),
          ],
          Wrap(
            spacing: IrisSpace.sm,
            children: [
              for (final option in options)
                Semantics(
                  button: true,
                  selected: chosen.contains(option),
                  label: chosen.contains(option) ? '$option, selected' : option,
                  onTap: () => _tap(option),
                  excludeSemantics: true,
                  child: IrisPressable(
                    onTap: () => _tap(option),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: chosen.contains(option)
                            ? palette.accentQuiet
                            : palette.surfaceSunken,
                        borderRadius: const BorderRadius.all(IrisRadius.sm),
                        border: Border.all(
                          color: chosen.contains(option)
                              ? palette.accent
                              : palette.line,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: IrisSpace.md,
                          vertical: IrisSpace.sm,
                        ),
                        child: Text(
                          option,
                          style: context.type.body.copyWith(
                            color: chosen.contains(option)
                                ? palette.accent
                                : palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- switch -----------------------------------------------------------------------------------------------------------

class IrisToggleRow extends StatelessWidget {
  const IrisToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        Expanded(
          child: ExcludeSemantics(child: Text(label, style: context.type.body)),
        ),
        const SizedBox(width: IrisSpace.md),
        IrisSwitch(value: value, onChanged: onChanged, semanticLabel: label),
      ],
    ),
  );
}

// -- slider -----------------------------------------------------------------------------------------------------------

class IrisSliderRow extends StatelessWidget {
  const IrisSliderRow({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.step,
    super.key,
  });

  final String label;
  final double min;
  final double max;
  final num? value;
  final ValueChanged<double> onChanged;
  final double? step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final shown = (value ?? min).toDouble().clamp(min, max);
    final divisions = step != null && step! > 0
        ? ((max - min) / step!).round()
        : null;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                Expanded(child: Text(label, style: type.body)),
                Text(
                  formatNumber(shown),
                  style: type.numeric.copyWith(color: palette.inkMuted),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: palette.accent,
              inactiveTrackColor: palette.lineStrong,
              thumbColor: palette.accent,
              overlayColor: palette.accent.withValues(alpha: 0.12),
              trackHeight: 4,
            ),
            child: Slider.adaptive(
              value: shown,
              min: min,
              max: max,
              divisions: divisions != null && divisions > 0 && divisions <= 1000
                  ? divisions
                  : null,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// -- stepper ----------------------------------------------------------------------------------------------------------

class IrisStepperRow extends StatelessWidget {
  const IrisStepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.step = 1,
    super.key,
  });

  final String label;
  final num? value;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;
  final double step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final current = (value ?? min ?? 0).toDouble();
    final canDown = min == null || current - step >= min! - 1e-9;
    final canUp = max == null || current + step <= max! + 1e-9;
    return Row(
      children: [
        Expanded(
          child: ExcludeSemantics(child: Text(label, style: type.body)),
        ),
        const SizedBox(width: IrisSpace.md),
        IrisCircleButton(
          icon: Icons.remove,
          semanticLabel: 'Decrease $label',
          onPressed: canDown ? () => onChanged(current - step) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40),
          child: Text(
            formatNumber(current),
            textAlign: TextAlign.center,
            style: type.numeric.copyWith(color: palette.ink),
          ),
        ),
        IrisCircleButton(
          icon: Icons.add,
          semanticLabel: 'Increase $label',
          onPressed: canUp ? () => onChanged(current + step) : null,
        ),
      ],
    );
  }
}

// -- date -------------------------------------------------------------------------------------------------------------

class IrisDatePickerRow extends StatelessWidget {
  const IrisDatePickerRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;

  /// An ISO date, or anything else for "not chosen".
  final Object? value;
  final ValueChanged<String> onChanged;

  static final _first = DateTime(1900);
  static final _last = DateTime(2100, 12, 31);

  Future<void> _pick(BuildContext context) async {
    final current = parseIsoDate(value) ?? DateTime.now();
    final initial = current.isBefore(_first)
        ? _first
        : current.isAfter(_last)
        ? _last
        : current;
    if (IrisPlatform.of(context) == IrisPlatform.ios) {
      var chosen = initial;
      final done = await showIrisSheet<bool>(
        context: context,
        builder: (context) => IrisSheet(
          title: label,
          actions: IrisSheetActions(
            primary: IrisButton(
              label: 'Done',
              tone: IrisButtonTone.primary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
          child: SizedBox(
            height: 216,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: initial,
              minimumDate: _first,
              maximumDate: _last,
              onDateTimeChanged: (d) => chosen = d,
            ),
          ),
        ),
      );
      if (done ?? false) onChanged(formatIsoDate(chosen));
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _first,
      lastDate: _last,
    );
    if (picked != null) onChanged(formatIsoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final date = parseIsoDate(value);
    final text = date == null ? 'Choose a date' : _writtenDate(date);
    return Semantics(
      button: true,
      label: '$label, $text',
      excludeSemantics: true,
      onTap: () => _pick(context),
      child: IrisPressable(
        onTap: () => _pick(context),
        ensureTapTarget: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: IrisSize.control),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.all(IrisRadius.sm),
              border: Border.all(color: palette.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IrisSpace.md,
                vertical: IrisSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: type.caption.copyWith(color: palette.inkMuted),
                        ),
                        Text(
                          text,
                          style: type.body.copyWith(
                            color: date == null
                                ? palette.inkFaint
                                : palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: IrisSpace.sm),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: IrisSize.iconSmall,
                    color: palette.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
