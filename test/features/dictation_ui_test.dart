import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/chat/composer.dart';

import '../support/harness.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Duration? recording,
    bool transcribing = false,
    Stream<double>? level,
    VoidCallback? onStop,
    VoidCallback? onCancel,
  }) async {
    await tester.pumpWidget(
      themed(
        Align(
          alignment: Alignment.bottomCenter,
          child: Composer(
            controller: TextEditingController(),
            running: false,
            onSend: () {},
            onStop: () {},
            onMic: () {},
            recording: recording,
            transcribing: transcribing,
            level: level,
            onStopRecording: onStop,
            onCancelRecording: onCancel,
          ),
        ),
      ),
    );
  }

  testWidgets('the mic shows while the field is empty', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel('Dictate'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('recording shows the time, Cancel and Stop in a taller bar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var stopped = false;
    var cancelled = false;
    await pump(
      tester,
      recording: const Duration(seconds: 75),
      onStop: () => stopped = true,
      onCancel: () => cancelled = true,
    );
    expect(find.text('1:15'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await tester.tap(find.bySemanticsLabel('Cancel recording'));
    expect(stopped && cancelled, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('recording-bar'))).height,
      72,
    );
    semantics.dispose();
  });

  testWidgets('the level reaches the orb through a scale, and stays in range', (
    tester,
  ) async {
    final level = StreamController<double>();
    addTearDown(level.close);
    await pump(tester, recording: Duration.zero, level: level.stream);
    level.add(1);
    await tester.pump();
    final loud = tester.getSize(find.byKey(const ValueKey('level-orb'))).width;
    level.add(0);
    await tester.pump(const Duration(milliseconds: 300));
    final quiet = tester.getSize(find.byKey(const ValueKey('level-orb'))).width;
    expect(loud, greaterThanOrEqualTo(quiet));
    expect(loud, lessThanOrEqualTo(56 * 1.2));
  });

  testWidgets('transcribing keeps the Stop slot empty', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, transcribing: true);
    expect(find.bySemanticsLabel('Stop recording'), findsNothing);
    expect(find.bySemanticsLabel('Transcribing'), findsOneWidget);
    semantics.dispose();
  });
}
