import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/voice/live_audio_consent.dart';

import '../support/harness.dart';

void main() {
  for (final accept in [true, false]) {
    testWidgets('direct audio requires an explicit choice: $accept', (
      tester,
    ) async {
      bool? allowed;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async =>
                    allowed = await confirmLiveAudio(context),
                child: const Text('Call'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();
      expect(allowed, isNull);
      expect(find.text('Send call audio to OpenAI?'), findsOneWidget);
      await tester.tap(find.text(accept ? 'Continue with GPT-Live' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(allowed, accept);
    });
  }

  testWidgets('dismissing consent does not authorize audio', (tester) async {
    bool? allowed;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async => allowed = await confirmLiveAudio(context),
              child: const Text('Call'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
  });
}
