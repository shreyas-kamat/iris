/// Displays report what happens to them (plan 6.1): seen for two seconds, opened in full, dismissed, or marked not
/// useful from a long press.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/genui/signals.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/reply_kit.dart';
import 'package:iris/features/genui/surface_block.dart';

UiSurfaceItem _surface(
  String id, {
  String code = 'root = Text("Hello")',
  String? template,
  SurfacePlacement placement = SurfacePlacement.inline,
}) => UiSurfaceItem(
  id: 'item-$id',
  ref: UiSurfaceRef(
    surfaceId: id,
    code: code,
    template: template,
    placement: placement,
  ),
);

Widget _host(Widget child) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
  return IrisTheme(
    data: theme,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(390, 600), disableAnimations: true),
      child: MaterialApp(
        theme: theme.materialTheme,
        home: Material(child: child),
      ),
    ),
  );
}

class _Seen {
  final signals = <(DisplaySignal, String?, String?)>[];

  void call(DisplaySignal signal, {String? surface, String? template}) =>
      signals.add((signal, surface, template));

  List<DisplaySignal> get names => [for (final (s, _, _) in signals) s];
}

void main() {
  late _Seen seen;
  setUp(() => seen = _Seen());

  group('used', () {
    testWidgets('is sent once after two seconds in view', (tester) async {
      await tester.pumpWidget(
        _host(
          SurfaceBlock(_surface('s1', template: 'deploy'), onSignal: seen.call),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      expect(seen.signals, isEmpty);

      await tester.pump(const Duration(milliseconds: 750));
      expect(seen.signals, [(DisplaySignal.used, 's1', 'deploy')]);

      await tester.pump(const Duration(seconds: 10));
      expect(seen.signals, hasLength(1));
    });

    testWidgets('waits until the display is scrolled into view', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          ListView(
            controller: controller,
            children: [
              const SizedBox(height: 700),
              SurfaceBlock(_surface('s1'), onSignal: seen.call),
              const SizedBox(height: 900),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(seen.signals, isEmpty, reason: 'it is below the screen');

      controller.jumpTo(600);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2500));
      expect(seen.names, [DisplaySignal.used]);
    });

    testWidgets('starts over when it is scrolled away', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          ListView(
            controller: controller,
            children: [
              SurfaceBlock(_surface('s1'), onSignal: seen.call),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1250));
      controller.jumpTo(1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(seen.signals, isEmpty);

      controller.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1250));
      expect(seen.signals, isEmpty, reason: 'the earlier time does not count');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(seen.names, [DisplaySignal.used]);
    });

    testWidgets('does not count time with the app in the background', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(SurfaceBlock(_surface('s1'), onSignal: seen.call)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(seen.signals, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2500));
      expect(seen.names, [DisplaySignal.used]);
    });

    testWidgets('is silent without a listener', (tester) async {
      await tester.pumpWidget(_host(SurfaceBlock(_surface('s1'))));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  });

  group('expanded', () {
    testWidgets('is sent when "Show all" is opened', (tester) async {
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: SurfaceBlock(
              _surface(
                's1',
                code:
                    'root = Stack([Text("one"), Text("two"), Text("three"), Text("four"), Text("five")])',
              ),
              maxHeight: 40,
              onSignal: seen.call,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('SHOW ALL'));
      await tester.pump();
      expect(seen.signals, [(DisplaySignal.expanded, 's1', null)]);

      // Closing it again is not news.
      await tester.tap(find.text('SHOW LESS'));
      await tester.pump();
      expect(seen.names, [DisplaySignal.expanded]);
    });
  });

  group('not useful', () {
    testWidgets('a long press offers it, and choosing it is sent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(Center(child: SurfaceBlock(_surface('s1'), onSignal: seen.call))),
      );
      await tester.pump();
      await tester.longPress(find.text('Hello'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Not useful'), findsOneWidget);
      expect(seen.signals, isEmpty);

      await tester.tap(find.text('Not useful'));
      await tester.pumpAndSettle();
      expect(seen.signals, [(DisplaySignal.notUseful, 's1', null)]);
      expect(find.text('Not useful'), findsNothing, reason: 'the sheet closed');
    });

    testWidgets('closing the sheet sends nothing', (tester) async {
      await tester.pumpWidget(
        _host(Center(child: SurfaceBlock(_surface('s1'), onSignal: seen.call))),
      );
      await tester.pump();
      await tester.longPress(find.text('Hello'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen.signals, isEmpty);
    });

    testWidgets('there is no menu without a listener', (tester) async {
      await tester.pumpWidget(
        _host(Center(child: SurfaceBlock(_surface('s1')))),
      );
      await tester.pump();
      await tester.longPress(find.text('Hello'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Not useful'), findsNothing);
    });
  });

  group('dismissed', () {
    testWidgets('is sent when a reply kit is closed', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.bottomCenter,
            child: ReplyKitDock(
              item: _surface(
                'kit',
                code: 'root = ApproveReject("Approve", "Hold")',
                placement: SurfacePlacement.replyKit,
              ),
              onDismiss: () => closed++,
              onSignal: seen.call,
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Dismiss suggested replies'));
      await tester.pump();
      expect(closed, 1);
      expect(seen.signals, [(DisplaySignal.dismissed, 'kit', null)]);
    });
  });
}
