import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/iris_library.dart';
import 'package:iris/features/genui/render/node_builder.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';
import 'package:openui_lang/openui_lang.dart' hide Element;

Widget _host(Widget child, {double scale = 1.0, bool dark = true}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
  return IrisTheme(
    data: theme,
    child: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        home: Material(
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

Future<void> _show(
  WidgetTester tester,
  String code, {
  NodeEnv env = const NodeEnv(),
  double scale = 1.0,
}) => tester.pumpWidget(
  _host(
    OpenUiView(code: code, env: env, maxHeight: 4000),
    scale: scale,
  ),
);

void main() {
  final lib = IrisLibrary.toLibrarySpec();

  group('library', () {
    test('declares the inputs and marks the bindable props', () {
      List<String> props(String n) => [
        for (final p in lib.components[n]!.props) p.name,
      ];
      List<String> bound(String n) => [
        for (final p in lib.components[n]!.props)
          if (p.bindable) p.name,
      ];
      expect(props('ChoiceChips'), ['options', 'value', 'multi', 'label']);
      expect(props('Input'), ['label', 'value', 'placeholder', 'kind']);
      expect(props('Slider'), ['label', 'min', 'max', 'value', 'step']);
      expect(props('Toggle'), ['label', 'value']);
      expect(props('DatePicker'), ['label', 'value']);
      expect(props('Stepper'), ['label', 'value', 'min', 'max', 'step']);
      expect(props('ApproveReject'), [
        'approveLabel',
        'rejectLabel',
        'askLabel',
      ]);
      expect(props('Submit'), ['label', 'action']);
      for (final n in [
        'ChoiceChips',
        'Input',
        'Slider',
        'Toggle',
        'DatePicker',
        'Stepper',
      ]) {
        expect(bound(n), ['value'], reason: n);
      }
      expect(bound('Button'), isEmpty);
    });

    test('a state variable in a bound slot becomes a binding', () {
      final r = parseProgram(
        lib,
        'root = Stack([Input("Name", \$name)])\n\$name = "Ada"',
      );
      expect(r.errors, isEmpty);
      final input = (r.tree! as UiElement).props['children'] as List;
      expect(
        ((input.single as UiElement).props['value'] as Binding).name,
        r'$name',
      );
    });

    test('the inputs sit in their own group', () {
      expect(
        IrisLibrary.groups.any(
          (g) => g.name == 'Inputs' && g.components.contains('Slider'),
        ),
        isTrue,
      );
    });
  });

  group('Input', () {
    testWidgets('typing updates an expression that reads the variable', (
      tester,
    ) async {
      await _show(tester, '''
\$q = "a"
root = Stack([Input("Search", \$q), Text("You typed " + \$q)])
''');
      expect(find.text('You typed a'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'hello');
      await tester.pump();
      expect(find.text('You typed hello'), findsOneWidget);
    });

    testWidgets('a new revision of the program keeps what was typed', (
      tester,
    ) async {
      await _show(tester, '''
\$q = "a"
root = Stack([Input("Search", \$q), Text("v1 " + \$q)])
''');
      await tester.enterText(find.byType(EditableText), 'typed by me');
      await tester.pump();
      await _show(tester, '''
\$q = "from the model"
root = Stack([Input("Search", \$q), Text("v2 " + \$q)])
''');
      expect(find.text('v2 typed by me'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'typed by me',
      );
    });

    testWidgets('without a variable it still works, locally', (tester) async {
      await _show(tester, 'root = Input("Note", null, "Write here")');
      await tester.enterText(find.byType(EditableText), 'kept');
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'kept',
      );
    });

    testWidgets('a number input stores a number', (tester) async {
      await _show(tester, '''
\$n = 0
root = Stack([Input("Count", \$n, null, "number"), Text("Total " + (\$n + 1))])
''');
      await tester.enterText(find.byType(EditableText), '41');
      await tester.pump();
      expect(find.text('Total 42'), findsOneWidget);
    });

    testWidgets('it is labelled for a screen reader', (tester) async {
      await _show(tester, 'root = Input("Search jobs", null, "name")');
      expect(find.bySemanticsLabel(RegExp('Search jobs')), findsWidgets);
    });
  });

  group('ChoiceChips', () {
    testWidgets('choosing one updates the variable', (tester) async {
      await _show(tester, '''
\$f = "Daily"
root = Stack([ChoiceChips(["Daily", "Weekly", "Monthly"], \$f), Text("Picked " + \$f)])
''');
      expect(find.text('Picked Daily'), findsOneWidget);
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      expect(find.text('Picked Weekly'), findsOneWidget);
    });

    testWidgets('the chosen chip says so to a screen reader', (tester) async {
      await _show(tester, '''
\$f = "Daily"
root = ChoiceChips(["Daily", "Weekly"], \$f)
''');
      expect(find.bySemanticsLabel('Daily, selected'), findsOneWidget);
      expect(find.bySemanticsLabel('Weekly'), findsOneWidget);
    });

    testWidgets('several can be chosen when multi is on', (tester) async {
      await _show(tester, '''
\$f = []
root = Stack([ChoiceChips(["A", "B", "C"], \$f, true), Text("n=" + @Count(\$f))])
''');
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.tap(find.text('C'));
      await tester.pump();
      expect(find.text('n=2'), findsOneWidget);
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(find.text('n=1'), findsOneWidget);
    });
  });

  group('Toggle', () {
    testWidgets('flipping it updates the variable', (tester) async {
      await _show(tester, '''
\$on = false
root = Stack([Toggle("Notify me", \$on), Text(\$on ? "On" : "Off")])
''');
      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Notify me'));
      await tester.pump();
      expect(find.text('On'), findsOneWidget);
    });
  });

  group('Slider', () {
    testWidgets('dragging it changes the variable, within its range', (
      tester,
    ) async {
      await _show(tester, '''
\$v = 10
root = Stack([Slider("Volume", 0, 100, \$v), Text("v=" + \$v)])
''');
      expect(find.text('v=10'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pump();
      expect(find.text('v=10'), findsNothing);
      expect(find.textContaining('v='), findsOneWidget);
    });

    testWidgets('a start outside the range is pulled inside it', (
      tester,
    ) async {
      await _show(tester, 'root = Slider("Level", 0, 10, null, 1)');
      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('an empty range cannot be shown', (tester) async {
      await _show(tester, 'root = Slider("Level", 5, 5)');
      expect(find.byType(Slider), findsNothing);
    });
  });

  group('Stepper', () {
    testWidgets('plus and minus step the variable and stop at the bounds', (
      tester,
    ) async {
      await _show(tester, '''
\$n = 2
root = Stack([Stepper("Guests", \$n, 1, 3), Text("n=" + \$n)])
''');
      await tester.tap(find.bySemanticsLabel('Increase Guests'));
      await tester.pump();
      expect(find.text('n=3'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Increase Guests'));
      await tester.pump();
      expect(find.text('n=3'), findsOneWidget); // at the top
      await tester.tap(find.bySemanticsLabel('Decrease Guests'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Decrease Guests'));
      await tester.pump();
      expect(find.text('n=1'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Decrease Guests'));
      await tester.pump();
      expect(find.text('n=1'), findsOneWidget); // at the bottom
    });
  });

  group('DatePicker', () {
    testWidgets('Android: choosing a day writes an ISO date', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _show(tester, '''
\$d = "2026-11-07"
root = Stack([DatePicker("Due", \$d), Text("d=" + \$d)])
''');
        expect(find.text('d=2026-11-07'), findsOneWidget);
        await tester.tap(find.text('Due'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('15'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('d=2026-11-15'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('iOS: a sheet with a wheel, written on Done', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _show(tester, '''
\$d = "2026-11-07"
root = Stack([DatePicker("Due", \$d), Text("d=" + \$d)])
''');
        await tester.tap(find.text('Due'));
        await tester.pumpAndSettle();
        expect(find.text('Done'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('d=2026-11-07'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a value that is not a date is shown as unset', (tester) async {
      await _show(tester, r'''
$d = "someday"
root = DatePicker("Due", $d)
''');
      expect(find.text('Choose a date'), findsOneWidget);
    });
  });

  group('ApproveReject and Submit', () {
    testWidgets('each button sends its own label with the decision', (
      tester,
    ) async {
      final sent = <(String, Object?, String)>[];
      await _show(
        tester,
        'root = ApproveReject("Approve", "Hold", "Ask me first")',
        env: NodeEnv(onAsk: (t, c, k) => sent.add((t, c, k))),
      );
      for (final label in ['Approve', 'Hold', 'Ask me first']) {
        await tester.tap(find.text(label));
      }
      expect([for (final e in sent) e.$1], ['Approve', 'Hold', 'Ask me first']);
      expect(sent[0].$2, equals({'decision': 'approve'}));
      expect(sent[1].$2, equals({'decision': 'reject'}));
      expect(sent[2].$2, equals({'decision': 'ask'}));
      expect(sent.every((e) => e.$3 == 'ApproveReject'), isTrue);
    });

    testWidgets('without an ask label there are two buttons', (tester) async {
      await _show(
        tester,
        'root = ApproveReject("Yes", "No")',
        env: NodeEnv(onAsk: (t, c, k) {}),
      );
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('Submit runs its action and sees the typed value', (
      tester,
    ) async {
      final sent = <(String, Object?, String)>[];
      await _show(tester, r'''
$note = ""
root = Stack([Input("Note", $note), Submit("Send", @Ask("Here is my note", {note: $note}))])
''', env: NodeEnv(onAsk: (t, c, k) => sent.add((t, c, k))));
      await tester.enterText(find.byType(EditableText), 'ship it');
      await tester.pump();
      await tester.tap(find.text('Send'));
      expect(sent, hasLength(1));
      expect(sent.single.$1, 'Here is my note');
      expect(sent.single.$2, equals({'note': 'ship it'}));
      expect(sent.single.$3, 'Submit');
    });

    testWidgets('buttons are disabled without a host', (tester) async {
      await _show(tester, 'root = Submit("Send", @Ask("x"))');
      expect(tester.takeException(), isNull);
      expect(find.text('Send'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('no overflow at text x$scale', (tester) async {
        await _show(
          tester,
          r'''
$f = "Daily"
$on = true
$v = 30
$n = 2
$d = "2026-11-07"
$q = "hello"
root = Stack([Input("A fairly long label for a field", $q, "placeholder text"), ChoiceChips(["Daily", "Weekly", "Monthly", "Quarterly"], $f), Toggle("Tell me when this is finished", $on), Slider("Volume", 0, 100, $v), Stepper("Guests", $n, 1, 9), DatePicker("Due on", $d), ApproveReject("Approve", "Hold", "Ask me first"), Submit("Send it", @Ask("x"))])
''',
          scale: scale,
          env: NodeEnv(onAsk: (t, c, k) {}),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
