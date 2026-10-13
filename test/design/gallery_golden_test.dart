/// Renders the design gallery to images.
///
/// These are goldens in the regression sense, but their first job is to be
/// *looked at*: a design system is judged by eye, and a build that only proves
/// "no exceptions thrown" proves nothing about whether the thing is any good.
/// Run with `--update-goldens` to regenerate, then open the PNGs.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/design_gallery/design_gallery.dart';

/// Loads the bundled fonts so goldens show real type rather than Ahem boxes.
///
/// Without this every glyph renders as a filled rectangle and the images are
/// useless for judging typography — which is most of what there is to judge.
Future<void> loadIrisFonts() async {
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
}

/// Wraps the gallery with the theme it is being captured in.
Widget harness({required IrisSkin skin, required bool isDark}) {
  final theme = IrisThemeData(skin: skin, isDark: isDark);
  return ProviderScope(
    overrides: [
      themeControllerProvider.overrideWith(
        () => _FixedTheme(ThemePreference(
          skin: skin,
          mode: isDark ? BrightnessMode.dark : BrightnessMode.light,
        )),
      ),
    ],
    child: MediaQuery(
      // Animations are disabled so the aperture and skeletons land on a stable
      // frame; otherwise every run captures a different point in the breath.
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        home: Material(
          type: MaterialType.transparency,
          child: IrisTheme(data: theme, child: const DesignGallery()),
        ),
      ),
    ),
  );
}

class _FixedTheme extends ThemeController {
  _FixedTheme(this._value);
  final ThemePreference _value;
  @override
  ThemePreference build() => _value;
}

void main() {
  setUpAll(loadIrisFonts);

  /// Tall enough that the whole gallery renders in one image rather than only
  /// the top of the scroll view.
  const surface = Size(430, 3400);

  Future<void> capture(
    WidgetTester tester,
    IrisSkin skin, {
    required bool isDark,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(skin: skin, isDark: isDark));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(DesignGallery),
      matchesGoldenFile(
        'goldens/gallery_${skin.name}_${isDark ? 'dark' : 'light'}.png',
      ),
    );
  }

  // The default skin in both brightnesses — the primary review surface.
  testWidgets('aperture dark', (t) => capture(t, IrisSkin.aperture, isDark: true));
  testWidgets('aperture light', (t) => capture(t, IrisSkin.aperture, isDark: false));

  // A spread across the hue range, to catch a skin whose accent collapses
  // against its own neutrals.
  testWidgets('mono dark', (t) => capture(t, IrisSkin.mono, isDark: true));
  testWidgets('ares dark', (t) => capture(t, IrisSkin.ares, isDark: true));
  testWidgets('poseidon dark', (t) => capture(t, IrisSkin.poseidon, isDark: true));
  testWidgets('sienna light', (t) => capture(t, IrisSkin.sienna, isDark: false));
  testWidgets('contrast light', (t) => capture(t, IrisSkin.contrast, isDark: false));
}
