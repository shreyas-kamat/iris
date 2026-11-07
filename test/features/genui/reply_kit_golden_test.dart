/// The reply-kit dock in both themes, as it sits above the composer. Meant to be looked at: run with
/// `--update-goldens`, then open the PNGs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/reply_kit.dart';

import '../../support/fonts.dart';

UiSurfaceItem _kit(String code) => UiSurfaceItem(
  id: 'k',
  ref: UiSurfaceRef(
    surfaceId: 'k',
    code: code,
    placement: SurfacePlacement.replyKit,
  ),
);

const _kits = {
  'decision':
      'root = ApproveReject("Approve the deploy", "Hold it", "Ask me first")',
  'choices':
      'root = Stack([Text("Which environment?", "caption"), ChoiceChips(["Staging", "Production", "Both"], null)])',
};

Widget _host(Widget child, {required bool dark}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
  return IrisTheme(
    data: theme,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(390, 200), disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        home: Material(
          color: theme.palette.canvas,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: ColoredBox(color: theme.palette.canvas, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadIrisFonts);

  for (final entry in _kits.entries) {
    for (final dark in [true, false]) {
      testWidgets('${entry.key}, ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(390, 200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 358,
              child: ReplyKitDock(item: _kit(entry.value), onDismiss: () {}),
            ),
            dark: dark,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byKey(const ValueKey('shot')),
          matchesGoldenFile(
            'goldens/reply_kit_${entry.key}_${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    }
  }
}
