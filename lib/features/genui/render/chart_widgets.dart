/// The charts of the GenUI library (plan 4.1): a sparkline, a line chart, a bar chart and a donut, drawn with painters on
/// the Iris tokens. They take plain Dart numbers and know nothing of OpenUI; the node builder cleans what the model
/// wrote (text among the numbers, too many points) with [cleanValues] before anything reaches a painter.
///
/// Colour is state in Iris, so a chart uses the accent for its first series and turns that hue for the others. Every
/// series is also named in a legend, and every chart reads out its figures to a screen reader.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/theme/iris_theme.dart';
import '../../../design/tokens/metrics.dart';
import '../../../design/tokens/palette.dart';

/// Points drawn per series. More than this carries no extra meaning at phone width.
const kMaxPoints = 200;

/// Series on one chart.
const kMaxSeries = 4;

/// Slices on a donut.
const kMaxSlices = 12;

/// The numbers among [raw], in order: text, null, booleans, NaN and infinities are skipped, and at most [kMaxPoints]
/// are kept.
List<double> cleanValues(List<Object?> raw) {
  final out = <double>[];
  for (final v in raw) {
    if (v is num && v.isFinite) {
      out.add(v.toDouble());
      if (out.length == kMaxPoints) break;
    }
  }
  return out;
}

/// A value for an axis or a read-out: whole numbers plain, one decimal otherwise, thousands as `k`, millions as `M`.
String formatChartValue(double v) {
  String trim(double x, int digits) {
    final s = x.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
  }

  final a = v.abs();
  if (a >= 1e6) return '${trim(v / 1e6, 1)}M';
  if (a >= 1e3) return '${trim(v / 1e3, 1)}k';
  return trim(v, a == a.roundToDouble() ? 0 : 1);
}

/// What a screen reader hears for one series. [name] is left out when the chart has a single unnamed series.
String describeSeries(String? name, List<double> values) {
  final n = values.length;
  final count = '$n point${n == 1 ? '' : 's'}';
  final prefix = name == null ? '' : '$name: ';
  if (n == 1) return '$prefix$count, ${formatChartValue(values.first)}';
  final low = values.reduce(math.min);
  final high = values.reduce(math.max);
  return '$prefix$count, from ${formatChartValue(values.first)} to '
      '${formatChartValue(values.last)}, low ${formatChartValue(low)}, '
      'high ${formatChartValue(high)}';
}

/// The value range a plot spans. Never empty: a flat series gets a range around its value.
class ChartRange {
  const ChartRange(this.min, this.max);

  factory ChartRange.of(List<List<double>> series, {bool includeZero = false}) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final s in series) {
      for (final v in s) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (lo == double.infinity) return const ChartRange(0, 1);
    if (includeZero) {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    if (hi == lo) {
      final pad = hi == 0 ? 1.0 : hi.abs() * 0.1;
      return includeZero && lo == 0
          ? ChartRange(0, pad)
          : ChartRange(lo - pad, hi + pad);
    }
    return ChartRange(lo, hi);
  }

  final double min;
  final double max;
  double get span => max - min;

  /// 0 at [min], 1 at [max].
  double fraction(double v) => (v - min) / span;
}

/// One named line or set of bars.
class ChartSeries {
  const ChartSeries(this.name, this.values);
  final String name;
  final List<double> values;
}

/// One slice of a donut.
class ChartSlice {
  const ChartSlice(this.label, this.value);
  final String label;
  final double value;
}

/// [n] colours for series or slices: the accent first, then that hue turned round the wheel.
List<Color> chartColors(IrisPalette palette, int n) {
  final base = HSLColor.fromColor(palette.accent);
  final step = n <= 4 ? 80.0 : 360.0 / n;
  return [
    for (var i = 0; i < n; i++)
      i == 0
          ? palette.accent
          : base.withHue((base.hue + step * i) % 360).toColor(),
  ];
}

double _measure(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

/// Indexes of the labels to show so that they cannot collide: every label when they fit, otherwise every nth one from
/// the first. [pitch] is the distance between neighbouring labels and [slot] the width one label needs.
List<int> labelSlots(int count, double pitch, double slot) {
  if (count == 0) return const [];
  final step = math.max(1, (slot / math.max(pitch, 1)).ceil());
  return [for (var i = 0; i < count; i += step) i];
}

// -- sparkline ------------------------------------------------------------------------------------------------------

/// A small line with no axes, for a trend inside a sentence-sized space.
class IrisSparkline extends StatelessWidget {
  const IrisSparkline({required this.values, this.height = 36, super.key});

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Trend, ${describeSeries(null, values)}',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.hasBoundedWidth ? math.min(box.maxWidth, 240) : 96,
          height: height,
          child: CustomPaint(
            painter: _LinePainter(
              series: [values],
              colors: [palette.accent],
              range: ChartRange.of([values]),
              grid: const [],
              gridColor: palette.line,
              strokeWidth: 2,
              pad: 4,
            ),
          ),
        ),
      ),
    );
  }
}

// -- line and bar charts --------------------------------------------------------------------------------------------

/// Two or more series as lines over shared labels.
class IrisLineChart extends StatelessWidget {
  const IrisLineChart({
    required this.series,
    this.labels = const [],
    super.key,
  });

  final List<ChartSeries> series;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => _AxisChart(
    kind: 'Line chart',
    series: series,
    labels: labels,
    bars: false,
  );
}

/// Series as grouped bars over shared labels. The baseline is always zero.
class IrisBarChart extends StatelessWidget {
  const IrisBarChart({required this.series, this.labels = const [], super.key});

  final List<ChartSeries> series;
  final List<String> labels;

  @override
  Widget build(BuildContext context) =>
      _AxisChart(kind: 'Bar chart', series: series, labels: labels, bars: true);
}

class _AxisChart extends StatelessWidget {
  const _AxisChart({
    required this.kind,
    required this.series,
    required this.labels,
    required this.bars,
  });

  final String kind;
  final List<ChartSeries> series;
  final List<String> labels;
  final bool bars;

  static const _plotHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final caption = context.type.caption.copyWith(color: palette.inkMuted);
    final colors = chartColors(palette, series.length);
    final values = [for (final s in series) s.values];
    final range = ChartRange.of(values, includeZero: bars);
    final count = values.map((v) => v.length).reduce(math.max);
    final top = formatChartValue(range.max);
    final bottom = formatChartValue(range.min);
    final label =
        '$kind, ${series.length} series. '
        '${[for (final s in series) describeSeries(s.name, s.values)].join('. ')}';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final width = box.hasBoundedWidth ? box.maxWidth : 280.0;
              final gutter =
                  math.max(
                    _measure(context, top, caption),
                    _measure(context, bottom, caption),
                  ) +
                  IrisSpace.sm;
              final plot = math.max(40.0, width - gutter);
              final slot = math.max(48.0, _measure(context, 'Wwwww', caption));
              final pitch = bars
                  ? plot / count
                  : count == 1
                  ? plot
                  : plot / (count - 1);
              final shown = labelSlots(
                math.min(count, labels.length),
                pitch,
                slot,
              );
              // Where each label's centre sits across the plot.
              double centre(int i) => bars
                  ? (i + 0.5) / count * plot
                  : count == 1
                  ? plot / 2
                  : i / (count - 1) * plot;
              final step = shown.length > 1 ? shown[1] - shown[0] : 1;
              final slotWidth = math.min(plot, pitch * step);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: _plotHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: gutter,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(top, style: caption, maxLines: 1),
                              Text(bottom, style: caption, maxLines: 1),
                            ],
                          ),
                        ),
                        Expanded(
                          child: CustomPaint(
                            painter: bars
                                ? _BarPainter(
                                    series: values,
                                    colors: colors,
                                    range: range,
                                    gridColor: palette.line,
                                  )
                                : _LinePainter(
                                    series: values,
                                    colors: colors,
                                    range: range,
                                    grid: const [0, 1],
                                    gridColor: palette.line,
                                    strokeWidth: 2,
                                    pad: 4,
                                    dots: true,
                                    surface: palette.surface,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (shown.isNotEmpty) ...[
                    const SizedBox(height: IrisSpace.xs),
                    Padding(
                      padding: EdgeInsets.only(left: gutter),
                      child: SizedBox(
                        height:
                            caption.fontSize! *
                            1.4 *
                            MediaQuery.textScalerOf(context).scale(1),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final i in shown)
                              Positioned(
                                left: (centre(i) - slotWidth / 2).clamp(
                                  0.0,
                                  math.max(0.0, plot - slotWidth),
                                ),
                                width: slotWidth,
                                child: Text(
                                  labels[i],
                                  style: caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  // A label pushed in from an edge leans toward the point it names.
                                  textAlign: centre(i) - slotWidth / 2 < 0
                                      ? TextAlign.left
                                      : centre(i) + slotWidth / 2 > plot
                                      ? TextAlign.right
                                      : TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (series.length > 1) ...[
            const SizedBox(height: IrisSpace.sm),
            Wrap(
              spacing: IrisSpace.md,
              runSpacing: IrisSpace.xs,
              children: [
                for (var i = 0; i < series.length; i++)
                  _LegendEntry(color: colors[i], label: series[i].name),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(IrisRadius.xs),
          ),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: IrisSpace.xs),
        Flexible(
          child: Text(
            label,
            style: type.caption.copyWith(color: palette.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.colors,
    required this.range,
    required this.grid,
    required this.gridColor,
    required this.strokeWidth,
    required this.pad,
    this.dots = false,
    this.surface,
  });

  final List<List<double>> series;
  final List<Color> colors;
  final ChartRange range;

  /// Fractions (0 bottom, 1 top) at which to draw a hairline.
  final List<double> grid;
  final Color gridColor;
  final double strokeWidth;
  final double pad;
  final bool dots;
  final Color? surface;

  @override
  void paint(Canvas canvas, Size size) {
    final inner = Rect.fromLTWH(
      pad,
      pad,
      math.max(0, size.width - pad * 2),
      math.max(0, size.height - pad * 2),
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = IrisStroke.hairline;
    for (final g in grid) {
      final y = inner.bottom - g * inner.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final n = series.map((s) => s.length).fold(0, math.max);
    for (var s = 0; s < series.length; s++) {
      final values = series[s];
      if (values.isEmpty) continue;
      Offset at(int i) => Offset(
        n == 1 ? inner.center.dx : inner.left + i / (n - 1) * inner.width,
        inner.bottom - range.fraction(values[i]) * inner.height,
      );
      final paint = Paint()
        ..color = colors[s]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (values.length > 1) {
        final path = Path()..moveTo(at(0).dx, at(0).dy);
        for (var i = 1; i < values.length; i++) {
          path.lineTo(at(i).dx, at(i).dy);
        }
        canvas.drawPath(path, paint);
      }
      // The last point, ringed in the surface colour so it stands off the line.
      final end = at(values.length - 1);
      if (dots || values.length == 1) {
        if (surface != null) {
          canvas.drawCircle(end, 4.5, Paint()..color = surface!);
        }
        canvas.drawCircle(end, 3, Paint()..color = colors[s]);
      } else {
        canvas.drawCircle(end, 2.5, Paint()..color = colors[s]);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.series != series ||
      old.colors != colors ||
      old.range.min != range.min ||
      old.range.max != range.max ||
      old.gridColor != gridColor;
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.series,
    required this.colors,
    required this.range,
    required this.gridColor,
  });

  final List<List<double>> series;
  final List<Color> colors;
  final ChartRange range;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final zeroY = size.height - range.fraction(0) * size.height;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = gridColor
        ..strokeWidth = IrisStroke.thin,
    );
    final n = series.map((s) => s.length).fold(0, math.max);
    if (n == 0) return;
    final group = size.width / n;
    final inset = group * 0.15;
    final bar = (group - inset * 2) / series.length;
    for (var s = 0; s < series.length; s++) {
      for (var i = 0; i < series[s].length; i++) {
        final y = size.height - range.fraction(series[s][i]) * size.height;
        final left = i * group + inset + s * bar;
        final rect = Rect.fromLTRB(
          left + 1,
          math.min(y, zeroY),
          left + bar - 1,
          math.max(y, zeroY).clamp(0.0, size.height),
        );
        if (rect.height < 1) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left, zeroY - 0.5, rect.width, 1),
            Paint()..color = colors[s],
          );
          continue;
        }
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: series[s][i] >= 0 ? const Radius.circular(3) : Radius.zero,
            topRight: series[s][i] >= 0
                ? const Radius.circular(3)
                : Radius.zero,
            bottomLeft: series[s][i] < 0
                ? const Radius.circular(3)
                : Radius.zero,
            bottomRight: series[s][i] < 0
                ? const Radius.circular(3)
                : Radius.zero,
          ),
          Paint()..color = colors[s],
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.series != series ||
      old.colors != colors ||
      old.range.min != range.min ||
      old.range.max != range.max ||
      old.gridColor != gridColor;
}

// -- donut ----------------------------------------------------------------------------------------------------------

/// Shares of a whole as a ring with a legend. Slices that are zero or negative never reach this widget.
class IrisDonut extends StatelessWidget {
  const IrisDonut({required this.slices, super.key});

  final List<ChartSlice> slices;

  static String share(double value, double total) {
    final pct = value / total * 100;
    return pct > 0 && pct < 1 ? '<1%' : '${pct.round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    final colors = chartColors(palette, slices.length);
    final label =
        'Donut chart, ${slices.length} slice${slices.length == 1 ? '' : 's'}: '
        '${[for (final s in slices) '${s.label} ${share(s.value, total)}'].join(', ')}';
    final ring = SizedBox.square(
      dimension: 96,
      child: CustomPaint(
        painter: _DonutPainter(
          fractions: [for (final s in slices) s.value / total],
          colors: colors,
          track: palette.lineStrong,
        ),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IrisSpace.xxs),
            child: Row(
              children: [
                Expanded(
                  child: _LegendEntry(color: colors[i], label: slices[i].label),
                ),
                const SizedBox(width: IrisSpace.sm),
                Text(
                  share(slices[i].value, total),
                  style: context.type.numeric.copyWith(color: palette.inkMuted),
                ),
              ],
            ),
          ),
      ],
    );
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ring,
                const SizedBox(height: IrisSpace.md),
                legend,
              ],
            )
          : Row(
              children: [
                ring,
                const SizedBox(width: IrisSpace.lg),
                Expanded(child: legend),
              ],
            ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.fractions,
    required this.colors,
    required this.track,
  });

  final List<double> fractions;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    // A hairline gap between slices, unless one slice is the whole ring.
    final gap = fractions.length > 1 ? 0.04 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = math.pi * 2 * fractions[i];
      final drawn = math.max(0.0, sweep - gap);
      if (drawn > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          drawn,
          false,
          paint..color = colors[i],
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fractions != fractions || old.colors != colors || old.track != track;
}
