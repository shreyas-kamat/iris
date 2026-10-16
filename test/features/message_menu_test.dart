import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/chat/message_menu.dart';

import '../support/harness.dart';

void main() {
  Future<MessageAction?> open(WidgetTester tester, List<MessageAction> actions) async {
    MessageAction? chosen;
    await tester.pumpWidget(themed(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async => chosen = await showMessageMenu(
          context,
          anchor: const Rect.fromLTWH(40, 300, 300, 80),
          alignEnd: false,
          actions: actions,
        ),
        child: const Text('go'),
      ),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('offers exactly the actions it is given', (tester) async {
    await open(tester, [MessageAction.copy, MessageAction.undo]);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Branch from here'), findsNothing);
  });

  testWidgets('choosing a row returns it', (tester) async {
    MessageAction? chosen;
    await tester.pumpWidget(themed(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async => chosen = await showMessageMenu(
          context,
          anchor: const Rect.fromLTWH(40, 300, 300, 80),
          alignEnd: true,
          actions: [MessageAction.copy, MessageAction.branch],
        ),
        child: const Text('go'),
      ),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Branch from here'));
    await tester.pumpAndSettle();
    expect(chosen, MessageAction.branch);
  });

  testWidgets('a tap on the scrim closes it with no choice', (tester) async {
    MessageAction? chosen = MessageAction.copy;
    await tester.pumpWidget(themed(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async => chosen = await showMessageMenu(
          context,
          anchor: const Rect.fromLTWH(40, 300, 300, 80),
          alignEnd: false,
          actions: [MessageAction.copy],
        ),
        child: const Text('go'),
      ),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });

  testWidgets('the menu flips above the anchor when it would cross the composer', (tester) async {
    await tester.pumpWidget(themed(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () => showMessageMenu(
          context,
          anchor: const Rect.fromLTWH(40, 640, 300, 80),
          alignEnd: false,
          actions: [MessageAction.copy, MessageAction.branch],
        ),
        child: const Text('go'),
      ),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('Copy')).dy, lessThan(640));
  });
}
