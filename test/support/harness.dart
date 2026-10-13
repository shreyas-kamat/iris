/// Wraps a widget in the theme and window every Iris screen expects.
library;

import 'package:flutter/material.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';

Widget themed(Widget child) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
  return MediaQuery(
    data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
    child: MaterialApp(
      theme: theme.materialTheme,
      // Above the Navigator, as in the app, so pushed routes get the theme
      // and a Material ancestor too.
      builder: (context, navigator) => IrisTheme(
        data: theme,
        child: Material(type: MaterialType.transparency, child: navigator),
      ),
      home: child,
    ),
  );
}
