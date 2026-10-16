import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/features/chat/branched_header.dart';

import '../support/harness.dart';

void main() {
  testWidgets('the header line names the parent and opens it when tapped', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      themed(BranchedHeader(parentTitle: 'Investigate worker heartbeat gaps', onOpen: () => opened = true)),
    );
    expect(find.textContaining('Branched from'), findsOneWidget);
    expect(find.textContaining('Investigate worker heartbeat gaps', findRichText: true), findsOneWidget);
    await tester.tap(find.byType(BranchedHeader));
    expect(opened, isTrue);
  });

  testWidgets('the header line grows with the text instead of clipping at 200%', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      themed(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(2), disableAnimations: true),
          child: BranchedHeader(parentTitle: 'Investigate worker heartbeat gaps', onOpen: () {}),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BranchedHeader)).height, greaterThan(44));
  });

  testWidgets('the divider shows when the chat was branched', (tester) async {
    await tester.pumpWidget(themed(BranchedDivider(at: DateTime(2026, 10, 16, 14, 2))));
    expect(find.text('BRANCHED HERE · 14:02'), findsOneWidget);
  });

  test('a record keeps when it was made', () {
    const record = BranchRecord(parentId: 'p', parentTitle: 'P', count: 3, at: 1760623320000);
    expect(BranchRecord.tryParse(record.toJson())?.at, 1760623320000);
    expect(BranchRecord.tryParse('{"parent":"p"}')?.at, 0, reason: 'old records have no time');
  });
}
