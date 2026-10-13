/// Home: the profile's conversations, the way into one, more of them, and
/// which profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
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
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
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
    await tester.pumpWidget(home(const []));
    await settle(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.text('New conversation'), findsOneWidget);
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

  testWidgets('with several profiles, the chip switches profile', (tester) async {
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
    // IrisChip upper-cases its label.
    await tester.tap(find.text('DEFAULT'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.tap(find.text('ananta'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListScreen)),
    );
    expect(container.read(activeProfileProvider), 'ananta');
    expect(find.text('ANANTA'), findsOneWidget);
  });

  testWidgets('a single profile shows no chip', (tester) async {
    await tester.pumpWidget(
      home(
        const [],
        profiles: const [AgentProfile(name: 'default', isDefault: true)],
      ),
    );
    await settle(tester);
    expect(find.text('DEFAULT'), findsNothing);
  });
}
