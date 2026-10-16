/// Context fill, provider usage and search rows, in every shape Hermes sends.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/usage_parser.dart';

void main() {
  group('context', () {
    test('a fraction becomes a percentage', () {
      final usage = UsageParser.context(
        Json.of({
          'context_percent': 0.18,
          'context_used': 48210,
          'context_max': 272000,
        }),
      )!;
      expect(usage.percent, closeTo(18, 0.001));
      expect(usage.used, 48210);
      expect(usage.max, 272000);
    });

    test('a percentage stays one', () {
      expect(
        UsageParser.context(Json.of({'context_percent': 42}))!.percent,
        42,
      );
    });

    test('without a percent, used over max', () {
      expect(
        UsageParser.context(
          Json.of({'context_used': 50, 'context_max': 200}),
        )!.percent,
        25,
      );
    });

    test('the numbers may sit under usage', () {
      expect(
        UsageParser.context(
          Json.of({
            'usage': {'context_percent': 30, 'context_max': 1000},
          }),
        )!.percent,
        30,
      );
    });

    test('no numbers means no context, not zero', () {
      expect(UsageParser.context(Json.of({'calls': 3, 'total': 10})), isNull);
      expect(UsageParser.context(Json.of({'lazy': true})), isNull);
    });

    test('over a hundred is clamped', () {
      expect(
        UsageParser.context(Json.of({'context_percent': 140}))!.percent,
        100,
      );
    });
  });

  group('provider usage', () {
    test('windows as the gateway sends them', () {
      final usage = UsageParser.providerUsage(
        Json.of({
          'windows': [
            {
              'label': 'Session',
              'used_percent': 73.0,
              'resets_at': '2026-10-14T11:26:44+00:00',
              'scope': 'account',
            },
            {
              'label': 'Weekly',
              'used_percent': 48.0,
              'resets_at': '2026-10-20T05:20:29+00:00',
              'scope': 'account',
            },
          ],
        }),
      )!;
      expect(usage.windows.map((w) => w.label), ['Session', 'Weekly']);
      expect(usage.windows.first.leftPercent, 27);
      expect(
        usage.windows.first.resetsAt?.toUtc(),
        DateTime.utc(2026, 10, 14, 11, 26, 44),
      );
      expect(usage.tightest?.label, 'Session');
    });

    test('a pooled provider reports accounts; the best one leads', () {
      final usage = UsageParser.providerUsage(
        Json.of({
          'accounts': [
            {
              'label': 'work',
              'state': 'limited',
              'windows': [
                {'label': 'Session', 'used_percent': 100},
              ],
            },
            {
              'label': 'home',
              'state': 'ready',
              'windows': [
                {'label': 'Session', 'used_percent': 20},
              ],
            },
          ],
        }),
      )!;
      expect(usage.accounts.map((a) => a.state), [
        UsageAccountState.limited,
        UsageAccountState.ready,
      ]);
      expect(usage.tightest?.usedPercent, 20);
    });

    test('usage clamps and fills in missing labels', () {
      final usage = UsageParser.providerUsage(
        Json.of({
          'windows': [
            {'used_percent': 120, 'scope': 'model'},
          ],
          'accounts': [
            {'state': 'weird', 'windows': <Object>[]},
          ],
        }),
      )!;
      final window = usage.windows.single;
      expect(window.label, 'Usage');
      expect(window.usedPercent, 100);
      expect(window.leftPercent, 0);
      expect(window.accountScoped, isFalse);
      expect(usage.accounts.single.label, 'Account');
      expect(usage.accounts.single.state, UsageAccountState.unknown);
    });

    test('a window without a number is skipped; nothing left means null', () {
      expect(
        UsageParser.providerUsage(
          Json.of({
            'windows': [
              {'label': 'Session'},
            ],
          }),
        ),
        isNull,
      );
      expect(UsageParser.providerUsage(Json.of(null)), isNull);
    });
  });

  group('search', () {
    test('one hit per conversation, in the server order', () {
      final hits = UsageParser.searchHits(
        Json.of({
          'results': [
            {
              'session_id': 'a',
              'title': 'Deploy',
              'snippet': 'the >>>deploy<<< failed',
              'last_active': 1791964543.0,
              'message_count': 4,
            },
            {
              'session_id': 'b',
              'title': null,
              'preview': 'Plans',
              'snippet': 'x',
              'archived': true,
            },
            {'session_id': 'a', 'title': 'Deploy', 'snippet': 'second match'},
          ],
        }),
      );
      expect(hits.map((h) => h.storedId), ['a', 'b']);
      expect(hits.first.snippet.where((r) => r.matched).single.text, 'deploy');
      expect(hits.first.messageCount, 4);
      expect(hits.first.lastActive, isNotNull);
      expect(hits[1].title, 'Plans');
      expect(hits[1].archived, isTrue);
    });

    test('hits count every matching message of a conversation', () {
      final hits = UsageParser.searchHits(
        Json.of({
          'results': [
            {
              'session_id': 'a',
              'title': 'Backup',
              'snippet': '>>>backup<<< one',
            },
            {'session_id': 'b', 'title': 'Runbook', 'snippet': 'restore'},
            {
              'session_id': 'a',
              'title': 'Backup',
              'snippet': '>>>backup<<< two',
            },
            {
              'session_id': 'a',
              'title': 'Backup',
              'snippet': '>>>backup<<< three',
            },
          ],
        }),
      );
      expect(hits.map((h) => (h.storedId, h.matches)), [('a', 3), ('b', 1)]);
      expect(
        hits.first.snippet.any((r) => r.matched),
        isTrue,
        reason: 'the first match is the snippet',
      );
    });

    test('search drops rows without a session id', () {
      final hits = UsageParser.searchHits(
        Json.of({
          'results': [
            {'id': 99, 'title': 'message-only row', 'snippet': 'x'},
          ],
        }),
      );
      expect(hits, isEmpty);
    });

    test('snippets survive broken markers', () {
      expect(UsageParser.snippet('a >>>b c'), [
        isA<SnippetRun>().having((r) => r.text, 'text', 'a '),
        isA<SnippetRun>().having((r) => r.text, 'text', 'b c'),
      ]);
      final runs = UsageParser.snippet('>>><<< plain\n\ttext');
      expect(runs.single.text, ' plain text');
      expect(runs.single.matched, isFalse);
    });
  });
}
