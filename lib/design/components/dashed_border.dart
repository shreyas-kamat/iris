/// A dashed rounded border, for things that are pending or provisional: a
/// steer waiting for its step, an expired prompt.
library;

import 'package:flutter/widgets.dart';

class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    required this.radius,
    this.width = 1,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final BorderRadius radius;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(radius.toRRect(Offset.zero & size));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.width != width;
}
