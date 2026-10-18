import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/iris_voice_orb.dart';
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
    Duration maxRecording = const Duration(minutes: 2),
    double? width,
    bool animated = false,
  }) async {
    final composer = Composer(
      controller: TextEditingController(),
      running: false,
      onSend: () {},
      onStop: () {},
      onMic: () {},
      recording: recording,
      transcribing: transcribing,
      level: level,
      maxRecording: maxRecording,
      onStopRecording: onStop,
      onCancelRecording: onCancel,
    );
    Widget sized = Align(
      alignment: Alignment.bottomCenter,
      child: width == null ? composer : SizedBox(width: width, child: composer),
    );
    // Under reduced motion (the harness default) the level is throttled to
    // four a second against the wall clock, so the level tests animate.
    if (animated) {
      sized = MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: sized,
      );
    }
    await tester.pumpWidget(themed(sized));
  }

  IrisVoiceOrb orb(WidgetTester tester) =>
      tester.widget<IrisVoiceOrb>(find.byType(IrisVoiceOrb));

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
    expect(find.text('1:15 / 2:00'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await tester.tap(find.bySemanticsLabel('Cancel recording'));
    expect(stopped && cancelled, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('recording-bar'))).height,
      72,
    );
    semantics.dispose();
  });

  testWidgets('the cap comes from the server', (tester) async {
    await pump(
      tester,
      recording: const Duration(seconds: 7),
      maxRecording: const Duration(seconds: 90),
    );
    expect(find.text('0:07 / 1:30'), findsOneWidget);
  });

  testWidgets('recording shows a 46 pt listening orb, not the strip', (
    tester,
  ) async {
    final level = StreamController<double>();
    addTearDown(level.close);
    await pump(
      tester,
      recording: Duration.zero,
      level: level.stream,
      animated: true,
    );

    expect(find.byType(IrisVoiceOrb), findsOneWidget);
    expect(find.byKey(const ValueKey('level-orb')), findsNothing);
    expect(tester.getSize(find.byType(IrisVoiceOrb)), const Size(46, 46));
    expect(orb(tester).mode, VoiceOrbMode.listening);

    level.add(.1);
    await tester.pump();
    expect(orb(tester).mode, VoiceOrbMode.listening);

    level.add(.7);
    await tester.pump();
    expect(orb(tester).mode, VoiceOrbMode.hearing);
    expect(orb(tester).level?.value, closeTo(.7, 1e-9));

    level.add(.1);
    await tester.pump();
    expect(orb(tester).mode, VoiceOrbMode.listening);
  });

  testWidgets('a level outside 0 to 1 is held in range', (tester) async {
    final level = StreamController<double>();
    addTearDown(level.close);
    await pump(
      tester,
      recording: Duration.zero,
      level: level.stream,
      animated: true,
    );
    level.add(4);
    await tester.pump();
    expect(orb(tester).level?.value, 1);
    level.add(-2);
    await tester.pump();
    expect(orb(tester).level?.value, 0);
  });

  testWidgets('320 pt keeps the orb at 46', (tester) async {
    await pump(tester, recording: const Duration(seconds: 5), width: 320);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(IrisVoiceOrb)), const Size(46, 46));
    expect(
      tester.getSize(find.byKey(const ValueKey('recording-bar'))).width,
      lessThanOrEqualTo(320),
    );
  });

  testWidgets('transcribing keeps the Stop slot empty', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, transcribing: true);
    expect(find.bySemanticsLabel('Stop recording'), findsNothing);
    expect(find.bySemanticsLabel('Transcribing'), findsOneWidget);
    expect(orb(tester).mode, VoiceOrbMode.thinking);
    semantics.dispose();
  });
}
