import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/automation/kanban_models.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/components/segmented.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/chat/conversation_search.dart';

import '../support/fake_automation.dart';
import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;
  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  ServerCapabilities caps(Set<ServerCapability> available) =>
      ServerCapabilities(available: available, probedAt: DateTime(2026, 10, 17));

  Widget home(
    ServerCapabilities capabilities, {
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: [
      activeServerProvider.overrideWithValue(
        const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'Home'),
      ),
      activeLinkProvider.overrideWith(
        (ref) => Stream.value(const LinkState(LinkPhase.live)),
      ),
      activeCapabilitiesProvider.overrideWith(
        (ref) => Stream.value(capabilities),
      ),
      activeChatProvider.overrideWith((ref) async => backend),
      conversationsProvider.overrideWith(
        (ref) async => const ConversationPage(
          items: [ConversationSummary(id: 'a', title: 'Fix the build')],
          total: 1,
        ),
      ),
      profilesProvider.overrideWith((ref) async => const []),
      liveChatsProvider.overrideWith((ref) => Stream.value(const {})),
      cronJobsProvider.overrideWith(
        (ref) => Stream.value([fakeJob('j1', name: 'Morning digest')]),
      ),
      kanbanBoardProvider.overrideWith(
        (ref) => Stream.value(
          KanbanBoard(
            columns: [
              KanbanColumn(id: 'todo', tasks: [fakeTask('t_1', title: 'Write notes')]),
            ],
          ),
        ),
      ),
      ...overrides,
    ],
    child: themed(const ConversationListScreen()),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a server with neither capability looks as it always did', (
    tester,
  ) async {
    await tester.pumpWidget(home(caps({ServerCapability.profiles})));
    await settle(tester);
    expect(find.byType(IrisSegmented<HomeTab>), findsNothing);
    expect(find.text('h.example · Connected'), findsOneWidget);
    expect(find.text('Fix the build'), findsOneWidget);
  });

  testWidgets('a server that has not been probed shows no control', (
    tester,
  ) async {
    await tester.pumpWidget(home(const ServerCapabilities.unknown()));
    await settle(tester);
    expect(find.byType(IrisSegmented<HomeTab>), findsNothing);
  });

  testWidgets('cron only gives two segments', (tester) async {
    await tester.pumpWidget(home(caps({ServerCapability.cronJobs})));
    await settle(tester);
    expect(find.byType(IrisSegmented<HomeTab>), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);
  });

  testWidgets('both give three, and each shows its own content', (tester) async {
    await tester.pumpWidget(
      home(caps({ServerCapability.cronJobs, ServerCapability.kanban})),
    );
    await settle(tester);
    expect(find.text('Fix the build'), findsOneWidget);

    await tester.tap(find.text('Scheduled'));
    await settle(tester);
    expect(find.text('Morning digest'), findsOneWidget);
    expect(find.text('Fix the build'), findsNothing);

    await tester.tap(find.text('Tasks'));
    await settle(tester);
    expect(find.text('Write notes'), findsOneWidget);
    expect(find.text('Morning digest'), findsNothing);

    await tester.tap(find.text('Sessions'));
    await settle(tester);
    expect(find.text('Fix the build'), findsOneWidget);
  });

  testWidgets('search belongs to Sessions only', (tester) async {
    await tester.pumpWidget(
      home(caps({ServerCapability.cronJobs, ServerCapability.kanban})),
    );
    await settle(tester);
    expect(find.byType(SearchField), findsOneWidget);
    await tester.tap(find.text('Scheduled'));
    await settle(tester);
    expect(find.byType(SearchField), findsNothing);
  });

  testWidgets('the Ask bar is on every tab', (tester) async {
    await tester.pumpWidget(
      home(caps({ServerCapability.cronJobs, ServerCapability.kanban})),
    );
    await settle(tester);
    for (final tab in ['Sessions', 'Scheduled', 'Tasks']) {
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(find.text('Ask Iris anything…'), findsOneWidget, reason: tab);
    }
  });
}
