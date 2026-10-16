import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/busy_setting.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'the picker lists the three modes with a line each and the profile footnote',
    (tester) async {
      BusyMode? chosen;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen = await showBusyPicker(
                context,
                current: BusyMode.queue,
                profile: 'Default',
                host: 'hermes.local',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      for (final mode in BusyMode.values) {
        expect(find.text(mode.label), findsOneWidget);
        expect(find.text(mode.blurb), findsOneWidget);
      }
      expect(
        find.text('Applies to the Default profile on hermes.local.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Steer'));
      await tester.pumpAndSettle();
      expect(chosen, BusyMode.steer);
    },
  );

  testWidgets('picking the current mode still closes the sheet', (
    tester,
  ) async {
    BusyMode? chosen;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => chosen = await showBusyPicker(
              context,
              current: BusyMode.queue,
              profile: 'Default',
              host: 'h',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(chosen, BusyMode.queue);
  });
}
