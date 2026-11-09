import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/node_builder.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';

/// One program that uses every component in the library (7.3).
const _everything = '''
root = Stack([head, stats, pill, tabs, more, table, list, line, todo, prog, ring, code, diff, md, kv, link, btn, card, charts, form, decide])
head = Text("Cron jobs", "title")
stats = StatRow([Stat("Running", "12", "+2", "up"), Stat("Failed", "1", "-1", "down"), Stat("Idle", "3")])
pill = StatusPill("Healthy", "good")
tabs = Tabs([Tab("Jobs", [Text("first page")]), Tab("Log", [Text("second page")])])
more = Expander("Details", [Text("hidden detail")])
table = Table(["Job", "State"], [["backup", "ok"], ["sync", 3]])
list = Stack([ListRow("backup", "03:00", "ok"), ListRow("sync")])
line = Timeline([TimelineItem("Deployed", "09:00", "by me"), TimelineItem("Rolled back", "09:12")])
todo = Checklist([ChecklistItem("Write tests", true), ChecklistItem("Ship")])
prog = Progress(40, "Disk")
ring = Progress(75, "Quota", "ring")
code = CodeBlock("print('hi')", "python")
diff = Diff("a\\nb", "a\\nc")
md = Markdown("**bold** text")
kv = KeyValue("Region", "eu-west")
link = Link("Docs", "https://example.com/docs")
btn = Button("Retry", null, "primary")
card = Card([Text("inside")], "A card")
charts = Stack([Sparkline([3, 5, 4, 8, 6, 9]), LineChart([Series("Cpu", [1, 3, 2, 5])], ["a", "b", "c", "d"]), BarChart([Series("Jobs", [4, 2, 6])], ["x", "y", "z"]), Donut([Slice("ok", 8), Slice("failed", 2)])])
form = Stack([ChoiceChips(["Daily", "Weekly"], "Daily", false, "Repeat"), Input("Name", "", "Type here"), Slider("Volume", 0, 10, 4, 1), Toggle("Notify", true), DatePicker("Due"), Stepper("Retries", 3, 0, 9, 1)])
decide = Stack([ApproveReject("Approve", "Reject", "Ask"), Submit("Send", Action([@Ask("go")]))])
''';

Widget _host(
  Widget child, {
  required double scale,
  required bool dark,
  double width = 320,
}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
  return IrisTheme(
    data: theme,
    child: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
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
              width: width,
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
  WidgetTester tester, {
  required double scale,
  required bool dark,
  String code = _everything,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      OpenUiView(
        code: code,
        env: NodeEnv(onAsk: (text, context, component) {}),
        maxHeight: 100000,
      ),
      scale: scale,
      dark: dark,
    ),
  );
  await tester.pump();
}

void main() {
  group('accessibility (7.3)', () {
    for (final dark in [true, false]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('every component draws at 200 % text and 320 pt ($mode)', (
        tester,
      ) async {
        await _show(tester, scale: 2.0, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Cron jobs'), findsWidgets);
        expect(find.textContaining('Send'), findsWidgets);
      });

      testWidgets('every component draws at 100 % text and 320 pt ($mode)', (
        tester,
      ) async {
        await _show(tester, scale: 1.0, dark: dark);
        expect(tester.takeException(), isNull);
      });

      testWidgets('labelled tap targets ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        await _show(tester, scale: 1.0, dark: dark);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      // Iris's floor is 44 pt (`IrisSize.minTapTarget`), the iOS guideline. The
      // Android guideline asks for 48 and the whole app is built to 44, so it
      // is not asserted here.
      testWidgets('tap targets are at least 44 pt ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        await _show(tester, scale: 1.0, dark: dark);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('text contrast ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        await _show(tester, scale: 1.0, dark: dark);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
