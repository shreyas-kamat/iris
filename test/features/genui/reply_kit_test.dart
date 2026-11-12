import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/genui/genui_parser.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/genui/reply_kit.dart';

UiSurfaceItem _surface(
  String id, {
  SurfacePlacement placement = SurfacePlacement.replyKit,
  String code = 'root = ApproveReject("Approve", "Hold")',
  int? rev,
}) => UiSurfaceItem(
  id: 'item-$id',
  ref: UiSurfaceRef(surfaceId: id, code: code, placement: placement, rev: rev),
);

Widget _host(Widget child, {bool dark = true, double scale = 1.0}) {
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
        theme: theme.materialTheme,
        home: Material(
          child: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('currentReplyKit', () {
    test('is the newest reply kit', () {
      final items = <TranscriptItem>[
        _surface('a'),
        const AssistantTurn(id: 't', text: 'Which one?'),
        _surface('b'),
      ];
      expect(currentReplyKit(items)!.ref.surfaceId, 'b');
    });

    test('is the kit the assistant sends again after the person replied', () {
      // The model reuses a kit's id for its next question; the new offer must dock, not hide behind the old reply.
      var items = <TranscriptItem>[
        _surface('next', rev: 1),
        const UserTurn(id: 'u', text: 'Alpha'),
        const AssistantTurn(id: 't', text: 'Next?'),
      ];
      items = UiSurfaceItem.add(items, _surface('next', rev: 2));
      expect(currentReplyKit(items)!.ref.rev, 2);
      expect(items.whereType<UiSurfaceItem>(), hasLength(1));
    });

    test('an inline display updated in place keeps its position', () {
      var items = <TranscriptItem>[
        _surface('card', placement: SurfacePlacement.inline),
        const UserTurn(id: 'u', text: 'More'),
      ];
      items = UiSurfaceItem.add(
        items,
        _surface('card', placement: SurfacePlacement.inline, rev: 2),
      );
      expect(items.first, isA<UiSurfaceItem>());
      expect(items.last, isA<UserTurn>());
    });

    test('ignores displays that sit in the transcript', () {
      expect(
        currentReplyKit([_surface('a', placement: SurfacePlacement.inline)]),
        isNull,
      );
    });

    test('is gone once the person has said something after it', () {
      final items = <TranscriptItem>[
        _surface('a'),
        const UserTurn(id: 'u', text: 'Approve'),
      ];
      expect(currentReplyKit(items), isNull);
    });

    test('stays while the assistant keeps talking', () {
      final items = <TranscriptItem>[
        _surface('a'),
        const AssistantTurn(id: 't', text: 'Which one?'),
      ];
      expect(currentReplyKit(items), isNotNull);
    });

    test('an older kit does not come back after a newer one is answered', () {
      final items = <TranscriptItem>[
        _surface('a'),
        _surface('b'),
        const UserTurn(id: 'u', text: 'Hold'),
      ];
      expect(currentReplyKit(items), isNull);
    });

    test('a kit is told apart by its id and revision', () {
      expect(
        replyKitKey(_surface('a', rev: 1)),
        isNot(replyKitKey(_surface('a', rev: 2))),
      );
      expect(
        replyKitKey(_surface('a', rev: 1)),
        replyKitKey(_surface('a', rev: 1)),
      );
    });
  });

  group('ReplyKitDock', () {
    testWidgets('draws the kit and says what it is to a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(ReplyKitDock(item: _surface('a'), onDismiss: () {})),
      );
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Hold'), findsOneWidget);
      expect(find.bySemanticsLabel('Suggested replies'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('can be dismissed', (tester) async {
      final semantics = tester.ensureSemantics();
      var dismissed = 0;
      await tester.pumpWidget(
        _host(ReplyKitDock(item: _surface('a'), onDismiss: () => dismissed++)),
      );
      await tester.tap(find.bySemanticsLabel('Dismiss suggested replies'));
      expect(dismissed, 1);
      semantics.dispose();
    });

    testWidgets('a tap sends the sentence and the hidden block, then goes', (
      tester,
    ) async {
      final sent = <(String, IrisActionEnvelope)>[];
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          ReplyKitDock(
            item: _surface('a'),
            onDismiss: () => dismissed++,
            onUiAction: (t, a) => sent.add((t, a)),
          ),
        ),
      );
      await tester.tap(find.text('Approve'));
      expect(sent, hasLength(1));
      expect(sent.single.$1, 'Approve');
      expect(sent.single.$2.surface, 'a');
      expect(sent.single.$2.component, 'ApproveReject');
      expect(dismissed, 1);
    });

    testWidgets('a kit that only sets state stays put', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          ReplyKitDock(
            item: _surface(
              'a',
              code: r'''
$on = false
root = Stack([Text($on ? "On" : "Off"), Button("Flip", @Set($on, true))])
''',
            ),
            onDismiss: () => dismissed++,
            onUiAction: (t, a) {},
          ),
        ),
      );
      await tester.tap(find.text('Flip'));
      await tester.pump();
      expect(find.text('On'), findsOneWidget);
      expect(dismissed, 0);
    });

    testWidgets('a tall kit is capped, not allowed to push the chat away', (
      tester,
    ) async {
      final rows = [for (var i = 0; i < 30; i++) 'Text("row $i")'].join(', ');
      await tester.pumpWidget(
        _host(
          ReplyKitDock(
            item: _surface('a', code: 'root = Stack([$rows])'),
            onDismiss: () {},
          ),
        ),
      );
      final size = tester.getSize(find.byType(ReplyKitDock));
      expect(size.height, lessThan(320));
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('no overflow at text x$scale', (tester) async {
        await tester.pumpWidget(
          _host(
            ReplyKitDock(
              item: _surface(
                'a',
                code:
                    'root = ApproveReject("Approve it", "Hold off", "Ask me first")',
              ),
              onDismiss: () {},
            ),
            scale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
