/// Widgets the node builder needs that hold state or paint something of their own. They know nothing of OpenUI: they
/// take plain Dart values.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/components/primitives.dart';
import '../../../design/components/segmented.dart';
import '../../../design/theme/iris_theme.dart';
import '../../../design/tokens/metrics.dart';
import '../../../design/tokens/motion.dart';
import '../../../design/tokens/palette.dart';

/// Switches between pages by label. The chosen page is local state and never reaches the server.
class IrisTabsView extends StatefulWidget {
  const IrisTabsView({required this.labels, required this.pages, super.key})
    : assert(labels.length == pages.length);

  final List<String> labels;
  final List<Widget> pages;

  @override
  State<IrisTabsView> createState() => _IrisTabsViewState();
}

class _IrisTabsViewState extends State<IrisTabsView> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    final index = math.min(_index, widget.pages.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.pages.length > 1)
          IrisSegmented<int>(
            values: List.generate(widget.pages.length, (i) => i),
            selected: index,
            labelOf: (i) => widget.labels[i],
            onChanged: (i) => setState(() => _index = i),
            height: IrisSize.controlSmall,
          ),
        if (widget.pages.length > 1) const SizedBox(height: IrisSpace.md),
        KeyedSubtree(key: ValueKey(index), child: widget.pages[index]),
      ],
    );
  }
}

/// A title that opens to reveal its content.
class IrisExpanderView extends StatefulWidget {
  const IrisExpanderView({
    required this.title,
    required this.child,
    this.initiallyOpen = false,
    super.key,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<IrisExpanderView> createState() => _IrisExpanderViewState();
}

class _IrisExpanderViewState extends State<IrisExpanderView> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: _open,
          child: IrisPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: widget.title,
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(widget.title, style: context.type.heading),
                  ),
                ),
                ExcludeSemantics(
                  child: AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: context.reduceMotion
                        ? Duration.zero
                        : IrisDurations.quick,
                    child: Icon(
                      Icons.expand_more,
                      size: IrisSize.icon,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        IrisAnimatedSize(
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: IrisSpace.sm),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// How a line changed between two versions of a text.
enum DiffKind { same, removed, added }

class DiffLine {
  const DiffLine(this.kind, this.text);
  final DiffKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffLine && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() =>
      '${switch (kind) {
        DiffKind.same => ' ',
        DiffKind.removed => '-',
        DiffKind.added => '+',
      }}$text';
}

/// A line diff by longest common subsequence. Texts past [limit] lines are shown as all removed then all added, which
/// is honest and bounded (the table is quadratic).
List<DiffLine> lineDiff(String before, String after, {int limit = 400}) {
  final a = before.isEmpty ? <String>[] : before.split('\n');
  final b = after.isEmpty ? <String>[] : after.split('\n');
  if (a.length > limit || b.length > limit) {
    return [
      for (final l in a) DiffLine(DiffKind.removed, l),
      for (final l in b) DiffLine(DiffKind.added, l),
    ];
  }
  final table = List.generate(
    a.length + 1,
    (_) => List.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : math.max(table[i + 1][j], table[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffKind.same, a[i]));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      out.add(DiffLine(DiffKind.removed, a[i++]));
    } else {
      out.add(DiffLine(DiffKind.added, b[j++]));
    }
  }
  while (i < a.length) {
    out.add(DiffLine(DiffKind.removed, a[i++]));
  }
  while (j < b.length) {
    out.add(DiffLine(DiffKind.added, b[j++]));
  }
  return out;
}

class IrisDiffView extends StatelessWidget {
  const IrisDiffView({required this.before, required this.after, super.key});

  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = context.type.codeSmall;
    final lines = lineDiff(before, after);
    final removed = palette.colorFor(AgentState.failed);
    final added = palette.colorFor(AgentState.done);
    final changed = lines.where((l) => l.kind != DiffKind.same).length;

    return Semantics(
      container: true,
      label: changed == 0 ? 'No changes' : '$changed changed lines',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSunken,
          borderRadius: const BorderRadius.all(IrisRadius.sm),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(IrisRadius.sm),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Semantics(
                    label: switch (line.kind) {
                      DiffKind.same => line.text,
                      DiffKind.removed => 'Removed: ${line.text}',
                      DiffKind.added => 'Added: ${line.text}',
                    },
                    excludeSemantics: true,
                    child: ColoredBox(
                      color: switch (line.kind) {
                        DiffKind.same => const Color(0x00000000),
                        DiffKind.removed => removed.withValues(alpha: 0.14),
                        DiffKind.added => added.withValues(alpha: 0.14),
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: IrisSpace.md,
                          vertical: 1,
                        ),
                        child: Text(
                          '${switch (line.kind) {
                            DiffKind.same => '  ',
                            DiffKind.removed => '- ',
                            DiffKind.added => '+ ',
                          }}${line.text}',
                          style: style.copyWith(
                            color: switch (line.kind) {
                              DiffKind.same => palette.inkMuted,
                              DiffKind.removed => removed,
                              DiffKind.added => added,
                            },
                          ),
                        ),
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

/// One event on a timeline: a dot on a line, then the words.
class IrisTimelineRow extends StatelessWidget {
  const IrisTimelineRow({
    required this.title,
    this.time,
    this.detail,
    this.first = false,
    this.last = false,
    super.key,
  });

  final String title;
  final String? time;
  final String? detail;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Semantics(
      container: true,
      label: [?time, title, ?detail].join(', '),
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 20,
              child: CustomPaint(
                painter: _RailPainter(
                  color: palette.lineStrong,
                  dot: palette.accent,
                  first: first,
                  last: last,
                ),
              ),
            ),
            const SizedBox(width: IrisSpace.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: IrisSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (time != null)
                      Text(
                        time!,
                        style: type.caption.copyWith(color: palette.inkMuted),
                      ),
                    Text(title, style: type.body),
                    if (detail != null)
                      Text(
                        detail!,
                        style: type.caption.copyWith(color: palette.inkMuted),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.color,
    required this.dot,
    required this.first,
    required this.last,
  });

  final Color color;
  final Color dot;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const dotY = 10.0;
    final line = Paint()
      ..color = color
      ..strokeWidth = IrisStroke.thin;
    if (!first) canvas.drawLine(Offset(x, 0), Offset(x, dotY), line);
    if (!last) canvas.drawLine(Offset(x, dotY), Offset(x, size.height), line);
    canvas.drawCircle(Offset(x, dotY), 4, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color ||
      old.dot != dot ||
      old.first != first ||
      old.last != last;
}

/// A placeholder in the shape of a small display, for a surface that is still arriving.
class IrisSurfaceSkeleton extends StatelessWidget {
  const IrisSurfaceSkeleton({this.rows = 3, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading display',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IrisSkeleton(width: 140, height: 16),
          for (var i = 0; i < rows; i++) ...[
            const SizedBox(height: IrisSpace.sm),
            IrisSkeleton(height: 12, width: i.isEven ? double.infinity : 220),
          ],
        ],
      ),
    );
  }
}

/// What stands in for a part that cannot be shown. Quiet: the reply's text already says the same thing.
class IrisCantShow extends StatelessWidget {
  const IrisCantShow({this.what, super.key});

  final String? what;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = what == null
        ? 'Can’t show this part'
        : 'Can’t show this part ($what)';
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSunken,
          borderRadius: const BorderRadius.all(IrisRadius.xs),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IrisSpace.sm,
            vertical: IrisSpace.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: IrisSize.iconSmall,
                color: palette.inkFaint,
              ),
              const SizedBox(width: IrisSpace.xs),
              Flexible(
                child: Text(
                  text,
                  style: context.type.caption.copyWith(color: palette.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
