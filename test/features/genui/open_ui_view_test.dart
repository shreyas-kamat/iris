import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/node_builder.dart';
import 'package:iris/features/genui/render/node_widgets.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';

Widget _host(Widget child, {double width = 390}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 844), disableAnimations: true),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme,
      home: Material(
        child: IrisTheme(
          data: theme,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a whole program', (tester) async {
    await tester.pumpWidget(
      _host(
        const OpenUiView(
          code:
              'root = Stack([Text("Cron jobs", "title"), KeyValue("Region", "eu-west")])',
        ),
      ),
    );
    expect(find.text('Cron jobs'), findsOneWidget);
    expect(find.text('eu-west'), findsOneWidget);
    expect(find.byType(IrisSurfaceSkeleton), findsNothing);
  });

  testWidgets('a growing program shows a skeleton first, then fills in', (
    tester,
  ) async {
    Future<void> show(String code, {required bool streaming}) =>
        tester.pumpWidget(_host(OpenUiView(code: code, streaming: streaming)));

    await show('', streaming: true);
    expect(find.byType(IrisSurfaceSkeleton), findsOneWidget);

    await show('root = Stack([a, b])\na = Text("first")\n', streaming: true);
    expect(find.text('first'), findsOneWidget);
    expect(
      find.byType(IrisSurfaceSkeleton),
      findsOneWidget,
    ); // b has not arrived

    await show(
      'root = Stack([a, b])\na = Text("first")\nb = Text("second")\n',
      streaming: false,
    );
    expect(find.text('second'), findsOneWidget);
    expect(find.byType(IrisSurfaceSkeleton), findsNothing);
  });

  testWidgets('a program that cannot be shown falls back to the reply text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const OpenUiView(
          code: 'this is not a program',
          fallback: 'Plain **answer**',
        ),
      ),
    );
    expect(find.textContaining('answer'), findsOneWidget);
    expect(find.byType(IrisCantShow), findsNothing);
  });

  testWidgets('without fallback text it shows the quiet chip', (tester) async {
    await tester.pumpWidget(_host(const OpenUiView(code: '')));
    expect(find.byType(IrisCantShow), findsOneWidget);
  });

  testWidgets('a program with a bad part still shows the rest and says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const OpenUiView(code: 'root = Stack([Text("kept"), Hologram("x")])'),
      ),
    );
    expect(find.text('kept'), findsOneWidget);
    expect(find.byType(IrisCantShow), findsOneWidget);
  });

  testWidgets('functions run: percent, money and relative time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        OpenUiView(
          code:
              'root = Stack([Progress(@Percent(1, 4), "Done"), Text(@Money(5, "GBP")), Text(@Ago("2026-11-07T09:00:00Z"))])',
          now: () => DateTime.utc(2026, 11, 7, 12),
        ),
      ),
    );
    expect(find.text('£5.00'), findsOneWidget);
    expect(find.text('3 hours ago'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Done: 25 percent')), findsWidgets);
  });

  group('tall displays', () {
    final rows = List.generate(40, (i) => 'ListRow("row $i")').join(', ');
    final tall = 'root = Stack([$rows, Text("the very end")])';

    testWidgets('are cut with a Show all that reveals the rest', (
      tester,
    ) async {
      await tester.pumpWidget(_host(OpenUiView(code: tall, maxHeight: 200)));
      await tester.pump();
      await tester.pump();
      expect(find.text('SHOW ALL'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SingleChildScrollView).last).height,
        200,
      );

      await tester.tap(find.text('SHOW ALL'));
      await tester.pump();
      await tester.pump();
      expect(find.text('SHOW LESS'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SingleChildScrollView).last).height,
        greaterThan(400),
      );
    });

    testWidgets('short ones have no button', (tester) async {
      await tester.pumpWidget(
        _host(const OpenUiView(code: 'root = Text("short")', maxHeight: 200)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('SHOW ALL'), findsNothing);
    });

    testWidgets('opening one keeps the page chosen in its tabs', (
      tester,
    ) async {
      final body = List.generate(40, (i) => 'ListRow("row $i")').join(', ');
      final code =
          'root = Tabs([Tab("One", [Text("page one")]), Tab("Two", [Stack([$body])])])';
      await tester.pumpWidget(_host(OpenUiView(code: code, maxHeight: 200)));
      await tester.tap(find.text('Two'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('SHOW ALL'));
      await tester.pump();
      await tester.pump();
      expect(find.text('page one'), findsNothing);
      expect(find.text('row 0'), findsOneWidget);
    });
  });

  testWidgets('the same program delivered again keeps the chosen tab', (
    tester,
  ) async {
    Widget view(String code) => _host(OpenUiView(code: code));
    const tabs =
        'root = Tabs([Tab("A", [Text("one")]), Tab("B", [Text("two")])])';
    await tester.pumpWidget(view(tabs));
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(find.text('two'), findsOneWidget);

    // Same program re-delivered (as a reconnect does): the view is not rebuilt from scratch.
    await tester.pumpWidget(view(tabs));
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('an action from a button reaches the host', (tester) async {
    String? from;
    await tester.pumpWidget(
      _host(
        OpenUiView(
          code: 'root = Button("More")',
          env: NodeEnv(onAction: (a, c) => from = c),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    expect(from, 'Button');
  });
}
