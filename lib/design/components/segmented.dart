/// A row of equal segments with a thumb that slides to the selected one.
library;

import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';

/// Home's Sessions | Scheduled | Tasks, the model sheet's effort track, and the
/// New task column choice.
///
/// At large text the segments wrap onto rows and the selected one is filled in
/// place, because a thumb cannot slide across a layout that has no single row.
class IrisSegmented<T> extends StatelessWidget {
  const IrisSegmented({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.height = 44,
    super.key,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// The least height of a segment.
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final reduced = context.reduceMotion;
    final wide = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final index = values.indexWhere((value) => value == selected);

    final thumb = BoxDecoration(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: palette.lineStrong, width: IrisStroke.hairline),
    );

    Widget segment(T value) {
      final on = value == selected;
      final label = labelOf(value);
      return Semantics(
        button: true,
        selected: on,
        label: '$label${on ? ', selected' : ''}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: Container(
            constraints: BoxConstraints(minHeight: height, minWidth: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: wide && on ? thumb : null,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: type.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: on ? palette.ink : palette.inkMuted,
              ),
            ),
          ),
        ),
      );
    }

    final Widget content;
    if (wide) {
      content = Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [for (final value in values) segment(value)],
      );
    } else {
      final count = values.length;
      content = Stack(
        children: [
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: reduced ? Duration.zero : IrisDurations.normal,
                curve: IrisCurves.standard,
                alignment: Alignment(
                  count == 1 ? 0 : -1 + 2 * index / (count - 1),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    key: const Key('segmented-thumb'),
                    decoration: thumb,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final value in values) Expanded(child: segment(value)),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: content,
    );
  }
}
