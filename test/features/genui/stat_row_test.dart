import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';

/// Found on a phone at 320 pt: a row of three stats cut "Unknown" into "Unkno" and "wn".
const _program = '''
root = Stack([card])
card = Card([StatRow([Stat("Build", "Unknown"), Stat("Services", "Unknown"), Stat("Deploy", "Unknown")])], "Deploy status")
''';

Future<void> _show(WidgetTester tester, double width, String code) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: false);
  await tester.pumpWidget(
    IrisTheme(
      data: theme,
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 844), disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme,
          home: Material(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OpenUiView(code: code, maxHeight: 100000),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Whether [text] was laid out on more than one line.
bool _wraps(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text).first);
  final lineHeight = paragraph.text.style?.fontSize ?? 14;
  return paragraph.size.height > lineHeight * 2;
}

const _short = '''
root = Stack([card])
card = Card([StatRow([Stat("Build", "12"), Stat("Services", "3"), Stat("Deploy", "40")])], "Deploy status")
''';

void main() {
  testWidgets('a stat value never breaks inside a word at 320 pt', (
    tester,
  ) async {
    await _show(tester, 320, _program);
    expect(tester.takeException(), isNull);
    for (final value in tester.widgetList<Text>(find.text('Unknown'))) {
      expect(value.data, 'Unknown');
    }
    expect(find.text('Unknown'), findsNWidgets(3));
    expect(_wraps(tester, 'Unknown'), isFalse);
  });

  testWidgets('three short stats still sit side by side on a wide screen', (
    tester,
  ) async {
    await _show(tester, 420, _short);
    final tops = {
      for (final e
          in find
              .byType(Text)
              .evaluate()
              .where(
                (e) =>
                    const ['12', '3', '40'].contains((e.widget as Text).data),
              ))
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(tops, hasLength(1));
  });
}
