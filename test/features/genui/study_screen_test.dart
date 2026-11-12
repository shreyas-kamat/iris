/// The "Study my work" screen: it says what a study reads before anything starts, then follows one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/genui_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/genui/personal_models.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/genui/study_screen.dart';

import '../../support/fake_chat_backend.dart';
import '../../support/fake_genui_api.dart';
import '../../support/harness.dart';

void main() {
  late FakeChatBackend backend;
  late FakeGenUiApi api;

  setUp(() {
    backend = FakeChatBackend();
    api = FakeGenUiApi();
  });

  tearDown(() => backend.close());

  Widget screen({VoidCallback? onReview}) => ProviderScope(
    overrides: [
      activeChatProvider.overrideWith((ref) async => backend),
      genUiApiProvider.overrideWith((ref) async => api),
    ],
    child: themed(StudyScreen(onReview: onReview)),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Leaves the tree so the screen's polling timer is cancelled before the test ends.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('says what a study reads and that nothing is used unapproved', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.text('Study my work'), findsWidgets);
    for (final line in StudyScreen.reads) {
      expect(find.textContaining(line), findsOneWidget);
    }
    expect(find.textContaining('stays on your server'), findsOneWidget);
    expect(find.textContaining('approved'), findsOneWidget);
    expect(backend.calls, isNot(contains('create')), reason: 'not started yet');
    await leave(tester);
  });

  testWidgets('starting makes the Iris setup chat and shows the progress', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(find.widgetWithText(IrisButton, 'Study my work'));
    await settle(tester);

    expect(backend.calls, contains('create'));
    expect(backend.submitted.single.$2, contains('iris-study'));
    expect(find.text('Hermes is reading your work'), findsOneWidget);
    expect(find.textContaining('Nothing proposed yet'), findsOneWidget);
    expect(find.text('Watch in the chat'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('shows what has been proposed so far, then that it is done', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(find.widgetWithText(IrisButton, 'Study my work'));
    await settle(tester);

    api
      ..profile = const WorkProfile(
        summary: 'Engineer',
        chips: [],
        status: PersonalStatus.proposed,
        rev: 1,
      )
      ..stored = [
        sampleTemplate('a'),
        sampleTemplate('b', kind: TemplateKind.replyKit),
      ];
    backend.emit(const MessageStarted('run-new'));
    await settle(tester);
    backend.emit(const MessageCompleted('run-new', content: 'Done.'));
    backend.emit(const BusyChanged('run-new', busy: false));
    await settle(tester);
    await settle(tester);

    expect(find.text('Hermes has proposals for you'), findsOneWidget);
    expect(
      find.textContaining('a profile and 2 templates (1 reply kit)'),
      findsOneWidget,
    );
    expect(find.text('Open the chat'), findsOneWidget);
    expect(
      find.text('Review what it found'),
      findsNothing,
      reason: 'no review screen wired',
    );
    await leave(tester);
  });

  testWidgets('offers the review once there is a screen for it', (
    tester,
  ) async {
    var reviewed = 0;
    await tester.pumpWidget(screen(onReview: () => reviewed++));
    await settle(tester);
    await tester.tap(find.widgetWithText(IrisButton, 'Study my work'));
    await settle(tester);
    api.stored = [sampleTemplate('a')];
    backend.emit(const MessageStarted('run-new'));
    await settle(tester);
    backend.emit(const BusyChanged('run-new', busy: false));
    await settle(tester);
    await settle(tester);

    await tester.tap(find.text('Review what it found'));
    expect(reviewed, 1);
    await leave(tester);
  });

  testWidgets('a study that proposed nothing says so', (tester) async {
    await tester.pumpWidget(screen(onReview: () {}));
    await settle(tester);
    await tester.tap(find.widgetWithText(IrisButton, 'Study my work'));
    await settle(tester);
    backend.emit(const MessageStarted('run-new'));
    await settle(tester);
    backend.emit(const BusyChanged('run-new', busy: false));
    await settle(tester);
    await settle(tester);

    expect(find.text('Hermes did not propose anything'), findsOneWidget);
    expect(find.text('Review what it found'), findsNothing);
    await leave(tester);
  });

  testWidgets('a failure says why and can be tried again', (tester) async {
    backend.createResult = const Err(
      IrisFailure(FailureKind.offline, message: 'No route to the server'),
    );
    await tester.pumpWidget(screen());
    await settle(tester);
    await tester.tap(find.widgetWithText(IrisButton, 'Study my work'));
    await settle(tester);

    expect(find.text('The study did not finish'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    backend.createResult = const Ok(
      NewConversation(runtimeId: 'run-2', storedId: 'stored-2'),
    );
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.textContaining(StudyScreen.reads.first), findsOneWidget);
    expect(find.widgetWithText(IrisButton, 'Study my work'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('leaving does not loop: the screen lets Back pop it', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pump();
    final scopes = tester.widgetList<PopScope<Object?>>(
      find.descendant(of: find.byType(StudyScreen), matching: find.byWidgetPredicate((w) => w is PopScope)),
    );
    expect(scopes, isNotEmpty);
    // A screen that sets onBack to maybePop makes canPop false, and maybePop then calls
    // onBack again without end: the app hangs on the UI thread.
    expect(scopes.every((s) => s.canPop), isTrue);
  });
}
