/// The iris orb: every state renders, reduced motion stops the ticker, and the
/// semantics say what the orb means.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/iris_orb.dart';
import 'package:iris/design/tokens/palette.dart';

import '../support/harness.dart';

void main() {
  testWidgets('every state renders at every size without throwing', (
    tester,
  ) async {
    for (final state in AgentState.values) {
      for (final size in [12.0, 20.0, 40.0, 150.0]) {
        await tester.pumpWidget(
          themed(Center(child: IrisOrb(state: state, size: size))),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${state.name} at $size',
        );
      }
    }
  });

  testWidgets('under reduced motion the orb paints once and schedules nothing', (
    tester,
  ) async {
    // themed() sets disableAnimations, which is the reduced-motion setting the
    // app reads. The orb must not start its ticker, or pumpAndSettle hangs.
    await tester.pumpWidget(
      themed(const Center(child: IrisOrb(state: AgentState.thinking))),
    );
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('a resting orb stops scheduling frames after it settles', (
    tester,
  ) async {
    // Start in a state that moves, then drop to rest. The ease has to finish,
    // after which the orb must stop asking for frames: a list of resting orbs
    // should cost nothing.
    Widget thinkingOrb() => themed(
      const MediaQuery(
        data: MediaQueryData(),
        child: Center(child: IrisOrb(state: AgentState.thinking)),
      ),
    );
    await tester.pumpWidget(thinkingOrb());
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(
      themed(
        const MediaQuery(
          data: MediaQueryData(),
          child: Center(child: IrisOrb(state: AgentState.rest)),
        ),
      ),
    );
    // Two seconds is far beyond the ease's settling time at five per second.
    for (var i = 0; i < 125; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('semantics describe each state in words', (tester) async {
    final handle = tester.ensureSemantics();
    const labels = {
      AgentState.idle: 'Agent idle',
      AgentState.thinking: 'Agent thinking',
      AgentState.streaming: 'Agent replying',
      AgentState.working: 'Agent running a tool',
      AgentState.waiting: 'Agent waiting for you',
      AgentState.done: 'Run finished',
      AgentState.failed: 'Run failed',
      AgentState.loading: 'Connecting',
      AgentState.offline: 'Offline',
      AgentState.rest: 'Finished',
    };
    for (final entry in labels.entries) {
      await tester.pumpWidget(
        themed(Center(child: IrisOrb(state: entry.key))),
      );
      expect(
        find.bySemanticsLabel(entry.value),
        findsOneWidget,
        reason: entry.key.name,
      );
    }
    handle.dispose();
  });

  testWidgets('waiting is a live region, and other states are not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(const Center(child: IrisOrb(state: AgentState.waiting))),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Agent waiting for you')).flagsCollection.isLiveRegion,
      isTrue,
    );
    await tester.pumpWidget(
      themed(const Center(child: IrisOrb(state: AgentState.idle))),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Agent idle')).flagsCollection.isLiveRegion,
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('an explicit semanticLabel overrides the state description', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(
        const Center(
          child: IrisOrb(state: AgentState.idle, semanticLabel: 'Hermes link'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Hermes link'), findsOneWidget);
    handle.dispose();
  });
}
