/// A whole conversation screen against a scripted backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/chat_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 50));

  testWidgets('opens a stored conversation and shows its transcript', (tester) async {
    backend.historyResult = const Ok([
      UserTurn(id: '1', text: 'hi'),
      AssistantTurn(id: '2', text: 'hello'),
    ]);
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          title: 'Greetings',
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    expect(find.text('Greetings'), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('a streamed reply appears as it arrives', (tester) async {
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    backend
      ..emit(const MessageStarted('run-1'))
      ..emit(const TextDelta('run-1', 'Hel'))
      ..emit(const TextDelta('run-1', 'lo'));
    await settle(tester);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    backend.emit(const MessageCompleted('run-1'));
    await settle(tester);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('sending puts the message in the transcript and submits it', (tester) async {
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    await tester.enterText(find.byType(EditableText), 'Run the tests');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await settle(tester);
    expect(backend.submitted.single, ('run-1', 'Run the tests'));
    expect(find.text('Run the tests'), findsOneWidget);
  });

  testWidgets('an approval shows above the composer and is answered', (tester) async {
    backend.resumeResult = Ok(
      ResumedConversation(
        runtimeId: 'run-1',
        running: true,
        pending: [
          ApprovalAsked(
            const ApprovalRequest(
              sessionId: 'run-1',
              command: 'git push',
              description: 'Push to origin',
              choices: ['once', 'deny'],
              serverRequestId: 'srq-1',
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    expect(find.text('git push'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await settle(tester);
    expect(backend.approvals, ['once']);
    expect(find.text('git push'), findsNothing);
  });

  testWidgets('a conversation that cannot be read offers a retry', (tester) async {
    backend.historyResult = const Err(
      IrisFailure(FailureKind.notFound, message: 'Session not found'),
    );
    await tester.pumpWidget(
      themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
    );
    await settle(tester);
    expect(find.text('Could not open this conversation'), findsOneWidget);
    expect(find.text('Session not found'), findsOneWidget);
    backend.historyResult = const Ok([UserTurn(id: '1', text: 'back')]);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    await settle(tester);
    expect(find.text('back'), findsOneWidget);
  });

  testWidgets('a new chat starts empty and is created on send', (tester) async {
    await tester.pumpWidget(themed(ChatScreen(backend: backend)));
    await settle(tester);
    expect(find.text('Ask your agent anything.'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'hi');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await settle(tester);
    expect(backend.calls, contains('create'));
    expect(backend.submitted.single, ('run-new', 'hi'));
  });
}
