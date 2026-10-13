/// Sessions and the messages inside them.
///
/// These mirror hermes-webui's session objects. Decoding is hand-written rather
/// than generated because generated `fromJson` throws on a type it did not
/// expect, and a session list that fails to decode because one row grew a field
/// is exactly the failure mode Iris exists to avoid. Every reader here goes
/// through [Json] and falls back instead.
library;

import '../../core/json.dart';

/// The author of a message.
enum MessageRole {
  user,
  assistant,
  system,
  tool;

  static MessageRole parse(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'user' || 'human' => MessageRole.user,
        'assistant' || 'ai' || 'model' => MessageRole.assistant,
        'tool' || 'function' || 'tool_result' => MessageRole.tool,
        _ => MessageRole.system,
      };
}

/// A stored message in a session's history.
final class Message {
  const Message({
    required this.role,
    required this.content,
    this.reasoning,
    this.attachments = const [],
    this.toolCalls = const [],
    this.createdAt,
    this.raw = Json.missing,
  });

  factory Message.fromJson(Json json) => Message(
    role: MessageRole.parse(json['role'].stringOrNull),
    content: _readContent(json.any(['content', 'text', 'message'])),
    reasoning: json.any(['reasoning', 'thinking']).stringOrNull,
    attachments: json
        .any(['attachments', 'files'])
        .list
        .map((a) => a.isMap ? a.any(['path', 'name']).string() : a.string())
        .where((a) => a.isNotEmpty)
        .toList(growable: false),
    toolCalls: json
        .any(['tool_calls', 'tools'])
        .mapList(ToolCall.fromJsonOrNull),
    createdAt: json.any(['created_at', 'timestamp', 'ts']).dateTimeOrNull,
    raw: json,
  );

  /// Content arrives as a plain string, or as the multi-part array that
  /// providers use for mixed text and images. Parts are flattened to their text,
  /// which is what the transcript needs; attachments carry the rest.
  static String _readContent(Json json) {
    if (json.isList) {
      return json.list
          .map(
            (part) => part.isMap
                ? part.any(['text', 'content']).string()
                : part.string(),
          )
          .where((text) => text.isNotEmpty)
          .join('\n');
    }
    return json.string();
  }

  final MessageRole role;
  final String content;
  final String? reasoning;
  final List<String> attachments;
  final List<ToolCall> toolCalls;
  final DateTime? createdAt;

  /// The undecoded source, so a future field is reachable without a migration.
  final Json raw;

  bool get isEmpty =>
      content.isEmpty && toolCalls.isEmpty && attachments.isEmpty;
}

/// A recorded tool invocation attached to a message.
final class ToolCall {
  const ToolCall({
    required this.name,
    this.id,
    this.arguments = Json.missing,
    this.result,
    this.error,
  });

  /// Returns `null` for a row that carries no usable name, so [Json.mapList]
  /// can drop it without discarding its siblings.
  static ToolCall? fromJsonOrNull(Json json) {
    final name = json.any([
      'name',
      'tool',
      'tool_name',
      'function',
    ]).stringOrNull;
    if (name == null || name.isEmpty) return null;
    return ToolCall(
      name: name,
      id: json.any(['id', 'call_id', 'tool_call_id']).stringOrNull,
      arguments: json.any(['args', 'arguments', 'input']),
      result: json.any(['result', 'output', 'content']).stringOrNull,
      error: json['error'].stringOrNull,
    );
  }

  final String name;
  final String? id;
  final Json arguments;
  final String? result;
  final String? error;

  bool get failed => error != null && error!.isNotEmpty;
}

/// A conversation, as it appears in the session list.
///
/// [SessionSummary] is what `/api/sessions` returns; a full [Session] adds the
/// message history from `/api/session`. They are separate types so a screen
/// cannot accidentally render a list row as though it had messages loaded.
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    this.workspace,
    this.model,
    this.projectId,
    this.createdAt,
    this.updatedAt,
    this.pinned = false,
    this.archived = false,
    this.tags = const [],
  });

  /// Returns `null` when the row has no session id, which is the one field
  /// nothing downstream can work without.
  static SessionSummary? fromJsonOrNull(Json json) {
    final id = json.any(['session_id', 'id', 'sid']).stringOrNull;
    if (id == null || id.isEmpty) return null;
    return SessionSummary(
      id: id,
      title: json['title'].string(),
      workspace: json['workspace'].stringOrNull,
      model: json['model'].stringOrNull,
      projectId: json.any(['project_id', 'project']).stringOrNull,
      createdAt: json['created_at'].dateTimeOrNull,
      updatedAt: json['updated_at'].dateTimeOrNull,
      pinned: json['pinned'].boolean(),
      archived: json['archived'].boolean(),
      tags: json['tags'].list
          .map((tag) => tag.string())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String id;
  final String title;
  final String? workspace;
  final String? model;
  final String? projectId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool pinned;
  final bool archived;
  final List<String> tags;

  /// A title safe to render. Untitled sessions are common right after creation,
  /// before the server has generated one.
  String get displayTitle => title.trim().isEmpty ? 'New conversation' : title;

  /// Used for ordering the list; falls back through the timestamps that exist.
  DateTime get sortKey =>
      updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// A conversation with its message history loaded.
final class Session {
  const Session({
    required this.summary,
    required this.messages,
    this.raw = Json.missing,
  });

  /// Returns `null` if the payload carries no identifiable session.
  static Session? fromJsonOrNull(Json json) {
    // `/api/session` returns the session at the top level; `done` events nest it
    // under `session`. Accept both so one decoder serves the whole app.
    final body = json['session'].isMap ? json['session'] : json;
    final summary = SessionSummary.fromJsonOrNull(body);
    if (summary == null) return null;
    return Session(
      summary: summary,
      messages: body
          .any(['messages', 'history'])
          .mapList((m) => m.isMap ? Message.fromJson(m) : null),
      raw: body,
    );
  }

  final SessionSummary summary;
  final List<Message> messages;
  final Json raw;

  String get id => summary.id;
}
