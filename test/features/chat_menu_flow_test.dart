import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/chat_export.dart';
import 'package:iris/features/chat/chat_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;
  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Widget chatScreen(
    FakeChatBackend backend, {
    String conversationId = 'stored-1',
    ChatMenuHooks? menu,
    ShareMarkdown? share,
  }) => themed(
    ChatScreen(
      backend: backend,
      conversationId: conversationId,
      title: 'Heartbeat gaps',
      menu: menu,
      shareMarkdown: share,
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the header has a More button that opens the menu', (
    tester,
  ) async {
    await tester.pumpWidget(chatScreen(backend));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    expect(find.text('Session info'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('without hooks there is no Pin, Archive or Delete', (
    tester,
  ) async {
    await tester.pumpWidget(chatScreen(backend));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('Delete with hooks calls the host and closes the chat', (
    tester,
  ) async {
    // Delete is the last row; a tall surface keeps it on screen.
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var deleted = false;
    await tester.pumpWidget(
      chatScreen(
        backend,
        menu: ChatMenuHooks(
          isPinned: () => false,
          onTogglePin: () {},
          onArchive: () async => true,
          onDelete: () async => deleted = true,
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('Compress calls the backend', (tester) async {
    await tester.pumpWidget(chatScreen(backend));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress'));
    await tester.pumpAndSettle();
    expect(backend.compressions, ['run-1']);
  });

  testWidgets('Session info shows the profile and the session id', (
    tester,
  ) async {
    await tester.pumpWidget(chatScreen(backend));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session info'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('stored-1'), findsOneWidget);
  });

  testWidgets('Export shares the whole transcript as Markdown', (tester) async {
    backend.historyResult = const Ok([
      UserTurn(id: '1', text: 'hi'),
      AssistantTurn(id: '2', text: 'hello'),
    ]);
    String? name;
    String? body;
    await tester.pumpWidget(
      chatScreen(
        backend,
        share: ({required fileName, required title, required markdown}) async {
          name = fileName;
          body = markdown;
        },
      ),
    );
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as Markdown'));
    await tester.pumpAndSettle();
    expect(name, 'heartbeat-gaps.md');
    expect(body, contains('## You'));
    expect(body, contains('hi'));
    expect(body, contains('hello'));
  });
}
