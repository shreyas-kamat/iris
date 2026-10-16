/// Which image hosts Iris loads without a tap, and how to add one. Provided
/// once at the app root from the person's saved list; absent in tests that
/// do not care, which means "none".
library;

import 'package:flutter/widgets.dart';

class ImageHostScope extends InheritedWidget {
  const ImageHostScope({
    required this.hosts,
    required this.onAllow,
    required super.child,
    super.key,
  });

  final Set<String> hosts;
  final ValueChanged<String> onAllow;

  static ImageHostScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageHostScope>();

  @override
  bool updateShouldNotify(ImageHostScope old) => old.hosts != hosts;
}
