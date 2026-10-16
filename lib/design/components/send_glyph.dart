/// The glyphs of the composer's one action: send, queue, steer, interrupt
/// and stop.
///
/// Drawn rather than taken from the icon font because the four busy-mode
/// glyphs must be told apart at a glance and must avoid two existing
/// meanings: steer must not look like "branch" (so it is one stroke with a
/// turn and no nodes) and interrupt must not look like "undo" (so it points
/// up and breaks a bar). All use a 2.4 stroke on a 24 grid.
library;

import 'package:flutter/widgets.dart';

import '../../data/chat/chat_models.dart';

enum SendKind {
  send('Send'),
  queue('Queue'),
  steer('Steer'),
  interrupt('Interrupt'),
  stop('Stop');

  const SendKind(this.semanticLabel);

  final String semanticLabel;

  static SendKind forMode(BusyMode mode) => switch (mode) {
    BusyMode.queue => queue,
    BusyMode.steer => steer,
    BusyMode.interrupt => interrupt,
  };
}

class SendGlyph extends StatelessWidget {
  const SendGlyph(this.kind, {required this.color, this.size = 24, super.key});

  final SendKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _GlyphPainter(kind, color)),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final SendKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path chevron(double x, double y, double reach) => Path()
      ..moveTo(x - reach, y + reach)
      ..lineTo(x, y)
      ..lineTo(x + reach, y + reach);
    switch (kind) {
      case SendKind.send:
        canvas
          ..drawLine(const Offset(12, 19), const Offset(12, 5), line)
          ..drawPath(chevron(12, 5, 6), line);
      case SendKind.queue:
        // An arrow onto a stack of two lines.
        canvas
          ..drawLine(const Offset(12, 13), const Offset(12, 4), line)
          ..drawPath(chevron(12, 4, 5), line)
          ..drawLine(const Offset(5, 17), const Offset(19, 17), line)
          ..drawLine(const Offset(7.5, 21), const Offset(16.5, 21), line);
      case SendKind.steer:
        // One stroke that bends and ends in an arrowhead.
        canvas
          ..drawPath(
            Path()
              ..moveTo(7, 20)
              ..lineTo(7, 12)
              ..quadraticBezierTo(7, 7, 12, 7)
              ..lineTo(18, 7),
            line,
          )
          ..drawPath(
            Path()
              ..moveTo(14.5, 3.5)
              ..lineTo(18, 7)
              ..lineTo(14.5, 10.5),
            line,
          );
      case SendKind.interrupt:
        // An arrow that points up and breaks a bar.
        canvas
          ..drawLine(const Offset(12, 16), const Offset(12, 4), line)
          ..drawPath(chevron(12, 4, 5.5), line)
          ..drawLine(const Offset(4, 20), const Offset(9, 20), line)
          ..drawLine(const Offset(15, 20), const Offset(20, 20), line);
      case SendKind.stop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(6.5, 6.5, 11, 11),
            const Radius.circular(2.5),
          ),
          Paint()..color = color,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color;
}
