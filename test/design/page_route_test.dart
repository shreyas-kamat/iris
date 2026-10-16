/// A sheet opened over a pushed page must not nudge that page sideways: the
/// drift belongs to page pushes only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/sheet.dart';
import 'package:iris/design/platform/platform_feel.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';

void main() {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: false);
  late GlobalKey<NavigatorState> navigator;
  setUp(() => navigator = GlobalKey<NavigatorState>());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: theme.materialTheme,
      builder: (context, child) => IrisTheme(
        data: theme,
        child: Material(type: MaterialType.transparency, child: child),
      ),
      home: const SizedBox(),
    ),
  );

  testWidgets('a sheet over a pushed page leaves the page where it is', (
    tester,
  ) async {
    await pump(tester);
    unawaited(
      navigator.currentState!.push(
        IrisPageRoute<void>(
          builder: (_) => const Align(
            alignment: Alignment.topLeft,
            child: Text('page', key: Key('page')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const Key('page')));

    unawaited(
      showIrisSheet<void>(
        context: navigator.currentContext!,
        builder: (_) => const SizedBox(height: 80, child: Text('sheet')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('page'))), before);
  });

  test('only another page pushes a page aside', () {
    final page = IrisPageRoute<void>(builder: (_) => const SizedBox());
    expect(
      page.canTransitionTo(
        IrisPageRoute<void>(builder: (_) => const SizedBox()),
      ),
      isTrue,
    );
    expect(
      page.canTransitionTo(
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox()),
      ),
      isFalse,
    );
  });
}
