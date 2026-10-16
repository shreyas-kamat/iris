import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/design/components/sheet.dart';
import 'package:iris/features/chat/delete_sheet.dart';

import '../support/harness.dart';

void main() {
  testWidgets('the sheet names the chat and asks before deleting', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      themed(Builder(builder: (context) => TextButton(
        onPressed: () async => answer = await showDeleteSheet(context, 'Weekly planning'),
        child: const Text('go'),
      ))),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete ‘Weekly planning’?'), findsOneWidget);
    expect(find.textContaining('removes it from Hermes for good'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('the sheet sits on its own surface, with a grabber', (tester) async {
    await tester.pumpWidget(
      themed(Builder(builder: (context) => TextButton(
        onPressed: () => showDeleteSheet(context, 'Weekly planning'),
        child: const Text('go'),
      ))),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(IrisSheet), findsOneWidget);
    // Without the sheet's surface the words are drawn straight over the list.
    expect(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(DecoratedBox)),
      findsWidgets,
    );
    final sheet = tester.getRect(find.byType(IrisSheet));
    expect(sheet.bottom, tester.getRect(find.byType(MaterialApp)).bottom);
  });

  test('a refusal because the chat is live is recognised', () {
    expect(refusedAsLive(const IrisFailure(FailureKind.rejected, message: 'cannot delete an active session')), isTrue);
    expect(refusedAsLive(const IrisFailure(FailureKind.rejected, statusCode: 409)), isTrue);
    expect(refusedAsLive(const IrisFailure(FailureKind.notFound, statusCode: 404)), isFalse);
    expect(refusedAsLive(const IrisFailure(FailureKind.offline)), isFalse);
  });
}
