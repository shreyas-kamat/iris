/// Font loading for golden tests, shared by every screen that is rendered to
/// an image.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled fonts so goldens show real type rather than Ahem boxes.
///
/// Without this every glyph renders as a filled rectangle and the images are
/// useless for judging typography — which is most of what there is to judge.
Future<void> loadIrisFonts() async {
  await loadMaterialIcons();
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Geist', [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
  ]);
  await load('GeistMono', [
    'GeistMono-Regular.ttf',
    'GeistMono-Medium.ttf',
  ]);
  // Both faces go into one family, because FontLoader cannot declare a style.
  // The italic face is what the serif role actually draws with.
  await load('InstrumentSerif', [
    'InstrumentSerif-Regular.ttf',
    'InstrumentSerif-Italic.ttf',
  ]);
}

/// Loads Material's icon font so `Icon` draws glyphs rather than empty boxes.
///
/// The app gets this font from its build (`uses-material-design`), but the test
/// bundle does not include it. The file is vendored under `test/fonts` rather
/// than read from the SDK, because an SDK path differs from one machine to the
/// next and goldens must not.
Future<void> loadMaterialIcons() async {
  final loader = FontLoader('MaterialIcons');
  final bytes = await File('test/fonts/MaterialIcons-Regular.otf').readAsBytes();
  loader.addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}
