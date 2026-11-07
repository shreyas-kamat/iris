import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/chart_widgets.dart';
import 'package:iris/features/genui/render/iris_library.dart';
import 'package:iris/features/genui/render/node_builder.dart';
import 'package:iris/features/genui/render/node_widgets.dart';
import 'package:openui_lang/openui_lang.dart' hide Element;
import 'package:openui_lang/openui_lang.dart' as oul show Element;

final _lib = IrisLibrary.toLibrarySpec();

oul.Element? _tree(String code) {
  final result = parseProgram(_lib, code);
  expect(result.errors, isEmpty, reason: code);
  return Evaluator(result, _lib).evaluateRoot().root;
}

Widget _host(Widget child, {double scale = 1.0, bool dark = true}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(390, 844),
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme,
      home: Material(
        child: IrisTheme(
          data: theme,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  String code, {
  double scale = 1.0,
  bool dark = true,
}) async {
  final root = _tree(code);
  await tester.pumpWidget(
    _host(
      Builder(builder: (c) => const NodeBuilder().surface(c, root)),
      scale: scale,
      dark: dark,
    ),
  );
}

const _spark = 'root = Sparkline([3, 5, 4, 8, 6, 9])';
const _line = '''
root = LineChart([a, b], ["Mon", "Tue", "Wed", "Thu", "Fri"])
a = Series("Requests", [10, 14, 9, 20, 18])
b = Series("Errors", [1, 0, 2, 1, 4])
''';
const _bar = '''
root = BarChart([a], ["Q1", "Q2", "Q3", "Q4"])
a = Series("Revenue", [120, 90, 150, -20])
''';
const _donut = '''
root = Donut([Slice("Docs", 40), Slice("Code", 35), Slice("Chat", 25)])
''';

void main() {
  group('library', () {
    test('declares the chart components with the spec\'s prop order', () {
      List<String> props(String name) => [
        for (final p in _lib.components[name]!.props) p.name,
      ];
      expect(props('Sparkline'), ['values']);
      expect(props('Series'), ['name', 'values']);
      expect(props('LineChart'), ['series', 'labels']);
      expect(props('BarChart'), ['series', 'labels']);
      expect(props('Donut'), ['slices']);
      expect(props('Slice'), ['label', 'value']);
    });

    test('the charts sit in their own group', () {
      expect(
        IrisLibrary.groups.any(
          (g) => g.components.contains('LineChart') && g.name == 'Charts',
        ),
        isTrue,
      );
    });
  });

  group('chart maths', () {
    test('keeps numbers only and caps the point count', () {
      expect(cleanValues([1, 'x', null, 2.5, true, double.nan]), [1, 2.5]);
      expect(cleanValues(List.generate(500, (i) => i)).length, kMaxPoints);
    });

    test('formats values compactly', () {
      expect(formatChartValue(0), '0');
      expect(formatChartValue(12), '12');
      expect(formatChartValue(12.5), '12.5');
      expect(formatChartValue(12.345), '12.3');
      expect(formatChartValue(1500), '1.5k');
      expect(formatChartValue(2000000), '2M');
      expect(formatChartValue(-1500), '-1.5k');
    });

    test('a flat series still gets a range', () {
      final r = ChartRange.of([
        [5, 5, 5],
      ]);
      expect(r.max > r.min, isTrue);
    });

    test('bars always include zero', () {
      final r = ChartRange.of([
        [50, 80],
      ], includeZero: true);
      expect(r.min, 0);
      expect(r.max, greaterThanOrEqualTo(80));
    });

    test('the summary names the lowest and highest values', () {
      expect(
        describeSeries('Requests', [10, 14, 9, 20, 18]),
        'Requests: 5 points, from 10 to 18, low 9, high 20',
      );
      expect(describeSeries(null, [4]), '1 point, 4');
    });
  });

  group('rendering', () {
    testWidgets('a sparkline paints and reads out its range', (tester) async {
      await _pump(tester, _spark);
      expect(find.byType(IrisSparkline), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Trend, 6 points, from 3 to 9')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a line chart shows its legend and axis labels', (
      tester,
    ) async {
      await _pump(tester, _line);
      expect(find.byType(IrisLineChart), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Line chart, 2 series.*Requests: 5')),
        findsOneWidget,
      );
    });

    testWidgets('a bar chart handles a negative value', (tester) async {
      await _pump(tester, _bar);
      expect(find.byType(IrisBarChart), findsOneWidget);
      expect(find.text('Q4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut lists each slice with its share', (tester) async {
      await _pump(tester, _donut);
      expect(find.byType(IrisDonut), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('35%'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Donut chart, 3 slices.*Docs 40%')),
        findsOneWidget,
      );
    });

    for (final dark in [true, false]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow (dark: $dark, text x$scale)', (tester) async {
          for (final code in [_spark, _line, _bar, _donut]) {
            await _pump(tester, code, scale: scale, dark: dark);
            expect(tester.takeException(), isNull, reason: code);
          }
        });
      }
    }

    testWidgets('a chart in a narrow row does not need unbounded width', (
      tester,
    ) async {
      await _pump(tester, '''
root = Stack([Sparkline([1, 2, 3]), Sparkline([3, 2, 1])], "row")
''');
      expect(find.byType(IrisSparkline), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('odd data', () {
    testWidgets('a chart with nothing to draw says so quietly', (tester) async {
      await _pump(tester, 'root = Sparkline([])');
      expect(find.byType(IrisCantShow), findsOneWidget);
      await _pump(tester, 'root = LineChart([Series("x", [1])])');
      expect(find.byType(IrisCantShow), findsOneWidget);
      await _pump(tester, 'root = Donut([Slice("a", 0), Slice("b", -3)])');
      expect(find.byType(IrisCantShow), findsOneWidget);
    });

    testWidgets('more than four series draws the first four', (tester) async {
      await _pump(tester, '''
root = LineChart([s1, s2, s3, s4, s5])
s1 = Series("A", [1, 2])
s2 = Series("B", [2, 3])
s3 = Series("C", [3, 4])
s4 = Series("D", [4, 5])
s5 = Series("E", [5, 6])
''');
      expect(find.text('D'), findsOneWidget);
      expect(find.text('E'), findsNothing);
    });

    testWidgets('a long label list is thinned so it cannot collide', (
      tester,
    ) async {
      final labels = [for (var i = 1; i <= 24; i++) '"Label $i"'].join(', ');
      final values = List.generate(24, (i) => i * 2).join(', ');
      await _pump(
        tester,
        'root = LineChart([Series("x", [$values])], [$labels])',
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Label').evaluate().length,
        lessThanOrEqualTo(6),
      );
    });
  });
}
