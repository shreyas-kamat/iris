/// A chat opened from a notification: its button is applied once the chat is open, and the app learns which chat is on
/// screen so a notification for it can be left out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/push_providers.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/push/push_intents.dart';
import 'package:iris/features/chat/chat_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

const _approval = ApprovalRequest(
  sessionId: 'run-1',
  command: 'rm -rf build',
  description: 'Run a command',
  choices: ['once', 'session', 'always', 'deny'],
  queueId: 'q1',
);

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Approve once from a notification answers and says so', (
    tester,
  ) async {
    backend.pendingApprovalList = [_approval];
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          pushTap: const PushTap(
            kind: 'approval',
            sessionId: 'stored-1',
            action: 'once',
          ),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(backend.resolved, ['q1:once']);
    expect(find.text('Approved once.'), findsOneWidget);
  });

  testWidgets('a plain tap opens the chat and answers nothing', (tester) async {
    backend.pendingApprovalList = [_approval];
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          pushTap: const PushTap(kind: 'approval', sessionId: 'stored-1'),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(backend.resolved, isEmpty);
  });

  group('the chat on screen', () {
    Widget scoped(Widget screen) => ProviderScope(child: themed(screen));

    testWidgets('is marked while open and cleared when it closes', (
      tester,
    ) async {
      await tester.pumpWidget(
        scoped(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      expect(container.read(foregroundChatProvider), 'stored-1');

      await tester.pumpWidget(scoped(const SizedBox()));
      await settle(tester);
      expect(container.read(foregroundChatProvider), isNull);
    });

    testWidgets('a new chat is not marked until it has an id', (tester) async {
      await tester.pumpWidget(scoped(ChatScreen(backend: backend)));
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      expect(container.read(foregroundChatProvider), isNull);
    });

    testWidgets('leaving does not clear another chat\'s mark', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final chat = container.read(foregroundChatProvider.notifier)
        ..enter('a')
        ..enter('b')
        ..leave('a');
      expect(container.read(foregroundChatProvider), 'b');
      chat.leave('b');
      expect(container.read(foregroundChatProvider), isNull);
    });
  });
}
