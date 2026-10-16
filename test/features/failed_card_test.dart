import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/transcript_view.dart';

import '../support/harness.dart';

void main() {
  const notice = Notice(
    id: 'n',
    text:
        'Hermes lost the gateway while reading logs. 502 after 30s on read_logs',
    isError: true,
    retryable: true,
  );

  Widget card({
    bool retrying = false,
    int attempt = 1,
    VoidCallback? onRetry,
    VoidCallback? onStop,
  }) => themed(
    SingleChildScrollView(
      child: TranscriptEntry(
        notice,
        onRetry: onRetry ?? () {},
        retrying: retrying,
        attempt: attempt,
        onStop: onStop,
      ),
    ),
  );

  testWidgets('says the turn stopped and offers Retry and Details', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(card(onRetry: () => retried = true));
    expect(find.text('The turn stopped'), findsOneWidget);
    expect(find.textContaining('Hermes lost the gateway'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('Details shows the full message in mono, and hides it again', (
    tester,
  ) async {
    await tester.pumpWidget(card());
    expect(find.byKey(const ValueKey('failure-details')), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('failure-details')), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('failure-details')), findsNothing);
  });

  testWidgets('retrying shows the attempt and a Stop', (tester) async {
    var stopped = false;
    await tester.pumpWidget(
      card(retrying: true, attempt: 2, onStop: () => stopped = true),
    );
    expect(find.text('Retrying…'), findsOneWidget);
    expect(find.text('attempt 2'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Stop'));
    expect(stopped, isTrue);
  });
}
