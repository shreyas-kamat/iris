/// Reply kits on the conversation screen (plan 4.4): docked above the composer, one at a time, and gone once the
/// person answers, types or dismisses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/genui/genui_parser.dart';
import 'package:iris/data/genui/signals.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/genui/reply_kit.dart';

import '../support/fake_chat_backend.dart';
import '../support/fake_genui_api.dart';
import '../support/harness.dart';

UiSurfaceItem _kit(String id, String code, {int rev = 1}) => UiSurfaceItem(
  id: 'item-$id',
  ref: UiSurfaceRef(
    surfaceId: id,
    code: code,
    placement: SurfacePlacement.replyKit,
    rev: rev,
  ),
);

const _decision = 'root = ApproveReject("Approve the deploy", "Hold it")';

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 50));

  Future<void> open(
    WidgetTester tester,
    List<TranscriptItem> history, {
    SignalReporter? signals,
  }) async {
    backend.historyResult = Ok(history);
    await tester.pumpWidget(
      themed(
        ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          signals: signals,
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
  }

  testWidgets('a kit from the assistant sits above the composer', (
    tester,
  ) async {
    await open(tester, [
      const UserTurn(id: 'u', text: 'Deploy?'),
      const AssistantTurn(id: 'a', text: 'Shall I go ahead?'),
      _kit('go', _decision),
    ]);
    expect(find.byType(ReplyKitDock), findsOneWidget);
    expect(find.text('Approve the deploy'), findsOneWidget);
    // The kit is not drawn a second time in the transcript.
    expect(find.text('Approve the deploy'), findsOneWidget);
  });

  testWidgets('only the newest kit is shown', (tester) async {
    await open(tester, [
      const AssistantTurn(id: 'a', text: 'First question'),
      _kit('one', 'root = ApproveReject("Old yes", "Old no")'),
      const AssistantTurn(id: 'b', text: 'Second question'),
      _kit('two', 'root = ApproveReject("New yes", "New no")'),
    ]);
    expect(find.text('New yes'), findsOneWidget);
    expect(find.text('Old yes'), findsNothing);
  });

  testWidgets('no kit once the person has answered', (tester) async {
    await open(tester, [
      _kit('go', _decision),
      const UserTurn(id: 'u', text: 'Hold it'),
    ]);
    expect(find.byType(ReplyKitDock), findsNothing);
  });

  testWidgets(
    'tapping a choice sends it with its hidden block and clears the kit',
    (tester) async {
      await open(tester, [
        const AssistantTurn(id: 'a', text: 'Shall I go ahead?'),
        _kit('go', _decision),
      ]);
      await tester.tap(find.text('Approve the deploy'));
      await settle(tester);
      await settle(tester);
      expect(backend.submits, hasLength(1));
      final (text, envelope) = IrisActionEnvelope.split(
        backend.submits.single.$2,
      );
      expect(text, 'Approve the deploy');
      expect(envelope!.surface, 'go');
      expect(envelope.component, 'ApproveReject');
      expect(envelope.context, {'decision': 'approve'});
      // The person's message shows the sentence, not the block, and the kit has gone.
      expect(find.text('Approve the deploy'), findsOneWidget);
      expect(find.textContaining('iris-action'), findsNothing);
      expect(find.byType(ReplyKitDock), findsNothing);
    },
  );

  testWidgets('typing clears the kit, and it does not come back', (
    tester,
  ) async {
    await open(tester, [_kit('go', _decision)]);
    expect(find.byType(ReplyKitDock), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Actually');
    await tester.pump();
    expect(find.byType(ReplyKitDock), findsNothing);
    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    expect(find.byType(ReplyKitDock), findsNothing);
  });

  testWidgets('can be dismissed', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, [_kit('go', _decision)]);
    await tester.tap(find.bySemanticsLabel('Dismiss suggested replies'));
    await tester.pump();
    expect(find.byType(ReplyKitDock), findsNothing);
    semantics.dispose();
  });

  testWidgets('hidden while a reply is still running', (tester) async {
    await open(tester, [_kit('go', _decision)]);
    expect(find.byType(ReplyKitDock), findsOneWidget);
    backend.emit(const MessageStarted('run-1'));
    await settle(tester);
    expect(find.byType(ReplyKitDock), findsNothing);
    backend.emit(const MessageCompleted('run-1', content: 'done'));
    await settle(tester);
    expect(find.byType(ReplyKitDock), findsOneWidget);
  });

  testWidgets('dismissing a kit reports it, with the stored conversation', (
    tester,
  ) async {
    final api = FakeGenUiApi();
    final reporter = SignalReporter(api: () async => api);
    addTearDown(reporter.dispose);
    await open(tester, [
      const AssistantTurn(id: 'a', text: 'Shall I go ahead?'),
      _kit('go', _decision),
    ], signals: reporter);

    await tester.tap(find.bySemanticsLabel('Dismiss suggested replies'));
    await settle(tester);
    await reporter.flush();

    final sent = api.signalBatches.single.single;
    expect(sent.signal, DisplaySignal.dismissed);
    expect(sent.surface, 'go');
    expect(sent.session, 'stored-1');
    expect(find.byType(ReplyKitDock), findsNothing);
  });
}
