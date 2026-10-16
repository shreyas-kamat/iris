import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/toast.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a top toast sits under the status bar, not above the composer', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(themed(Builder(builder: (context) {
      captured = context;
      return const SizedBox.expand();
    })));
    showIrisToast(captured, message: 'Queued for after this reply', top: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final box = tester.getRect(find.text('Queued for after this reply'));
    expect(box.top, lessThan(120), reason: 'top toasts sit near the top edge');
  });
}
