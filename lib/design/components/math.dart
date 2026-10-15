// lib/design/components/math.dart
/// TeX, typeset. `flutter_math_fork` lays it out in Dart with bundled KaTeX
/// fonts: no WebView and no CDN. TeX that doesn't parse, often half-written
/// while a reply streams, shows as its source in code type.
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/iris_theme.dart';
import 'tex_support.dart';

class IrisMath extends StatelessWidget {
  const IrisMath(this.tex, {required this.display, required this.style, super.key});

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
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: math,
      ),
    );
  }
}
