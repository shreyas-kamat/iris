import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/queue_tray.dart';

import '../support/harness.dart';

void main() {
  List<QueuedMessage> items(int n) => [
    for (var i = 0; i < n; i++) QueuedMessage(id: 'q$i', text: 'message $i'),
  ];

  Widget tray(
    List<QueuedMessage> list, {
    bool paused = false,
    void Function(String)? onRemove,
    VoidCallback? onNext,
    VoidCallback? onClear,
  }) => themed(
    Align(
      alignment: Alignment.bottomCenter,
      child: QueueTray(
        items: list,
        paused: paused,
        onRemove: onRemove ?? (_) {},
        onSendNext: onNext ?? () {},
        onClear: onClear ?? () {},
      ),
    ),
  );

  testWidgets('shows each message, numbered, with a remove button', (
    tester,
  ) async {
    String? removed;
    await tester.pumpWidget(tray(items(2), onRemove: (id) => removed = id));
    expect(find.text('message 0'), findsOneWidget);
    expect(find.text('message 1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove message 1'));
    expect(removed, 'q0');
  });

  testWidgets(
    'four or more shows the first two and a +N more row that expands',
    (tester) async {
      await tester.pumpWidget(tray(items(5)));
      expect(find.text('message 0'), findsOneWidget);
      expect(find.text('message 1'), findsOneWidget);
      expect(find.text('message 2'), findsNothing);
      expect(find.text('+3 more'), findsOneWidget);
      await tester.tap(find.text('+3 more'));
      await tester.pumpAndSettle();
      expect(find.text('message 4'), findsOneWidget);
    },
  );

  testWidgets('three items are all shown', (tester) async {
    await tester.pumpWidget(tray(items(3)));
    expect(find.text('message 2'), findsOneWidget);
    expect(find.textContaining('more'), findsNothing);
  });

  testWidgets('paused offers Send next and Clear', (tester) async {
    var next = false;
    var clear = false;
    await tester.pumpWidget(
      tray(
        items(2),
        paused: true,
        onNext: () => next = true,
        onClear: () => clear = true,
      ),
    );
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('Send next'));
    await tester.tap(find.text('Clear'));
    expect(next && clear, isTrue);
  });

  testWidgets('says the messages are held on this phone', (tester) async {
    await tester.pumpWidget(tray(items(1)));
    expect(find.text('Queued messages are held on this phone'), findsOneWidget);
  });
}
