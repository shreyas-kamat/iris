import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/components/segmented.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/chat/conversation_search.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

void main() {
  late FakeChatBackend backend;
  setUp(() => backend = FakeChatBackend());
  tearDown(() => backend.close());

  const two = [
    AgentProfile(name: 'default', isDefault: true),
    AgentProfile(name: 'research'),
  ];

  SearchHit hit(String id, String title, {String? profile, DateTime? at}) =>
      SearchHit(
        storedId: id,
        title: title,
        lastActive: at,
        profile: profile,
        snippet: const [SnippetRun('backup failed')],
      );

  Widget home({
    List<AgentProfile> profiles = two,
    List<Override> overrides = const [],
    Future<void>? switching,
  }) => ProviderScope(
    overrides: [
      activeServerProvider.overrideWithValue(
        const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'H'),
      ),
      activeLinkProvider.overrideWith(
        (ref) => Stream.value(const LinkState(LinkPhase.live)),
      ),
      // Rebuilt when the profile changes, as the app's own provider is.
      // [switching], when given, holds back every other profile's backend.
      activeChatProvider.overrideWith((ref) async {
        final profile = ref.watch(activeProfileProvider);
        if (profile != 'default' && switching != null) await switching;
        return backend;
      }),
      conversationsProvider.overrideWith(
        (ref) async => const ConversationPage(
          items: [ConversationSummary(id: 'a', title: 'Fix the build')],
          total: 1,
        ),
      ),
      profilesProvider.overrideWith((ref) async => profiles),
      liveChatsProvider.overrideWith((ref) => Stream.value(const {})),
      ...overrides,
    ],
    child: themed(const ConversationListScreen()),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.tap(find.byType(SearchField));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, text);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the scope bar needs more than one profile and an open search', (
    tester,
  ) async {
    await tester.pumpWidget(home());
    await settle(tester);
    expect(find.byType(IrisSegmented<SearchScope>), findsNothing);
    await tester.tap(find.byType(SearchField));
    await settle(tester);
    expect(find.byType(IrisSegmented<SearchScope>), findsOneWidget);
    expect(find.text('This profile'), findsOneWidget);
    expect(find.text('All profiles'), findsOneWidget);
  });

  testWidgets('a single profile never shows the scope bar', (tester) async {
    await tester.pumpWidget(home(profiles: [two.first]));
    await settle(tester);
    await tester.tap(find.byType(SearchField));
    await settle(tester);
    expect(find.byType(IrisSegmented<SearchScope>), findsNothing);
  });

  testWidgets('this profile searches the current profile only', (tester) async {
    backend.searchResult = Ok([hit('s1', 'Backup notes')]);
    await tester.pumpWidget(home());
    await settle(tester);
    await type(tester, 'backup');
    expect(backend.searches, contains('backup'));
    expect(backend.acrossSearches, isEmpty);
    expect(find.textContaining('Searching default only'), findsOneWidget);
    expect(find.textContaining('research'), findsWidgets);
  });

  testWidgets('all profiles groups hits under profile headers', (tester) async {
    backend.searchAcrossResult = Ok([
      hit('s1', 'Backup notes', profile: 'default', at: DateTime(2026, 10, 2)),
      hit('s2', 'Backup paper', profile: 'research', at: DateTime(2026, 9, 30)),
    ]);
    await tester.pumpWidget(home());
    await settle(tester);
    await tester.tap(find.byType(SearchField));
    await settle(tester);
    await tester.tap(find.text('All profiles'));
    await settle(tester);
    await type(tester, 'backup');
    expect(backend.acrossSearches, ['backup in default,research']);
    expect(find.bySemanticsLabel('default'), findsOneWidget);
    expect(find.bySemanticsLabel('research'), findsOneWidget);
    expect(find.text('Backup notes'), findsOneWidget);
    expect(find.text('Backup paper'), findsOneWidget);
    expect(find.textContaining('Searched default, research'), findsOneWidget);
  });

  testWidgets(
    'tapping a hit under another profile switches to it, then opens',
    (tester) async {
      backend.searchAcrossResult = Ok([
        hit(
          's2',
          'Backup paper',
          profile: 'research',
          at: DateTime(2026, 9, 30),
        ),
      ]);
      await tester.pumpWidget(home());
      await settle(tester);
      await tester.tap(find.byType(SearchField));
      await settle(tester);
      await tester.tap(find.text('All profiles'));
      await settle(tester);
      await type(tester, 'backup');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationListScreen)),
      );
      await tester.tap(find.text('Backup paper'));
      await tester.pumpAndSettle();
      expect(container.read(activeProfileProvider), 'research');
      expect(find.byType(ChatScreen), findsOneWidget);
    },
  );

  testWidgets('a second hit tapped while a profile switch builds is ignored', (
    tester,
  ) async {
    final switching = Completer<void>();
    // Both hits on screen, clear of the floating new-chat bar.
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend.searchAcrossResult = Ok([
      hit('s1', 'Backup notes', profile: 'default', at: DateTime(2026, 10, 2)),
      hit('s2', 'Backup paper', profile: 'research', at: DateTime(2026, 9, 30)),
    ]);
    await tester.pumpWidget(home(switching: switching.future));
    await settle(tester);
    await tester.tap(find.byType(SearchField));
    await settle(tester);
    await tester.tap(find.text('All profiles'));
    await settle(tester);
    await type(tester, 'backup');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListScreen)),
    );
    await tester.tap(find.text('Backup paper'));
    await tester.pump();
    expect(container.read(activeProfileProvider), 'research');
    // The research backend is still being built and the rows are still up.
    await tester.tap(find.text('Backup notes'));
    await tester.pump();
    switching.complete();
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider), 'research');
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('a hit in the current profile opens without switching', (
    tester,
  ) async {
    backend.searchAcrossResult = Ok([
      hit('s1', 'Backup notes', profile: 'default', at: DateTime(2026, 10, 2)),
    ]);
    await tester.pumpWidget(home());
    await settle(tester);
    await tester.tap(find.byType(SearchField));
    await settle(tester);
    await tester.tap(find.text('All profiles'));
    await settle(tester);
    await type(tester, 'backup');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListScreen)),
    );
    await tester.tap(find.text('Backup notes'));
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider), 'default');
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('the scope goes back to this profile when search closes', (
    tester,
  ) async {
    await tester.pumpWidget(home());
    await settle(tester);
    await tester.tap(find.byType(SearchField));
    await settle(tester);
    await tester.tap(find.text('All profiles'));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListScreen)),
    );
    expect(container.read(searchScopeProvider), SearchScope.all);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    expect(container.read(searchScopeProvider), SearchScope.here);
  });
}
