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
      home: Material(
        type: MaterialType.transparency,
        child: IrisTheme(data: theme, child: child),
      ),
    ),
  );
}
