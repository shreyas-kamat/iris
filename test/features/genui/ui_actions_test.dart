import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/genui/genui_parser.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/render/node_builder.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';
import 'package:iris/features/genui/surface_block.dart';

Widget _host(Widget child) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
  return IrisTheme(
    data: theme,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
      child: MaterialApp(
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

typedef _Ask = (String text, Object? context, String component);

void main() {
  group('OpenUiView runs actions', () {
    testWidgets('@Set and @Reset change the display\'s own variables', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const OpenUiView(
            code: r'''
$n = 1
root = Stack([Text("n=" + $n), Button("Bump", @Set($n, 5)), Button("Back", @Reset($n))])
''',
          ),
        ),
      );
      expect(find.text('n=1'), findsOneWidget);
      await tester.tap(find.text('Bump'));
      await tester.pump();
      expect(find.text('n=5'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('n=1'), findsOneWidget);
    });

    testWidgets('@Set evaluates its value when it is pressed', (tester) async {
      await tester.pumpWidget(
        _host(
          const OpenUiView(
            code: r'''
$a = 2
$b = 0
root = Stack([Input("A", $a, null, "number"), Text("b=" + $b), Button("Copy", @Set($b, $a * 10))])
''',
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), '7');
      await tester.pump();
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(find.text('b=70'), findsOneWidget);
    });

    testWidgets('@Ask goes to the host with its text, context and component', (
      tester,
    ) async {
      final asked = <_Ask>[];
      await tester.pumpWidget(
        _host(
          OpenUiView(
            code: 'root = Button("Go", @Ask("Deploy it", {env: "prod"}))',
            env: NodeEnv(onAsk: (t, c, k) => asked.add((t, c, k))),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      expect(asked, hasLength(1));
      expect(asked.single.$1, 'Deploy it');
      expect(asked.single.$2, equals({'env': 'prod'}));
      expect(asked.single.$3, 'Button');
    });

    testWidgets('a button with no action asks with its label', (tester) async {
      final asked = <_Ask>[];
      await tester.pumpWidget(
        _host(
          OpenUiView(
            code: 'root = Button("Retry")',
            env: NodeEnv(onAsk: (t, c, k) => asked.add((t, c, k))),
          ),
        ),
      );
      await tester.tap(find.text('Retry'));
      expect(asked, [('Retry', null, 'Button')]);
    });

    testWidgets('several steps run in order: set first, then ask', (
      tester,
    ) async {
      final asked = <_Ask>[];
      await tester.pumpWidget(
        _host(
          OpenUiView(
            code: r'''
$n = 1
root = Stack([Text("n=" + $n), Button("Go", Action([@Set($n, 2), @ToAssistant("Done", {n: $n})]))])
''',
            env: NodeEnv(onAsk: (t, c, k) => asked.add((t, c, k))),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(find.text('n=2'), findsOneWidget);
      expect(asked.single.$1, 'Done');
    });

    testWidgets('@OpenUrl goes to the host, which confirms it', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        _host(
          OpenUiView(
            code: 'root = Button("Docs", @OpenUrl("https://example.com/docs"))',
            env: NodeEnv(onOpenUrl: opened.add),
          ),
        ),
      );
      await tester.tap(find.text('Docs'));
      expect(opened, ['https://example.com/docs']);
    });

    testWidgets('a button that only sets state works without a host', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const OpenUiView(
            code: r'''
$on = false
root = Stack([Text($on ? "On" : "Off"), Button("Flip", @Set($on, true))])
''',
          ),
        ),
      );
      await tester.tap(find.text('Flip'));
      await tester.pump();
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('an ask with no host does nothing and does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const OpenUiView(code: 'root = Button("Go", @Ask("hi"))')),
      );
      await tester.tap(find.text('Go'));
      expect(tester.takeException(), isNull);
    });
  });

  group('SurfaceBlock raises a hidden-context action', () {
    UiSurfaceItem item(String code) => UiSurfaceItem(
      id: 'c1',
      ref: UiSurfaceRef(surfaceId: 'deploy', code: code),
    );

    testWidgets('with the display\'s id, the component and the context', (
      tester,
    ) async {
      final sent = <(String, IrisActionEnvelope)>[];
      await tester.pumpWidget(
        _host(
          SurfaceBlock(
            item(r'''
$note = ""
root = Stack([Input("Note", $note), Submit("Send", @Ask("Here is my note", {note: $note}))])
'''),
            onUiAction: (text, action) => sent.add((text, action)),
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), 'ship it');
      await tester.pump();
      await tester.tap(find.text('Send'));
      expect(sent, hasLength(1));
      expect(sent.single.$1, 'Here is my note');
      expect(sent.single.$2.surface, 'deploy');
      expect(sent.single.$2.component, 'Submit');
      expect(sent.single.$2.context, {'note': 'ship it'});
    });

    testWidgets('an approve button names its decision in the context', (
      tester,
    ) async {
      final sent = <(String, IrisActionEnvelope)>[];
      await tester.pumpWidget(
        _host(
          SurfaceBlock(
            item('root = ApproveReject("Approve it", "Hold off")'),
            onUiAction: (text, action) => sent.add((text, action)),
          ),
        ),
      );
      await tester.tap(find.text('Hold off'));
      expect(sent.single.$1, 'Hold off');
      expect(sent.single.$2.component, 'ApproveReject');
      expect(sent.single.$2.context, {'decision': 'reject'});
    });
  });
}
