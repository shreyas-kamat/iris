/// Reading `iris_ui` tool calls out of the chat, and the hidden `<iris-action>` envelope out of messages.
///
/// Nothing here logs a program, its data or an action's context (they can hold personal text).
library;

import 'dart:convert';

import '../../core/json.dart';
import 'genui_models.dart';

abstract final class GenUiParser {
  /// The name the agent's tool call carries.
  static const toolName = 'iris_ui';

  /// Hermes defers plugin tools behind these bridges, so a call can name the bridge and carry the real tool inside.
  static const _bridges = {'tool_call', 'mcp__tool_call'};

  /// Whether a tool call named [name] might be an `iris_ui` call (directly, or through a bridge).
  static bool mayBeSurface(String name) =>
      name == toolName || _bridges.contains(name);

  /// The display an `iris_ui` call names, or null when the call is something else or its arguments are unreadable.
  /// [input] is the arguments text; [output] is what the tool answered, when it has.
  static UiSurfaceRef? surfaceRef({
    required String name,
    String? input,
    String? output,
  }) {
    if (!mayBeSurface(name) || input == null) return null;
    var args = _object(input);
    if (_bridges.contains(name)) {
      // A real server stores `{"calls": [{"name": "iris_ui", "arguments": {...}}]}`
      // (seen in the 3.7 live check); a lone call at the top level is also read.
      // With several `iris_ui` calls the last one wins, as the newest does.
      final calls = args['calls'].isList ? args['calls'].list : [args];
      Json? mine;
      for (final call in calls) {
        final inner = call.any(const [
          'tool_name',
          'name',
          'tool',
        ]).stringOrNull;
        if (inner == toolName) mine = call;
      }
      if (mine == null) return null;
      args = _object(mine.any(const ['arguments', 'args', 'input']).raw);
    }
    final id = args['surface_id'].stringOrNull;
    if (id == null || id.isEmpty) return null;

    final answer = _object(output);
    return UiSurfaceRef(
      surfaceId: id,
      placement: SurfacePlacement.parse(args['placement'].stringOrNull),
      code: args['code'].stringOrNull,
      fallback: args['fallback'].stringOrNull,
      template: args['template'].stringOrNull,
      deleted: args['delete'].boolean(),
      accepted: answer['ok'].boolOrNull,
      rev: answer['rev'].intOrNull,
    );
  }

  /// A tolerant decode: text or an already decoded map, anything else is an empty object.
  static Json _object(Object? raw) {
    if (raw is String) {
      final text = raw.trim();
      if (!text.startsWith('{')) return Json.missing;
      try {
        return Json.of(jsonDecode(text));
      } on FormatException {
        return Json.missing;
      }
    }
    return Json.of(raw);
  }
}

/// The hidden part of a message Iris sends when the person acts on a display (spec D9). The visible text is what the
/// person (and the agent) reads as the message; the envelope tells the agent which display and component it came from.
final class IrisActionEnvelope {
  const IrisActionEnvelope({
    required this.surface,
    required this.component,
    this.context,
  });

  final String surface;
  final String component;

  /// Hidden data the display attached (a form's values, a row's id). JSON-shaped.
  final Object? context;

  static const _open = '<iris-action>';
  static const _close = '</iris-action>';

  /// More than this and the context is left out: it would crowd out the conversation and the agent will not read it.
  static const maxContextChars = 4000;

  static final _tag = RegExp(
    '${RegExp.escape(_open)}(.*?)${RegExp.escape(_close)}',
    dotAll: true,
  );

  /// [text] with the envelope appended on its own line.
  String attachTo(String text) {
    final body = <String, Object?>{'surface': surface, 'component': component};
    if (context != null) {
      final encoded = jsonEncode(context);
      if (encoded.length <= maxContextChars) body['context'] = context;
    }
    // `<` only occurs inside JSON strings, where `\u003c` means the same. Escaping it means no context, however it is
    // worded, can contain the closing tag and spill into the text the person reads.
    final encoded = jsonEncode(body).replaceAll('<', '\\u003c');
    return '$text\n$_open$encoded$_close';
  }

  /// Splits a message into what to show and the envelope in it. Every well-formed tag is removed from the text, even
  /// one whose JSON cannot be read (the person should never see it); the envelope is the last readable one.
  static (String, IrisActionEnvelope?) split(String text) {
    if (!text.contains(_open)) return (text, null);
    IrisActionEnvelope? found;
    for (final match in _tag.allMatches(text)) {
      final body = match.group(1)!;
      try {
        final json = Json.of(jsonDecode(body));
        final surface = json['surface'].stringOrNull;
        final component = json['component'].stringOrNull;
        if (surface != null && component != null) {
          found = IrisActionEnvelope(
            surface: surface,
            component: component,
            context: json['context'].raw,
          );
        }
      } on FormatException {
        // Hidden anyway.
      }
    }
    return (text.replaceAll(_tag, '').trimRight(), found);
  }

  /// [text] without any envelope.
  static String strip(String text) => split(text).$1;
}
