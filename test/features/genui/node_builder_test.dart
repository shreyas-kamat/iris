import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/primitives.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
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

Widget _host(
  Widget Function(BuildContext) build, {
  double scale = 1.0,
  bool dark = true,
}) {
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(builder: build),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  String code, {
  NodeEnv env = const NodeEnv(),
  double scale = 1.0,
}) async {
  final root = _tree(code);
  await tester.pumpWidget(
    _host((c) => NodeBuilder(env: env).surface(c, root), scale: scale),
  );
}

const _everything = '''
root = Stack([head, stats, pill, tabs, more, table, list, line, todo, prog, ring, code, diff, md, kv, link, btn, card])
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
''';

void main() {
  group('NodeBuilder', () {
    testWidgets('draws every component of the library without throwing', (
      tester,
    ) async {
      await _pump(tester, _everything);
      expect(tester.takeException(), isNull);
      for (final text in [
        'Cron jobs',
        'RUNNING',
        'HEALTHY',
        'first page',
        'Details',
        'backup',
        '03:00',
        'Deployed',
        'Write tests',
        'Region',
        'eu-west',
        'Docs',
        'Retry',
        'A card',
        'inside',
      ]) {
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
      // An unopened expander and an unselected tab are not in the tree.
      expect(find.text('hidden detail'), findsNothing);
      expect(find.text('second page'), findsNothing);
    });

    for (final dark in [true, false]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'has no overflow at ${scale}x text, ${dark ? 'dark' : 'light'}',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(390, 844));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final root = _tree(_everything);
            await tester.pumpWidget(
              _host(
                (c) => NodeBuilder().surface(c, root),
                scale: scale,
                dark: dark,
              ),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('a tab press shows its page', (tester) async {
      await _pump(tester, _everything);
      await tester.tap(find.text('Log'));
      await tester.pumpAndSettle();
      expect(find.text('second page'), findsOneWidget);
      expect(find.text('first page'), findsNothing);
    });

    testWidgets('an expander opens', (tester) async {
      await _pump(tester, _everything);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('hidden detail'), findsOneWidget);
    });

    testWidgets('a button without an action asks with its label', (
      tester,
    ) async {
      ActionValue? got;
      String? from;
      await _pump(
        tester,
        'root = Button("Retry")',
        env: NodeEnv(
          onAction: (a, c) {
            got = a;
            from = c;
          },
        ),
      );
      await tester.tap(find.text('Retry'));
      expect(from, 'Button');
      final step = got!.steps.single as CustomStep;
      expect(step.name, 'Ask');
      expect(step.params['text'], 'Retry');
    });

    testWidgets('a button runs its own action', (tester) async {
      ActionValue? got;
      await _pump(
        tester,
        'root = Button("Go", @Ask("Tell me more", "ctx"))',
        env: NodeEnv(onAction: (a, c) => got = a),
      );
      await tester.tap(find.text('Go'));
      final step = got!.steps.single as CustomStep;
      expect(step.params['text'], 'Tell me more');
      expect(step.params['context'], 'ctx');
    });

    testWidgets('a button with nowhere to send is disabled', (tester) async {
      await _pump(tester, 'root = Button("Retry")');
      final button = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Retry'), matching: find.byType(Opacity))
            .first,
      );
      expect(button.opacity, lessThan(1));
    });

    testWidgets(
      'a link opens through the host, and is plain text without one',
      (tester) async {
        String? opened;
        await _pump(
          tester,
          'root = Link("Docs", "https://example.com/docs")',
          env: NodeEnv(onOpenUrl: (u) => opened = u),
        );
        await tester.tap(find.text('Docs'));
        expect(opened, 'https://example.com/docs');

        await _pump(tester, 'root = Link("Docs", "https://example.com/docs")');
        expect(find.byType(IrisPressable), findsNothing);
      },
    );

    testWidgets('a link that is not a web address is plain text', (
      tester,
    ) async {
      await _pump(
        tester,
        'root = Link("Open", "file:///etc/passwd")',
        env: NodeEnv(onOpenUrl: (_) => fail('must not open')),
      );
      expect(find.byType(IrisPressable), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('an unknown component becomes a quiet chip, not an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          (c) =>
              const NodeBuilder().build(c, oul.Element('Hologram', 'root', {})),
        ),
      );
      expect(find.byType(IrisCantShow), findsOneWidget);
      expect(find.textContaining('Hologram'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a component missing a required value becomes a chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          (c) => const NodeBuilder().build(c, oul.Element('Text', 'root', {})),
        ),
      );
      expect(find.byType(IrisCantShow), findsOneWidget);
    });

    testWidgets('nesting deeper than the limit stops drawing', (tester) async {
      var node = oul.Element('Text', 'leaf', {'value': 'deep'});
      for (var i = 0; i < 12; i++) {
        node = oul.Element('Stack', 's$i', {
          'children': [
            node,
            oul.Element('Text', 't$i', {'value': 'x'}),
          ],
        });
      }
      await tester.pumpWidget(_host((c) => const NodeBuilder().build(c, node)));
      expect(find.text('deep'), findsNothing);
      expect(find.textContaining('too deep'), findsWidgets);
    });

    testWidgets(
      'a growing surface shows a skeleton, and no root shows a chip when it is not pending',
      (tester) async {
        await tester.pumpWidget(
          _host((c) => const NodeBuilder().surface(c, null, pending: true)),
        );
        expect(find.byType(IrisSurfaceSkeleton), findsOneWidget);
        expect(find.byType(IrisCantShow), findsNothing);

        await tester.pumpWidget(
          _host((c) => const NodeBuilder().surface(c, null)),
        );
        expect(find.byType(IrisCantShow), findsOneWidget);

        final root = _tree('root = Text("hello")');
        await tester.pumpWidget(
          _host((c) => NodeBuilder().surface(c, root, pending: true)),
        );
        expect(find.text('hello'), findsOneWidget);
        expect(find.byType(IrisSurfaceSkeleton), findsOneWidget);
      },
    );

    testWidgets(
      'part of a display that was dropped is flagged below the rest',
      (tester) async {
        final root = _tree('root = Text("hello")');
        await tester.pumpWidget(
          _host((c) => NodeBuilder().surface(c, root, errorCount: 2)),
        );
        expect(find.text('hello'), findsOneWidget);
        expect(find.byType(IrisCantShow), findsOneWidget);
      },
    );

    testWidgets('screen readers get one label per stat, row and checklist item', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        'root = Stack([Stat("Failed", "1", "-1", "down"), ListRow("backup", "03:00", "ok"), ChecklistItem("Ship", true)])',
      );
      expect(find.bySemanticsLabel('Failed, 1, -1, down'), findsOneWidget);
      expect(find.bySemanticsLabel('backup, 03:00, ok'), findsOneWidget);
      expect(find.bySemanticsLabel('Ship, done'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a code block with backticks inside is not cut short', (
      tester,
    ) async {
      await _pump(tester, 'root = CodeBlock("a ``` b", "text")');
      expect(find.textContaining('a ``` b'), findsOneWidget);
    });

    testWidgets('progress is clamped to the bar', (tester) async {
      await _pump(
        tester,
        'root = Stack([Progress(250, "Over"), Progress(-5, "Under")])',
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('Over: 100 percent')), findsWidgets);
    });
  });

  group('lineDiff', () {
    test('marks changed lines and keeps common ones', () {
      expect(lineDiff('a\nb\nc', 'a\nx\nc').map((l) => l.toString()), [
        ' a',
        '-b',
        '+x',
        ' c',
      ]);
    });

    test('handles empty sides', () {
      expect(lineDiff('', 'a').map((l) => l.toString()), ['+a']);
      expect(lineDiff('a', '').map((l) => l.toString()), ['-a']);
      expect(lineDiff('', ''), isEmpty);
    });

    test('very long texts fall back to removed then added', () {
      final before = List.generate(500, (i) => 'a$i').join('\n');
      final out = lineDiff(before, 'z');
      expect(out.first.kind, DiffKind.removed);
      expect(out.last, const DiffLine(DiffKind.added, 'z'));
      expect(out.length, 501);
    });

    test('an insertion in the middle is just an addition', () {
      expect(lineDiff('a\nc', 'a\nb\nc').map((l) => l.toString()), [
        ' a',
        '+b',
        ' c',
      ]);
    });
  });
}
