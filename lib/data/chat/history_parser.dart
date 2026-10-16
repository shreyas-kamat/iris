/// Reads conversation lists and stored transcripts from the dashboard.
///
/// Shapes verified against Hermes 0.18.2 on 2026-10-13: `session.list` returns
/// `{sessions: [{id, title, preview, started_at, message_count, source}]}`,
/// and `GET /api/sessions/{id}/messages` returns `{session_id, messages,
/// pagination}` where each row has a string `content`, a `role` of `user`,
/// `assistant` or `tool`, OpenAI-style `tool_calls` on assistant rows, and
/// `tool_call_id` plus `tool_name` on tool rows. Older rows carried `content`
/// as a list of parts; both are read.
library;

import '../../core/json.dart';
import 'attachment.dart';
import 'chat_models.dart';

abstract final class HistoryParser {
  /// The conversation list from a `session.list` result.
  static List<ConversationSummary> conversations(Json result) {
    final rows = result.isList ? result.list : result['sessions'].list;
    return [for (final row in rows) ?conversationRow(row)];
  }

  static ConversationSummary? conversationRow(Json row) {
    final id = firstText(row, const ['id', 'session_id', 'stored_session_id']);
    if (id == null) return null;
    return ConversationSummary(
      id: id,
      title:
          firstText(row, const ['title', 'preview']) ?? 'Untitled conversation',
      startedAt: row.any(const [
        'last_active',
        'updated_at',
        'started_at',
      ]).dateTimeOrNull,
      messageCount: row['message_count'].integer(),
      source: firstText(row, const ['source']),
      profile: firstText(row, const ['profile']),
    );
  }

  /// A stored transcript, oldest first, from a `/messages` response body.
  static List<TranscriptItem> transcript(Json body) {
    final rows = body.isList ? body.list : body['messages'].list;
    final items = <TranscriptItem>[];
    // Tool results name the call they answer; this finds its card.
    final callAt = <String, int>{};
    for (final (index, row) in rows.indexed) {
      // Model-facing scaffolding that Hermes marks as never shown.
      if (row['display_kind'].string().trim() == 'hidden') continue;
      final id = row['id'].stringOrNull ?? 'row-$index';
      final role = row['role'].string().trim().toLowerCase();
      // Tool output and Hermes's own display projection are shown as given;
      // anything else may carry context-compaction scaffolding.
      final visible = role == 'tool' || row['display_content'].hasValue
          ? contentOf(row)
          : withoutCompaction(row, contentOf(row));
      if (visible == null) continue;
      final content = visible;
      switch (role) {
        case 'user':
          final (files, text) = splitReferences(content);
          if (text.trim().isNotEmpty || files.isNotEmpty) {
            items.add(
              UserTurn(
                id: id,
                text: text,
                attachments: files,
                steered: row['display_kind'].string().trim() == 'steer',
              ),
            );
          }
        case 'assistant':
          final turn = AssistantTurn(
            id: id,
            text: content,
            reasoning: row.any(const [
              'reasoning',
              'reasoning_content',
            ]).string(),
          );
          if (!turn.isEmpty) items.add(turn);
          for (final (n, call) in row['tool_calls'].list.indexed) {
            final callId =
                firstText(call, const ['id', 'call_id']) ?? '$id-call-$n';
            final function = call['function'];
            callAt[callId] = items.length;
            items.add(
              ToolCall(
                id: callId,
                name:
                    firstText(function, const ['name']) ??
                    firstText(call, const ['name']) ??
                    'tool',
                arguments:
                    function['arguments'].stringOrNull ??
                    call['arguments'].stringOrNull,
              ),
            );
          }
        case 'tool':
          final callId = firstText(row, const ['tool_call_id', 'call_id']);
          final at = callId == null ? null : callAt[callId];
          final matched = at == null ? null : items[at];
          if (at != null && matched is ToolCall) {
            items[at] = matched.copyWith(output: content);
          } else {
            items.add(
              ToolCall(
                id: callId ?? id,
                name: firstText(row, const ['tool_name', 'name']) ?? 'tool',
                output: content,
              ),
            );
          }
        default:
          // System prompts and roles this build does not know stay hidden.
          break;
      }
    }
    return items;
  }

  /// The visible text of a row. `display_content` wins when Hermes projected
  /// one; `content` is a string today and a list of parts on older rows.
  static String contentOf(Json row) {
    final projected = row['display_content'].stringOrNull;
    if (projected != null) return projected;
    final content = row.any(const ['content', 'text']);
    if (content.stringOrNull case final text?) return text;
    final parts = <String>[];
    for (final part in content.list) {
      final text =
          part.stringOrNull ?? part.any(const ['text', 'content']).stringOrNull;
      if (text != null && text.isNotEmpty) parts.add(text);
    }
    return parts.join('\n');
  }

  /// Marks Hermes puts around model-facing context-compaction text, which a
  /// person never wrote and should not read as a message. Matched as Hermes
  /// Conduit does.
  static const _compactionDelimiter =
      '[END OF PRIOR CONTEXT — COMPACTION SUMMARY BELOW]';
  static const _priorContextHeader =
      '[PRIOR CONTEXT — for reference only; not a new message]';

  /// [content] with compaction scaffolding removed, or null when nothing a
  /// person said is left: a standalone summary, a merged row whose genuine
  /// prompt is empty, or a row flagged as a summary.
  static String? withoutCompaction(Json row, String content) {
    if (_isSummary(content)) return null;
    final cut = content.indexOf(_compactionDelimiter);
    if (cut >= 0) {
      // A merged row: the genuine prompt sits before the delimiter, behind an
      // optional header that is stripped only when it leads.
      var visible = content.substring(0, cut).trim();
      if (visible.startsWith(_priorContextHeader)) {
        visible = visible.substring(_priorContextHeader.length).trim();
      }
      return visible.isEmpty || _isSummary(visible) ? null : visible;
    }
    final flagged =
        row['_compressed_summary'].boolean() ||
        row['metadata']['_compressed_summary'].boolean();
    return flagged ? null : content;
  }

  /// Whether [content] opens with one of Hermes's summary headers. Only the
  /// start counts, so a person talking about compaction mid-message is kept.
  static bool _isSummary(String content) {
    final head = content.trimLeft();
    final start = head
        .substring(0, head.length < 32 ? head.length : 32)
        .toLowerCase();
    return start.startsWith('[context compaction') ||
        start.startsWith('[context summary]:') ||
        start.startsWith('[recent summary (');
  }

  /// The first of [keys] holding non-blank text, trimmed.
  static String? firstText(Json json, List<String> keys) {
    for (final key in keys) {
      final value = json[key].stringOrNull?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
