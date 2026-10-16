import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/composer.dart';

import '../support/harness.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    double percent, {
    VoidCallback? onContext,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      themed(
        Align(
          alignment: Alignment.bottomCenter,
          child: Composer(
            controller: controller,
            running: false,
            onSend: () {},
            onStop: () {},
            contextUsage: ContextUsage(percent: percent),
            onContext: onContext,
          ),
        ),
      ),
    );
  }

  testWidgets('the percentage stays hidden under 50%', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, 49);
    expect(find.text('49%'), findsNothing);
    expect(find.bySemanticsLabel('Context window, 49 percent'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('from 50% the label shows in mono', (tester) async {
    await pump(tester, 62);
    expect(find.text('62%'), findsOneWidget);
  });

  testWidgets('the ring has a 44 point hit area', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, 62, onContext: () {});
    final box = tester.getSize(
      find.bySemanticsLabel('Context window, 62 percent').first,
    );
    expect(box.width, greaterThanOrEqualTo(44));
    expect(box.height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });

  testWidgets('at 95% the strip offers Branch', (tester) async {
    var branched = false;
    await tester.pumpWidget(
      themed(ContextStrip(onBranch: () => branched = true)),
    );
    expect(
      find.text('Context is nearly full. Older turns will be summarised.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Branch'));
    expect(branched, isTrue);
  });
}
