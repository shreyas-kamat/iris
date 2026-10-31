import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/image_host_scope.dart';
import 'package:iris/design/components/markdown.dart';

import '../support/harness.dart';

void main() {
  const markdown = '![panel](https://grafana.local/a.png)';

  Widget scoped(Set<String> hosts, {ValueChanged<String>? onAllow}) => themed(
    ImageHostScope(
      hosts: hosts,
      onAllow: onAllow ?? (_) {},
      child: const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, child: IrisMarkdown(markdown)),
      ),
    ),
  );

  testWidgets('an image from an allowed host loads without a tap', (
    tester,
  ) async {
    await tester.pumpWidget(scoped({'grafana.local'}));
    await tester.pump();
    expect(find.text('Tap to load'), findsNothing);
  });

  testWidgets('another host still asks first', (tester) async {
    await tester.pumpWidget(scoped({'other.test'}));
    await tester.pump();
    expect(find.text('Tap to load'), findsOneWidget);
  });

  testWidgets('long-pressing the card offers Always load from this host', (
    tester,
  ) async {
    String? allowed;
    await tester.pumpWidget(
      scoped(const {}, onAllow: (host) => allowed = host),
    );
    await tester.longPress(find.text('Tap to load'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always load from grafana.local'));
    await tester.pumpAndSettle();
    expect(allowed, 'grafana.local');
    expect(find.text('Tap to load'), findsNothing);
  });

  testWidgets('without a scope nothing is allowed and there is no menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: IrisMarkdown(markdown)),
        ),
      ),
    );
    await tester.longPress(find.text('Tap to load'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Always load'), findsNothing);
    expect(find.text('Tap to load'), findsOneWidget);
  });
}
