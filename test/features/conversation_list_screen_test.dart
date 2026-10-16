/// Home: the profile's conversations, the way into one, more of them, and
/// which profile.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/chat/conversation_search.dart';
import 'package:iris/features/home/link_status_screen.dart';

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
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: [
      activeServerProvider.overrideWithValue(
        const ServerConfig(
          id: 's',
          baseUrl: 'https://h.example',
          label: 'Home',
        ),
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
      ...overrides,
    ],
    child: themed(const ConversationListScreen()),
  );

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 50));

  testWidgets('the archive toast stays five seconds', (tester) async {
    await tester.pumpWidget(
      home(const [
        ConversationSummary(id: 'stored-1', title: 'Weekly planning'),
      ]),
    );
    await settle(tester);
    await tester.longPress(find.text('Weekly planning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // "Undo" is the toast's own action; the word "Archived" is also a list row.
    await tester.pump(const Duration(milliseconds: 4200));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('the header names the server and the link', (tester) async {
    await tester.pumpWidget(home(const []));
    await settle(tester);
    // The gateway line names the host of the server and the link headline.
    expect(find.text('h.example · Connected'), findsOneWidget);
  });

  testWidgets('lists conversations with when and where they started', (
    tester,
  ) async {
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

  testWidgets('with several profiles, the pill switches profile', (
    tester,
  ) async {
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

  testWidgets('the usage strip sits under the hero when a provider reports', (
    tester,
  ) async {
    backend.modelOptionsResult = const Ok(
      ModelOptions(
        provider: 'openai-codex',
        providers: [
          ModelProvider(
            slug: 'openai-codex',
            name: 'OpenAI Codex',
            models: ['m'],
            isCurrent: true,
            usage: ProviderUsage(
              windows: [UsageWindow(label: 'Session', usedPercent: 10)],
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(home(const []));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI Codex'), findsOneWidget);
  });

  group('the bar folds in the hero', () {
    final rows = [
      for (var i = 0; i < 20; i++)
        ConversationSummary(id: '$i', title: 'Conversation $i'),
    ];

    double offset(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    testWidgets('scrolling the hero away shows the link in the bar', (
      tester,
    ) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      // The bar's own link is not built while the hero is in view.
      expect(find.text('Connected'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      // Back to the top, and it leaves again.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('a short pull settles back to the full hero', (tester) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -30));
      await tester.pumpAndSettle();
      expect(offset(tester), 0);
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('past halfway, it settles into the compact bar', (
      tester,
    ) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
      await tester.pumpAndSettle();
      // Fully folded: the bar's link at full strength, not partway in.
      final link = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Connected'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(link.opacity, 1);
    });

    testWidgets('the compact link opens the link detail', (tester) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connected'));
      // The push, then the route transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LinkStatusScreen), findsOneWidget);
    });
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
      backend.renameResult = const Err(
        IrisFailure(FailureKind.rejected, message: 'nope'),
      );
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

    testWidgets('show more skips past the rows archived here', (tester) async {
      // The server no longer counts 'a', so the next page starts one earlier.
      backend.conversationsResult = const Ok([
        ConversationSummary(id: 'c', title: 'Third'),
      ]);
      await tester.pumpWidget(home(rows, total: 3));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(backend.calls, contains('conversations 1'));
      expect(find.text('Third'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'a refresh in flight keeps archived and renamed rows as they were',
      (tester) async {
        final reload = Completer<void>();
        var asks = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeServerProvider.overrideWithValue(
                const ServerConfig(
                  id: 's',
                  baseUrl: 'https://h.example',
                  label: 'Home',
                ),
              ),
              activeLinkProvider.overrideWith(
                (ref) => Stream.value(const LinkState(LinkPhase.live)),
              ),
              activeChatProvider.overrideWith((ref) async => backend),
              conversationsProvider.overrideWith((ref) async {
                if (asks++ > 0) await reload.future;
                return ConversationPage(items: rows, total: rows.length);
              }),
              profilesProvider.overrideWith((ref) async => const []),
            ],
            child: themed(const ConversationListScreen()),
          ),
        );
        await settle(tester);
        await tester.longPress(find.text('Fix the build'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        // The archive toast is over the lower rows of the next menu (it is
        // taller now, with a Delete row); let the toast go first.
        await tester.pump(const Duration(seconds: 6));
        await tester.longPress(find.text('Plan the week'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(EditableText).last,
          'Plan next week',
        );
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        // Pull down: the list starts loading again, still holding the old rows.
        await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(asks, 2);
        expect(find.text('Fix the build'), findsNothing);
        expect(find.text('Plan next week'), findsOneWidget);
        reload.complete();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('undo after a refresh brings the conversation back', (
      tester,
    ) async {
      var served = List.of(rows);
      backend.onArchived = (id, {required archived}) {
        if (archived) {
          served = [
            for (final r in served)
              if (r.id != id) r,
          ];
        } else {
          served = List.of(rows);
        }
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeServerProvider.overrideWithValue(
              const ServerConfig(
                id: 's',
                baseUrl: 'https://h.example',
                label: 'Home',
              ),
            ),
            activeLinkProvider.overrideWith(
              (ref) => Stream.value(const LinkState(LinkPhase.live)),
            ),
            activeChatProvider.overrideWith((ref) async => backend),
            conversationsProvider.overrideWith(
              (ref) async =>
                  ConversationPage(items: served, total: served.length),
            ),
            profilesProvider.overrideWith((ref) async => const []),
          ],
          child: themed(const ConversationListScreen()),
        ),
      );
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      // The list is fetched again before Undo is tapped: it no longer holds 'a'.
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(served.length, 1);
      expect(find.text('Fix the build'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Fix the build'), findsOneWidget);
    });

    testWidgets('Archived opens the archived screen', (tester) async {
      backend.archivedResult = const Ok([
        ConversationSummary(id: 'z', title: 'Old notes'),
      ]);
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Archived'),
        200,
        // The list, not the search field's own scrollable.
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      expect(find.text('Old notes'), findsOneWidget);
    });
  });

  group('search', () {
    final rows = [
      const ConversationSummary(id: 'a', title: 'Fix the build'),
      const ConversationSummary(id: 'b', title: 'Plan the week'),
    ];

    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchField),
          matching: find.byType(EditableText),
        ),
        query,
      );
      await tester.pump();
    }

    testWidgets('typing filters at once, then the server answers', (
      tester,
    ) async {
      backend.searchResult = const Ok([
        SearchHit(
          storedId: 'c',
          title: 'Deploy notes',
          snippet: [
            SnippetRun('the '),
            SnippetRun('build', matched: true),
            SnippetRun(' broke'),
          ],
        ),
      ]);
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await search(tester, 'build');
      // Local first: the loaded row whose title matches.
      expect(find.text('Fix the build'), findsOneWidget);
      expect(find.text('Plan the week'), findsNothing);
      // After the pause, the server's hits replace it.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(backend.searches, ['build']);
      expect(find.text('Deploy notes'), findsOneWidget);
      expect(find.text('the build broke', findRichText: true), findsOneWidget);
    });

    testWidgets('archived hits are left out', (tester) async {
      backend.searchResult = const Ok([
        SearchHit(storedId: 'c', title: 'Old one', archived: true),
      ]);
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await search(tester, 'old');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Old one'), findsNothing);
      expect(find.text('No chats mention \u2018old\u2019.'), findsOneWidget);
    });

    testWidgets('a failed server search keeps the local matches', (
      tester,
    ) async {
      backend.searchResult = const Err(IrisFailure(FailureKind.offline));
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await search(tester, 'week');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Plan the week'), findsOneWidget);
      expect(find.text("Couldn't search the server"), findsOneWidget);
    });

    testWidgets('a conversation archived here is left out of the matches', (
      tester,
    ) async {
      backend.searchResult = const Ok([
        SearchHit(storedId: 'a', title: 'Fix the build'),
        SearchHit(storedId: 'c', title: 'Build notes'),
      ]);
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await search(tester, 'build');
      // Local matches first, then the server's hits (which still list 'a').
      expect(find.text('Fix the build'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Build notes'), findsOneWidget);
      expect(find.text('Fix the build'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a title changed here is what search matches and shows', (
      tester,
    ) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await tester.longPress(find.text('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Ship the app');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await search(tester, 'ship');
      expect(find.text('Ship the app'), findsOneWidget);
      await search(tester, 'build');
      expect(find.text('Ship the app'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('clearing the field brings the list back', (tester) async {
      await tester.pumpWidget(home(rows));
      await settle(tester);
      await search(tester, 'week');
      await tester.tap(find.bySemanticsLabel('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Fix the build'), findsOneWidget);
      expect(find.text('Plan the week'), findsOneWidget);
    });
  });

  test('local matches compare case-insensitively on the title', () {
    final rows = [
      const ConversationSummary(id: 'a', title: 'Fix The Build'),
      const ConversationSummary(id: 'b', title: 'Plan'),
    ];
    expect(localMatches(rows, 'the b').map((r) => r.id), ['a']);
    expect(localMatches(rows, '  '), rows);
  });

  Future<void> openDelete(WidgetTester tester) async {
    await tester.pumpWidget(
      home(const [
        ConversationSummary(id: 'stored-1', title: 'Weekly planning'),
      ]),
    );
    await settle(tester);
    await tester.longPress(find.text('Weekly planning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'long-press, Delete, confirm removes the row and tells the server',
    (tester) async {
      await openDelete(tester);
      // The confirm sheet's button is now the only "Delete" on screen.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(backend.deletes, ['stored-1']);
      expect(find.text('Weekly planning'), findsNothing);
    },
  );

  testWidgets('a live chat refuses to delete and the row stays', (
    tester,
  ) async {
    backend.deleteResult = const Err(
      IrisFailure(
        FailureKind.rejected,
        message: 'cannot delete an active session',
      ),
    );
    await openDelete(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly planning'), findsOneWidget);
    expect(
      find.text('Stop the reply before deleting this chat.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the confirm deletes nothing', (tester) async {
    await openDelete(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.deletes, isEmpty);
    expect(find.text('Weekly planning'), findsOneWidget);
  });

  const twoChats = [
    ConversationSummary(id: 'stored-1', title: 'Weekly planning'),
    ConversationSummary(id: 'stored-2', title: 'Runbook'),
  ];

  testWidgets('Pinned sits above Recent and is hidden when nothing is pinned', (
    tester,
  ) async {
    await tester.pumpWidget(home(twoChats));
    await settle(tester);
    expect(find.text('PINNED'), findsNothing);
    await tester.longPress(find.text('Runbook'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('PINNED')).dy,
      lessThan(tester.getTopLeft(find.text('RECENT')).dy),
    );
    expect(
      find.text('Runbook'),
      findsOneWidget,
      reason: 'listed once, not twice',
    );
  });

  testWidgets(
    'the menu offers Unpin for a pinned chat, and unpinning hides the section',
    (tester) async {
      await tester.pumpWidget(
        home(
          twoChats,
          overrides: [
            pinsProvider.overrideWith(() => _PinnedAlready(['stored-2'])),
          ],
        ),
      );
      await settle(tester);
      expect(find.text('PINNED'), findsOneWidget);
      await tester.longPress(find.text('Runbook'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsNothing);
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(find.text('PINNED'), findsNothing);
    },
  );

  testWidgets('replying chats show in Live with a state chip', (tester) async {
    await tester.pumpWidget(
      home(
        twoChats,
        overrides: [
          liveChatsProvider.overrideWith(
            (ref) => Stream.value({
              'stored-1': const LiveStatus(
                runtimeId: 'r1',
                storedId: 'stored-1',
                status: 'working',
              ),
            }),
          ),
        ],
      ),
    );
    await settle(tester);
    await settle(tester);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('REPLYING'), findsOneWidget);
  });

  testWidgets(
    'a pin on a chat outside the loaded page is read once and shown',
    (tester) async {
      backend.conversationResult = const Ok(
        ConversationSummary(id: 'old-1', title: 'Old notes'),
      );
      await tester.pumpWidget(
        home(
          twoChats,
          overrides: [
            pinsProvider.overrideWith(() => _PinnedAlready(['old-1'])),
          ],
        ),
      );
      await settle(tester);
      await settle(tester);
      expect(backend.conversationReads, ['old-1']);
      expect(find.text('Old notes'), findsOneWidget);
      expect(find.text('PINNED'), findsOneWidget);
    },
  );

  testWidgets('a pin on a chat that no longer exists is dropped quietly', (
    tester,
  ) async {
    await tester.pumpWidget(
      home(
        twoChats,
        overrides: [
          pinsProvider.overrideWith(() => _PinnedAlready(['gone-1'])),
        ],
      ),
    );
    await settle(tester);
    await settle(tester);
    expect(backend.conversationReads, ['gone-1']);
    expect(find.text('PINNED'), findsNothing);
  });

  testWidgets(
    'Branch from the menu copies the chat, remembers the parent and opens the child',
    (tester) async {
      await tester.pumpWidget(
        home(const [
          ConversationSummary(id: 'stored-1', title: 'Weekly planning'),
        ]),
      );
      await settle(tester);
      await tester.longPress(find.text('Weekly planning'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Branch'));
      await tester.pumpAndSettle();
      expect(backend.branches, ['stored-1']);
      expect(find.textContaining('Branched from'), findsOneWidget);
    },
  );

  group('search results', () {
    const threeChats = [
      ConversationSummary(id: 'a', title: 'Nightly backup to cold storage'),
      ConversationSummary(id: 'b', title: 'Investigate worker heartbeat gaps'),
      ConversationSummary(id: 'c', title: 'Hermes server runbook'),
    ];

    List<SearchHit> threeHits() => [
      SearchHit(
        storedId: 'a',
        title: 'Nightly backup to cold storage',
        matches: 4,
        lastActive: DateTime.now(),
        snippet: const [
          SnippetRun('…the '),
          SnippetRun('backup', matched: true),
          SnippetRun(' at 02:00 saturates the disk…'),
        ],
      ),
      SearchHit(
        storedId: 'b',
        title: 'Investigate worker heartbeat gaps',
        matches: 2,
        lastActive: DateTime.now(),
        snippet: const [
          SnippetRun('move the '),
          SnippetRun('backup', matched: true),
          SnippetRun(' to 04:30'),
        ],
      ),
      SearchHit(
        storedId: 'c',
        title: 'Hermes server runbook',
        lastActive: DateTime.now(),
        snippet: const [
          SnippetRun('Restore from the cold '),
          SnippetRun('backup', matched: true),
        ],
      ),
    ];

    /// Types [query] and lets the 200 ms debounce and the server answer land.
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(EditableText), query);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    bool marked(InlineSpan span, Color color) {
      var found = false;
      span.visitChildren((s) {
        if (s is TextSpan && s.style?.backgroundColor == color) found = true;
        return true;
      });
      return found;
    }

    testWidgets(
      'results are headed by chats and matches, with each hit’s own count',
      (tester) async {
        backend.searchResult = Ok(threeHits());
        await tester.pumpWidget(home(threeChats));
        await settle(tester);
        await type(tester, 'backup');
        expect(find.text('3 CHATS · 7 MATCHES'), findsOneWidget);
        expect(find.textContaining('4 matches'), findsOneWidget);
        expect(find.textContaining('1 match'), findsOneWidget);
      },
    );

    testWidgets('matched words are highlighted in the snippet', (tester) async {
      backend.searchResult = Ok(threeHits());
      await tester.pumpWidget(home(threeChats));
      await settle(tester);
      await type(tester, 'backup');
      final quiet = IrisThemeData(
        skin: IrisSkin.aperture,
        isDark: true,
      ).palette.accentQuiet;
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null && marked(w.textSpan!, quiet),
        ),
        findsWidgets,
      );
    });

    testWidgets('an empty focused field shows recent searches, newest first', (
      tester,
    ) async {
      await tester.pumpWidget(
        home(
          threeChats,
          overrides: [
            recentSearchesProvider.overrideWith(
              () => _RecentAlready(['heartbeat', 'passkey']),
            ),
          ],
        ),
      );
      await settle(tester);
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      expect(find.text('RECENT SEARCHES'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('heartbeat')).dx,
        lessThan(tester.getTopLeft(find.text('passkey')).dx),
      );
      await tester.tap(find.text('passkey'));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'passkey',
      );
    });

    testWidgets('Clear forgets the recent searches', (tester) async {
      await tester.pumpWidget(
        home(
          threeChats,
          overrides: [
            recentSearchesProvider.overrideWith(
              () => _RecentAlready(['heartbeat']),
            ),
          ],
        ),
      );
      await settle(tester);
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('heartbeat'), findsNothing);
    });

    testWidgets(
      'a search that finds nothing says what was searched and how to retry',
      (tester) async {
        backend.searchResult = const Ok([]);
        await tester.pumpWidget(home(threeChats));
        await settle(tester);
        await type(tester, 'kubernetes');
        expect(
          find.text('No chats mention \u2018kubernetes\u2019.'),
          findsOneWidget,
        );
        expect(
          find.text('Try fewer words or a different spelling.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a search that found something is remembered once', (
      tester,
    ) async {
      backend.searchResult = Ok(threeHits());
      await tester.pumpWidget(home(threeChats));
      await settle(tester);
      await type(tester, 'backup');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationListScreen)),
      );
      expect(container.read(recentSearchesProvider), ['backup']);
      await type(tester, '');
      await type(tester, 'backup');
      expect(container.read(recentSearchesProvider), ['backup']);
    });

    testWidgets('a search that found nothing is not remembered', (
      tester,
    ) async {
      backend.searchResult = const Ok([]);
      await tester.pumpWidget(home(threeChats));
      await settle(tester);
      await type(tester, 'kubernetes');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationListScreen)),
      );
      expect(container.read(recentSearchesProvider), isEmpty);
    });
  });
}

class _PinnedAlready extends Pins {
  _PinnedAlready(this.ids);

  final List<String> ids;

  @override
  List<String> build() => ids;
}

class _RecentAlready extends RecentSearches {
  _RecentAlready(this.queries);

  final List<String> queries;

  @override
  List<String> build() => queries;
}
