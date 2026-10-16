import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/chat/chat_state.dart';
import 'package:iris/features/chat/model_sheet.dart';

import '../support/harness.dart';

void main() {
  ModelOptions options({
    required bool reasoning,
    required bool fast,
    bool known = true,
  }) => ModelOptions(
    model: 'opus',
    provider: 'anthropic',
    providers: [
      ModelProvider(
        slug: 'anthropic',
        name: 'Anthropic',
        models: const ['opus'],
        isCurrent: true,
        capabilities: known
            ? {'opus': ModelCaps(reasoning: reasoning, fast: fast)}
            : const {},
      ),
    ],
  );

  Future<ValueNotifier<ChatState>> pump(
    WidgetTester tester,
    ModelOptions loaded, {
    ChatState state = const ChatState(
      phase: ChatPhase.ready,
      model: 'opus',
      provider: 'anthropic',
    ),
    ValueChanged<ReasoningEffort>? onEffort,
    ValueChanged<bool>? onFast,
  }) async {
    final notifier = ValueNotifier(state);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      themed(
        Align(
          alignment: Alignment.bottomCenter,
          child: ModelSheet(
            load: () async => Ok(loaded),
            current: 'opus',
            state: notifier,
            onEffort: onEffort,
            onFast: onFast,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('both controls show when the model supports both', (
    tester,
  ) async {
    await pump(tester, options(reasoning: true, fast: true));
    expect(find.text('REASONING EFFORT'), findsOneWidget);
    for (final label in ['None', 'Low', 'Medium', 'High', 'Max']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Fast mode'), findsOneWidget);
  });

  testWidgets('unsupported controls are removed, not disabled', (tester) async {
    await pump(tester, options(reasoning: true, fast: false));
    expect(find.text('REASONING EFFORT'), findsOneWidget);
    expect(find.text('Fast mode'), findsNothing);
    // A fresh sheet: the first one keeps the options it loaded.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, options(reasoning: false, fast: false));
    expect(find.text('REASONING EFFORT'), findsNothing);
    expect(find.text('Fast mode'), findsNothing);
  });

  testWidgets('unknown capabilities fall back to what the session reported', (
    tester,
  ) async {
    await pump(
      tester,
      options(reasoning: false, fast: false, known: false),
      state: const ChatState(
        phase: ChatPhase.ready,
        model: 'opus',
        provider: 'anthropic',
        effort: ReasoningEffort.medium,
      ),
    );
    expect(find.text('REASONING EFFORT'), findsOneWidget);
    expect(find.text('Fast mode'), findsNothing);
  });

  testWidgets('tapping an effort reports it, and the selected one is marked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    ReasoningEffort? picked;
    final notifier = await pump(
      tester,
      options(reasoning: true, fast: true),
      onEffort: (e) => picked = e,
    );
    await tester.tap(find.text('High'));
    expect(picked, ReasoningEffort.high);
    notifier.value = notifier.value.copyWith(effort: ReasoningEffort.high);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('High.*selected', caseSensitive: false)),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the fast switch reports its change', (tester) async {
    bool? fast;
    await pump(
      tester,
      options(reasoning: true, fast: true),
      onFast: (v) => fast = v,
    );
    await tester.tap(find.byType(IrisSwitch));
    expect(fast, isTrue);
  });

  testWidgets('a change made mid-reply says it waits for the next turn', (
    tester,
  ) async {
    final notifier = await pump(
      tester,
      options(reasoning: true, fast: true),
      state: const ChatState(
        phase: ChatPhase.ready,
        model: 'opus',
        provider: 'anthropic',
        turn: TurnPhase.working,
        effort: ReasoningEffort.high,
      ),
      onEffort: (_) {},
    );
    await tester.tap(find.text('Max'));
    notifier.value = notifier.value.copyWith(effort: ReasoningEffort.max);
    await tester.pumpAndSettle();
    expect(find.text('Applies after this reply.'), findsOneWidget);
    expect(find.text('high → max'), findsOneWidget);
    notifier.value = notifier.value.copyWith(turn: TurnPhase.idle);
    await tester.pumpAndSettle();
    expect(find.text('Applies after this reply.'), findsNothing);
  });

  testWidgets('five segments wrap at 200% text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      themed(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ModelSheet(
              load: () async => Ok(options(reasoning: true, fast: true)),
              current: 'opus',
              state: ValueNotifier(
                const ChatState(
                  phase: ChatPhase.ready,
                  model: 'opus',
                  provider: 'anthropic',
                ),
              ),
              onEffort: (_) {},
              onFast: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
