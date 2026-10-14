/// The new design pieces: a ring, a stretching gauge, a secret field and a
/// toast with one action.
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/design/components/toast.dart';

import '../support/harness.dart';

void main() {
  testWidgets('the ring says what it measures', (tester) async {
    await tester.pumpWidget(
      themed(
        const Center(
          child: IrisRing(value: .18, semanticLabel: 'Context window, 18 percent'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Context window, 18 percent'), findsOneWidget);
  });

  testWidgets('a gauge without a width fills its row', (tester) async {
    await tester.pumpWidget(
      themed(const Center(child: SizedBox(width: 300, child: IrisGauge(value: .5, width: null)))),
    );
    expect(tester.getSize(find.byType(IrisGauge)).width, 300);
  });

  testWidgets('a secret field turns off autocorrect and suggestions', (tester) async {
    await tester.pumpWidget(
      themed(
        const Center(
          child: IrisField(
            hint: 'Password',
            obscure: true,
            trailing: Icon(Icons.visibility),
          ),
        ),
      ),
    );
    final editable = tester.widget<widgets.EditableText>(find.byType(widgets.EditableText));
    expect(editable.obscureText, isTrue);
    expect(editable.autocorrect, isFalse);
    expect(editable.enableSuggestions, isFalse);
    // The trailing control is merged into the field's own semantics node, so
    // it is found as a widget, not by label.
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('a toast shows, runs its action once and leaves', (tester) async {
    var undone = 0;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: IrisButton(
              label: 'Go',
              onPressed: () => showIrisToast(
                context,
                message: 'Archived',
                actionLabel: 'Undo',
                onAction: () => undone++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Archived'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, 1);
    expect(find.text('Archived'), findsNothing);
  });

  testWidgets('a toast leaves by itself', (tester) async {
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: IrisButton(
              label: 'Go',
              onPressed: () => showIrisToast(context, message: 'Saved'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(IrisToast.visibleFor + const Duration(seconds: 1));
    expect(find.text('Saved'), findsNothing);
  });
}
