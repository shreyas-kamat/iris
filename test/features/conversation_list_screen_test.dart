/// Home: the profile's conversations, the way into one, more of them, and
/// which profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;

  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  Widget home(
    List<ConversationSummary> conversations, {
    int? total,
    List<AgentProfile> profiles = const [],
  }) => ProviderScope(
    overrides: [
      activeServerProvider.overrideWithValue(
        const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'Home'),
      ),
      activeLinkProvider.overrideWith(
        (ref) => Stream.value(const LinkState(LinkPhase.live)),
      ),
      activeChatProvider.overrideWith((ref) async => backend),
      conversationsProvider.overrideWith(
        (ref) async => ConversationPage(
          items: conversations,
          total: total ?? conversations.length,
        ),
      ),
      profilesProvider.overrideWith((ref) async => profiles),
    ],
    child: themed(const ConversationListScreen()),
  );

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 50));

  testWidgets('the header names the server and the link', (tester) async {
    await tester.pumpWidget(home(const []));
    await settle(tester);
    // The gateway line names the host of the server and the link headline.
    expect(find.text('h.example · Connected'), findsOneWidget);
  });

  testWidgets('lists conversations with when and where they started', (tester) async {
    await tester.pumpWidget(
      home([
        ConversationSummary(
          id: 'a',
          title: 'Fix the build',
          startedAt: DateTime.now().subtract(const Duration(hours: 3)),
          messageCount: 12,
          source: 'telegram',
        ),
      ]),
    );
    await settle(tester);
    expect(find.text('Fix the build'), findsOneWidget);
    expect(find.text('3h ago · telegram · 12 messages'), findsOneWidget);
  });

  testWidgets('an empty profile invites a first conversation', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(home(const []));
    await settle(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.bySemanticsLabel('New conversation'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a conversation opens it', (tester) async {
    backend.historyResult = const Ok([UserTurn(id: '1', text: 'earlier')]);
    await tester.pumpWidget(
      home(const [ConversationSummary(id: 'a', title: 'Fix the build')]),
    );
    await settle(tester);
    await tester.tap(find.text('Fix the build'));
    // The route transition, then the history load.
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(backend.calls, contains('history a'));
    expect(find.text('earlier'), findsOneWidget);
  });

  testWidgets('more conversations load at the end of the list', (tester) async {
    backend.conversationsResult = const Ok([
      ConversationSummary(id: 'b', title: 'Second'),
    ]);
    await tester.pumpWidget(
      home(const [ConversationSummary(id: 'a', title: 'First')], total: 2),
    );
    await settle(tester);
    await tester.tap(find.text('Show more'));
    await settle(tester);
    await settle(tester);
    expect(backend.calls, contains('conversations 1'));
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Show more'), findsNothing);
  });

  testWidgets('with several profiles, the pill switches profile', (tester) async {
    await tester.pumpWidget(
      home(
        const [],
        profiles: const [
          AgentProfile(name: 'default', isDefault: true),
          AgentProfile(name: 'ananta', model: 'gpt-6-luna'),
        ],
      ),
    );
    await settle(tester);
    // The pill shows the profile name as it is stored.
    await tester.tap(find.text('default'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.tap(find.text('ananta'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListScreen)),
    );
    expect(container.read(activeProfileProvider), 'ananta');
    expect(find.text('ananta'), findsOneWidget);
  });

  testWidgets('a single profile shows no picker', (tester) async {
    await tester.pumpWidget(
      home(
        const [],
        profiles: const [AgentProfile(name: 'default', isDefault: true)],
      ),
    );
    await settle(tester);
    // No picker means no chevron: the pill is a label only.
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('the usage strip sits under the hero when a provider reports', (tester) async {
    backend.modelOptionsResult = const Ok(
      ModelOptions(
        provider: 'openai-codex',
        providers: [
          ModelProvider(
            slug: 'openai-codex',
            name: 'OpenAI Codex',
            models: ['m'],
            isCurrent: true,
            usage: ProviderUsage(windows: [UsageWindow(label: 'Session', usedPercent: 10)]),
          ),
        ],
      ),
    );
    await tester.pumpWidget(home(const []));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI Codex'), findsOneWidget);
  });

  group('managing conversations', () {
    final rows = [
      const ConversationSummary(id: 'a', title: 'Fix the build'),
      const ConversationSummary(id: 'b', title: 'Plan the week'),
    ];

    testWidgets('rename from a long press', (tester) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Fix CI');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(backend.renames, [('a', 'Fix CI')]);
      expect(find.text('Fix CI'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refused rename puts the old title back', (tester) async {
      backend.renameResult = const Err(IrisFailure(FailureKind.rejected, message: 'nope'));
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Fix CI');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Fix the build'), findsOneWidget);
      expect(find.textContaining('Could not rename'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('archive hides the row; undo brings it back', (tester) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(backend.archives, [('a', true)]);
      expect(find.text('Fix the build'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(backend.archives, [('a', true), ('a', false)]);
      expect(find.text('Fix the build'), findsOneWidget);
    });

    testWidgets('a refused archive brings the row back', (tester) async {
      backend.archiveResult = const Err(IrisFailure(FailureKind.offline));
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Fix the build'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Archived opens the archived screen', (tester) async {
      backend.archivedResult = const Ok([ConversationSummary(id: 'z', title: 'Old notes')]);
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Archived'), 200);
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      expect(find.text('Old notes'), findsOneWidget);
    });
  });
}
