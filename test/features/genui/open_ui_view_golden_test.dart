/// Every component of the v1 library, rendered light and dark. Like the design gallery these are meant to be looked
/// at: run with `--update-goldens`, then open the PNGs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/node_builder.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';

import '../../support/fonts.dart';

const _layout = '''
root = Stack([title, card, section, tabs, more, rule, tail])
title = Text("Layout", "title")
card = Card([Text("Cards hold one idea each."), StatusPill("Healthy", "good")], "A card")
section = Section("A section", [KeyValue("Region", "eu-west"), KeyValue("Plan", "Pro")])
tabs = Tabs([Tab("Overview", [Text("The first page of the tabs.")]), Tab("Details", [Text("The second.")])])
more = Expander("An expander, open", [Text("Detail most people will not need.")], true)
rule = Divider()
tail = Stack([Text("A row of pills", "caption"), row], "column", "s")
row = Stack([StatusPill("Neutral"), StatusPill("Good", "good"), StatusPill("Warn", "warn"), StatusPill("Bad", "bad")], "row", "s")
''';

const _data = '''
root = Stack([head, stats, table, rows, md])
head = Text("Text and data", "title")
stats = StatRow([Stat("Running", "12", "+2", "up"), Stat("Failed", "1", "-1", "down"), Stat("Idle", "3", "no change", "flat")])
table = Table(["Job", "Last run", "State"], [["backup", "03:00", "ok"], ["sync", "04:30", "failed"], ["report", "06:00", "ok"]])
rows = Card([ListRow("backup", "Nightly", "ok"), ListRow("sync", "Every 6 hours", "failed"), ListRow("report")], "Jobs")
md = Markdown("Some **bold**, some `code` and a [link](https://example.com).")
''';

const _more = '''
root = Stack([head, line, todo, bar, ring, code, diff, kv, link, btn])
head = Text("Timeline, progress, code", "title")
line = Timeline([TimelineItem("Deployed", "09:00", "by me"), TimelineItem("Health check failed", "09:08"), TimelineItem("Rolled back", "09:12", "to v41")])
todo = Checklist([ChecklistItem("Write the tests", true), ChecklistItem("Fix the bug", true), ChecklistItem("Ship it")])
bar = Progress(@Percent(3, 4), "Disk used")
ring = Progress(40, "Quota", "ring")
code = CodeBlock("def hello():\n    return 'hi'", "python")
diff = Diff("name = old\nsame line\nremoved", "name = new\nsame line\nadded")
kv = KeyValue("Spent", @Money(1234.5, "GBP"))
link = Link("Read the docs", "https://example.com/docs")
btn = Button("Try again", null, "primary")
''';

const _charts = '''
root = Stack([head, spark, line, bar, donut])
head = Text("Charts", "title")
spark = Card([Text("Requests this week", "caption"), Sparkline([12, 15, 11, 18, 22, 19, 27])], "Sparkline")
line = Card([LineChart([Series("Requests", [10, 14, 9, 20, 18, 26, 24]), Series("Errors", [1, 0, 2, 1, 4, 2, 1])], ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])], "Line chart")
bar = Card([BarChart([Series("Revenue", [120, 90, 150, -20]), Series("Costs", [80, 85, 90, 60])], ["Q1", "Q2", "Q3", "Q4"])], "Bar chart")
donut = Card([Donut([Slice("Docs", 40), Slice("Code", 35), Slice("Chat", 20), Slice("Other", 0.5)])], "Donut")
''';

Widget _host(String code, {required bool dark}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: dark);
  return MediaQuery(
    data: const MediaQueryData(size: Size(390, 1200), disableAnimations: true),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme,
      home: Material(
        color: theme.palette.canvas,
        child: IrisTheme(
          data: theme,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: ColoredBox(
                  color: theme.palette.canvas,
                  child: OpenUiView(
                    code: code,
                    maxHeight: 4000,
                    now: () => DateTime.utc(2026, 11, 7, 12),
                    env: NodeEnv(onAction: (a, c) {}, onOpenUrl: (u) {}),
                  ),
                ),
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

  for (final entry in {
    'layout': _layout,
    'data': _data,
    'more': _more,
    'charts': _charts,
  }.entries) {
    for (final dark in [true, false]) {
      testWidgets('${entry.key}, ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(entry.value, dark: dark));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byKey(const ValueKey('shot')),
          matchesGoldenFile(
            'goldens/genui_${entry.key}_${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    }
  }
}
