import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/chat/conversation_actions.dart';

import '../support/harness.dart';

void main() {
  Future<void> open(WidgetTester tester, void Function(String?) done) async {
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                done(await showRenameSheet(context, 'Weekly planning')),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('Save does nothing until the title changes and is not empty', (
    tester,
  ) async {
    String? result = 'untouched';
    await open(tester, (value) => result = value);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget, reason: 'unchanged: stays open');
    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget, reason: 'empty: stays open');
    await tester.enterText(find.byType(EditableText), 'Q4');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, 'Q4');
  });

  testWidgets('the clear button empties the field', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, (_) {});
    await tester.tap(find.bySemanticsLabel('Clear'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    semantics.dispose();
  });
}
