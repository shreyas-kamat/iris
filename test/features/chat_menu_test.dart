import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/chat/chat_menu_sheet.dart';

import '../support/harness.dart';

void main() {
  Future<ChatMenuAction?> open(
    WidgetTester tester, {
    bool replying = false,
    bool live = true,
    bool canPin = true,
    bool canArchive = true,
    bool canDelete = true,
    bool canUndo = true,
    bool pinned = false,
  }) async {
    ChatMenuAction? chosen;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => chosen = await showChatMenu(
                context,
                title: 'Investigate heartbeat gaps',
                pinned: pinned,
                replying: replying,
                live: live,
                canPin: canPin,
                canArchive: canArchive,
                canDelete: canDelete,
                canUndo: canUndo,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('idle: every action is offered, in its group', (tester) async {
    await open(tester);
    for (final label in [
      'Rename',
      'Pin',
      'Branch',
      'Archive',
      'Compress',
      'Undo last turn',
      'Export as Markdown',
      'Session info',
      'Delete',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final group in ['Conversation', 'Context', 'Share', 'Info']) {
      expect(find.bySemanticsLabel(group), findsOneWidget, reason: group);
    }
  });

  testWidgets('a pinned chat offers Unpin', (tester) async {
    await open(tester, pinned: true);
    expect(find.text('Unpin'), findsOneWidget);
    expect(find.text('Pin'), findsNothing);
  });

  testWidgets('rows the host cannot do are left out', (tester) async {
    await open(tester, canPin: false, canArchive: false, canDelete: false);
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('replying: history actions are dimmed and say why', (
    tester,
  ) async {
    await open(tester, replying: true);
    for (final label in [
      'Branch',
      'Archive',
      'Compress',
      'Undo last turn',
      'Delete',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Stop the reply first'), findsNWidgets(5));
    // Rename, Export and Session info still work mid-reply.
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('a dimmed row does not respond to a tap', (tester) async {
    await open(tester, replying: true);
    await tester.tap(find.text('Compress'));
    await tester.pumpAndSettle();
    expect(find.text('Session info'), findsOneWidget, reason: 'still open');
  });

  testWidgets('a chat that is not live cannot be compressed or undone', (
    tester,
  ) async {
    await open(tester, live: false);
    expect(find.text('Not connected yet'), findsNWidgets(2));
  });

  testWidgets('a chat with nothing to undo dims Undo', (tester) async {
    await open(tester, canUndo: false);
    expect(find.text('Nothing to undo'), findsOneWidget);
  });

  testWidgets('tapping an enabled row returns it', (tester) async {
    ChatMenuAction? chosen;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => chosen = await showChatMenu(
                context,
                title: 't',
                pinned: false,
                replying: false,
                live: true,
                canPin: true,
                canArchive: true,
                canDelete: true,
                canUndo: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session info'));
    await tester.pumpAndSettle();
    expect(chosen, ChatMenuAction.info);
  });

  testWidgets('Delete is last', (tester) async {
    await open(tester);
    final delete = tester.getTopLeft(find.text('Delete')).dy;
    for (final label in [
      'Rename',
      'Branch',
      'Session info',
      'Export as Markdown',
    ]) {
      expect(tester.getTopLeft(find.text(label)).dy, lessThan(delete));
    }
  });

  testWidgets('fits at 320 pt wide with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester, replying: true);
    expect(tester.takeException(), isNull);
  });
}
