/// Archived conversations: listed, unarchived, and an empty state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/archived_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;
  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  testWidgets('nothing archived says so', (tester) async {
    await tester.pumpWidget(themed(ArchivedScreen(backend: backend)));
    await tester.pumpAndSettle();
    expect(find.text('Nothing archived'), findsOneWidget);
  });

  testWidgets('unarchive removes the row and tells the backend', (tester) async {
    backend.archivedResult = const Ok([ConversationSummary(id: 'z', title: 'Old notes')]);
    await tester.pumpWidget(themed(ArchivedScreen(backend: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Unarchive Old notes'));
    await tester.pumpAndSettle();
    expect(backend.archives, [('z', false)]);
    expect(find.text('Old notes'), findsNothing);
  });

  testWidgets('a failed load offers to try again', (tester) async {
    backend.archivedResult = const Err(IrisFailure(FailureKind.offline, message: 'down'));
    await tester.pumpWidget(themed(ArchivedScreen(backend: backend)));
    await tester.pumpAndSettle();
    expect(find.text('Could not load archived chats'), findsOneWidget);
    backend.archivedResult = const Ok([]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing archived'), findsOneWidget);
  });

  testWidgets('a long-press offers Delete and removes the row', (tester) async {
    backend.archivedResult = const Ok([ConversationSummary(id: 'z', title: 'Old notes')]);
    await tester.pumpWidget(themed(ArchivedScreen(backend: backend)));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Old notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(backend.deletes, ['z']);
    expect(find.text('Old notes'), findsNothing);
  });

}
