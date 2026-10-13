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
import 'chat_models.dart';

abstract final class HistoryParser {
  /// The conversation list from a `session.list` result.
  static List<ConversationSummary> conversations(Json result) {
    final rows = result.isList ? result.list : result['sessions'].list;
    return [for (final row in rows) ?_conversation(row)];
  }

  static ConversationSummary? _conversation(Json row) {
    final id = firstText(row, const ['id', 'session_id', 'stored_session_id']);
    if (id == null) return null;
    return ConversationSummary(
      id: id,
      title:
          firstText(row, const ['title', 'preview']) ?? 'Untitled conversation',
      startedAt: row
          .any(const ['last_active', 'updated_at', 'started_at'])
          .dateTimeOrNull,
      messageCount: row['message_count'].integer(),
      source: firstText(row, const ['source']),
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
      final content = contentOf(row);
      switch (row['role'].string().trim().toLowerCase()) {
        case 'user':
          if (content.trim().isNotEmpty) {
            items.add(UserTurn(id: id, text: content));
          }
        case 'assistant':
          final turn = AssistantTurn(
            id: id,
            text: content,
            reasoning: row.any(const ['reasoning', 'reasoning_content']).string(),
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

  /// The first of [keys] holding non-blank text, trimmed.
  static String? firstText(Json json, List<String> keys) {
    for (final key in keys) {
      final value = json[key].stringOrNull?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
