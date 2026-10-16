// lib/design/components/math.dart
/// TeX, typeset. `flutter_math_fork` lays it out in Dart with bundled KaTeX
/// fonts: no WebView and no CDN. TeX that doesn't parse, often half-written
/// while a reply streams, shows as its source in code type.
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import 'tex_support.dart';

class IrisMath extends StatelessWidget {
  const IrisMath(
    this.tex, {
    required this.display,
    required this.style,
    super.key,
  });

  final String tex;

  /// A block of its own: larger, centred and scrollable sideways.
  final bool display;

  /// The text around it, whose size and colour the maths takes.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final math = Math.tex(
      prepareTex(tex),
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style,
      settings: TexParserSettings(macros: irisTexMacros),
      onErrorFallback: (_) => Text(
        display ? tex : '\$$tex\$',
        style: context.type.code.copyWith(
          fontSize: (style.fontSize ?? 16) * 0.9,
          color: context.palette.inkMuted,
        ),
      ),
    );
    if (!display) return math;
    return _DisplayMath(child: math);
  }
}

/// A display equation in its own well: sunken, hairline, scrolling sideways.
/// A long one fades over its last 36 points while there is more to the right.
class _DisplayMath extends StatefulWidget {
  const _DisplayMath({required this.child});

  final Widget child;

  @override
  State<_DisplayMath> createState() => _DisplayMathState();
}

class _DisplayMathState extends State<_DisplayMath> {
  bool _more = false;

  bool _measure(ScrollMetrics metrics) {
    final more = metrics.maxScrollExtent - metrics.pixels > 1;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget scroll = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _measure(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _measure(n.metrics),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
    if (_more) {
      scroll = ShaderMask(
        key: const ValueKey('math-fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, (1 - 36 / bounds.width).clamp(0.0, 1.0), 1],
        ).createShader(bounds),
        child: scroll,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: Center(child: scroll),
    );
  }
}
