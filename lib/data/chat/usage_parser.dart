/// Reads the context window, provider usage and search rows.
///
/// Shapes verified on the user's server on 2026-10-14; see
/// `docs/superpowers/specs/2026-10-14-phase4-design.md`.
library;

import '../../core/json.dart';
import 'chat_models.dart';
import 'history_parser.dart';

abstract final class UsageParser {
  /// Context fill from `session.info`, a `session.usage` event or a resume's
  /// `info`, whose numbers may sit under `usage`. Null when there are no
  /// usable numbers, which a lazy, idle session never has. That is not the
  /// same as an empty window.
  static ContextUsage? context(Json json) {
    final source =
        json['context_percent'].hasValue || json['context_max'].hasValue
        ? json
        : json['usage'];
    final used = source['context_used'].intOrNull;
    final max = source['context_max'].intOrNull;
    var percent = source['context_percent'].doubleOrNull;
    // Hermes has sent both a fraction and a percentage.
    if (percent != null && percent > 0 && percent <= 1) percent *= 100;
    if ((percent == null || percent <= 0) &&
        used != null &&
        max != null &&
        max > 0) {
      percent = used / max * 100;
    }
    if (percent == null) return null;
    if (percent <= 0 && (max == null || max <= 0)) return null;
    return ContextUsage(
      percent: percent.clamp(0, 100).toDouble(),
      used: used,
      max: max == null || max <= 0 ? null : max,
    );
  }

  /// A `model.options` provider row's `usage`.
  static ProviderUsage? providerUsage(Json usage) {
    if (!usage.isMap) return null;
    final windows = _windows(usage['windows']);
    final accounts = [for (final row in usage['accounts'].list) _account(row)];
    if (windows.isEmpty && accounts.isEmpty) return null;
    return ProviderUsage(windows: windows, accounts: accounts);
  }

  static List<UsageWindow> _windows(Json list) => [
    for (final row in list.list)
      if (row['used_percent'].doubleOrNull case final used?)
        UsageWindow(
          label: HistoryParser.firstText(row, const ['label']) ?? 'Usage',
          usedPercent: used.clamp(0, 100).toDouble(),
          resetsAt: row['resets_at'].dateTimeOrNull,
          accountScoped: row['scope'].string('account') != 'model',
        ),
  ];

  static UsageAccount _account(Json row) => UsageAccount(
    label: HistoryParser.firstText(row, const ['label']) ?? 'Account',
    state:
        UsageAccountState.values.asNameMap()[row['state'].string()] ??
        UsageAccountState.unknown,
    windows: _windows(row['windows']),
    resetsAt: row['resets_at'].dateTimeOrNull,
  );

  /// `GET /api/sessions/search`: one row per matching *message*, folded to
  /// one hit per conversation, keeping the server's order and each
  /// conversation's first snippet. A row's `id` may be a message id, so only
  /// `session_id` names the conversation.
  static List<SearchHit> searchHits(Json body) {
    final seen = <String>{};
    final hits = <SearchHit>[];
    for (final row in body['results'].list) {
      final id = HistoryParser.firstText(row, const ['session_id']);
      if (id == null || !seen.add(id)) continue;
      hits.add(
        SearchHit(
          storedId: id,
          title:
              HistoryParser.firstText(row, const ['title', 'preview']) ??
              'Untitled conversation',
          snippet: snippet(row['snippet'].string()),
          lastActive: row.any(const [
            'last_active',
            'session_started',
            'started_at',
          ]).dateTimeOrNull,
          archived: row['archived'].boolean(),
          messageCount: row['message_count'].integer(),
        ),
      );
    }
    return hits;
  }

  /// Hermes marks matched words `>>>like this<<<`. The text is flattened to
  /// one line. A marker left open marks nothing, but still separates the text
  /// before it from the text after; an empty `>>><<<` pair joins its sides.
  static List<SnippetRun> snippet(String raw) {
    final runs = <SnippetRun>[];
    var rest = raw.replaceAll(RegExp(r'\s+'), ' ');
    var plain = '';
    void flush() {
      if (plain.isNotEmpty) runs.add(SnippetRun(plain));
      plain = '';
    }

    while (rest.isNotEmpty) {
      final open = rest.indexOf('>>>');
      if (open < 0) {
        plain += rest;
        break;
      }
      plain += rest.substring(0, open);
      final close = rest.indexOf('<<<', open + 3);
      if (close < 0) {
        // An unclosed marker marks nothing, but still separates the text.
        flush();
        plain = rest.substring(open + 3);
        break;
      }
      final word = rest.substring(open + 3, close);
      if (word.isNotEmpty) {
        flush();
        runs.add(SnippetRun(word, matched: true));
      }
      rest = rest.substring(close + 3);
    }
    flush();
    return runs;
  }
}
