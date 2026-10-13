/// What happens in a conversation while it is open, as Iris understands it.
///
/// The gateway's stream events and server requests are parsed here into a
/// small closed set, so the transcript logic switches over types the compiler
/// checks instead of strings. Field fallbacks follow Hermes Conduit's
/// `StreamEventParser`, which tracks every spelling Hermes has used.
library;

import '../../core/json.dart';
import '../rpc/rpc_frame.dart';
import 'chat_models.dart';
import 'history_parser.dart';

sealed class ChatEvent {
  const ChatEvent(this.sessionId);

  /// The live session it belongs to. Empty when the gateway named none.
  final String sessionId;

  static const _toolIdKeys = ['tool_id', 'tool_call_id', 'call_id'];

  /// The chat event for a stream [event], or null for one chat does not use.
  static ChatEvent? fromEvent(RpcEvent event) {
    final session = event.sessionId ?? '';
    final payload = event.payload;
    switch (event.type) {
      case 'message.start':
        return MessageStarted(session);
      case 'message.delta':
        final delta =
            payload['text'].stringOrNull ??
            event.raw['text'].stringOrNull ??
            '';
        return delta.isEmpty ? null : TextDelta(session, delta);
      case 'thinking.delta' ||
          'reasoning.delta' ||
          'message.reasoning' ||
          'message.reasoning.delta':
        final thought =
            payload.any(const [
              'reasoning',
              'reasoning_content',
              'text',
              'content',
            ]).stringOrNull ??
            event.raw.any(const ['reasoning', 'text']).stringOrNull ??
            '';
        return thought.isEmpty ? null : ReasoningDelta(session, thought);
      case 'message.complete':
        return MessageCompleted(
          session,
          content: payload.any(const [
            'content',
            'text',
            'rendered',
          ]).stringOrNull,
          reasoning: payload['reasoning'].stringOrNull,
        );
      case 'tool.start' || 'tool_call':
        return ToolStarted(
          session,
          toolId: HistoryParser.firstText(payload, _toolIdKeys),
          name:
              HistoryParser.firstText(payload, const ['name', 'tool_name']) ??
              'tool',
          input: _text(
            payload.any(const [
              'args_text',
              'context',
              'input',
              'arguments',
              'args',
            ]),
          ),
        );
      case 'tool.complete' || 'tool_result':
        return ToolCompleted(
          session,
          toolId: HistoryParser.firstText(payload, _toolIdKeys),
          name:
              HistoryParser.firstText(payload, const ['name', 'tool_name']) ??
              'tool',
          output: _text(payload.any(const ['output', 'result'])),
          failed: payload['is_error'].boolean() || payload['error'].hasValue,
        );
      case 'error':
        return TurnFailed(
          session,
          payload['message'].stringOrNull ?? 'Hermes reported an error.',
        );
      case 'message.interrupted' || 'session.interrupted':
        return TurnInterrupted(session);
      case 'session.busy':
        return BusyChanged(session, busy: payload['busy'].boolean());
      case 'session.title':
        final title = HistoryParser.firstText(payload, const ['title']);
        return title == null ? null : TitleChanged(session, title);
      case 'approval.request':
        final approval = parseApproval(payload, session);
        return approval == null ? null : ApprovalAsked(approval);
      case 'clarify' || 'clarify.request':
        final clarify = parseClarify(payload, session);
        return clarify == null ? null : ClarifyAsked(clarify);
      case 'clarify.expire':
        final expired = HistoryParser.firstText(payload, const [
          'request_id',
          'requestId',
        ]);
        return expired == null ? null : RequestWithdrawn(session, expired);
      case 'request.cancel':
        final cancelled = HistoryParser.firstText(payload, const [
          'id',
          'request_id',
        ]);
        return cancelled == null ? null : RequestWithdrawn(session, cancelled);
      case 'session.info' || 'model.update':
        final model = HistoryParser.firstText(payload, const ['model']);
        return model == null
            ? null
            : ModelChanged(
                session,
                model: model,
                provider: HistoryParser.firstText(payload, const ['provider']),
              );
      default:
        return null;
    }
  }

  /// The chat event for a presented server [request], or null.
  static ChatEvent? fromServerRequest(RpcServerRequest request) {
    final session = request.params['session_id'].string();
    switch (request.method) {
      case 'approval':
        final approval = parseApproval(
          request.params,
          session,
          serverRequestId: request.id,
        );
        return approval == null ? null : ApprovalAsked(approval);
      case 'clarify':
        final clarify = parseClarify(
          request.params,
          session,
          requestId: request.id,
        );
        return clarify == null ? null : ClarifyAsked(clarify);
      default:
        return null;
    }
  }

  /// An approval from an `approval.request` payload or `approval` request
  /// params. Null without a session, which nothing could answer.
  static ApprovalRequest? parseApproval(
    Json payload,
    String sessionId, {
    String? serverRequestId,
  }) {
    if (sessionId.isEmpty) return null;
    final offered = <String>[];
    for (final choice in payload['choices'].list) {
      final value = choice.stringOrNull?.trim();
      if (value != null && value.isNotEmpty && !offered.contains(value)) {
        offered.add(value);
      }
    }
    final permanent = payload['allow_permanent'].boolOrNull ?? true;
    return ApprovalRequest(
      sessionId: sessionId,
      command:
          HistoryParser.firstText(payload, const ['command', 'code', 'text']) ??
          '',
      description:
          HistoryParser.firstText(payload, const [
            'description',
            'message',
            'prompt',
          ]) ??
          'Approval required',
      choices: offered.isNotEmpty
          ? offered
          : ['once', 'session', if (permanent) 'always', 'deny'],
      queueId: HistoryParser.firstText(payload, const [
        'request_id',
        'requestId',
      ]),
      serverRequestId: serverRequestId,
    );
  }

  /// A clarifying question from a `clarify.request` payload or `clarify`
  /// request params. Null when it asks nothing.
  static ClarifyRequest? parseClarify(
    Json payload,
    String sessionId, {
    String? requestId,
  }) {
    final id =
        requestId ??
        HistoryParser.firstText(payload, const [
          'request_id',
          'requestId',
          'id',
        ]);
    if (id == null || id.isEmpty) return null;
    final questions = <ClarifyQuestion>[];
    for (final entry in payload['questions'].list) {
      final text = HistoryParser.firstText(entry, const [
        'question',
        'prompt',
        'text',
      ]);
      final qid = HistoryParser.firstText(entry, const [
        'qid',
        'question_id',
        'id',
      ]);
      if (text == null || qid == null || questions.any((q) => q.id == qid)) {
        continue;
      }
      questions.add(
        ClarifyQuestion(id: qid, text: text, choices: _choices(entry)),
      );
    }
    if (questions.isEmpty) {
      final text = HistoryParser.firstText(payload, const [
        'question',
        'prompt',
        'text',
      ]);
      if (text == null) return null;
      questions.add(
        ClarifyQuestion(
          id: 'q0',
          text: text,
          choices: _choices(payload),
          synthetic: true,
        ),
      );
    }
    return ClarifyRequest(
      requestId: id,
      sessionId: sessionId,
      questions: questions,
    );
  }

  /// Offered answers: plain strings, or `{label, value}` objects.
  static List<ClarifyChoice> _choices(Json json) {
    final raw = json['choices'].hasValue ? json['choices'] : json['options'];
    final choices = <ClarifyChoice>[];
    for (final entry in raw.list) {
      final label =
          entry.stringOrNull?.trim() ??
          HistoryParser.firstText(entry, const [
            'label',
            'title',
            'text',
            'name',
            'value',
          ]);
      if (label == null || label.isEmpty) continue;
      final value =
          entry.stringOrNull?.trim() ??
          HistoryParser.firstText(entry, const ['value', 'answer', 'id']) ??
          label;
      if (choices.any((c) => c.value == value)) continue;
      choices.add(ClarifyChoice(label: label, value: value));
    }
    return choices;
  }

  /// Text for a value that may be a string or structured JSON.
  static String? _text(Json value) {
    if (value.isNull) return null;
    return value.stringOrNull ?? value.encode();
  }
}

/// The agent began a reply.
final class MessageStarted extends ChatEvent {
  const MessageStarted(super.sessionId);
}

/// More reply text.
final class TextDelta extends ChatEvent {
  const TextDelta(super.sessionId, this.text);

  final String text;
}

/// More visible thinking.
final class ReasoningDelta extends ChatEvent {
  const ReasoningDelta(super.sessionId, this.text);

  final String text;
}

/// The reply is complete. [content] is the whole message when the gateway
/// sends it.
final class MessageCompleted extends ChatEvent {
  const MessageCompleted(super.sessionId, {this.content, this.reasoning});

  final String? content;
  final String? reasoning;
}

final class ToolStarted extends ChatEvent {
  const ToolStarted(
    super.sessionId, {
    required this.name,
    this.toolId,
    this.input,
  });

  final String name;
  final String? toolId;
  final String? input;
}

final class ToolCompleted extends ChatEvent {
  const ToolCompleted(
    super.sessionId, {
    required this.name,
    this.toolId,
    this.output,
    this.failed = false,
  });

  final String name;
  final String? toolId;
  final String? output;
  final bool failed;
}

/// The turn failed; [message] says why.
final class TurnFailed extends ChatEvent {
  const TurnFailed(super.sessionId, this.message);

  final String message;
}

/// The turn was stopped.
final class TurnInterrupted extends ChatEvent {
  const TurnInterrupted(super.sessionId);
}

/// The session started or stopped working.
final class BusyChanged extends ChatEvent {
  const BusyChanged(super.sessionId, {required this.busy});

  final bool busy;
}

final class TitleChanged extends ChatEvent {
  const TitleChanged(super.sessionId, this.title);

  final String title;
}

final class ApprovalAsked extends ChatEvent {
  ApprovalAsked(this.request) : super(request.sessionId);

  final ApprovalRequest request;
}

final class ClarifyAsked extends ChatEvent {
  ClarifyAsked(this.request) : super(request.sessionId);

  final ClarifyRequest request;
}

/// The gateway withdrew a request — answered elsewhere, timed out, or the
/// turn ended.
final class RequestWithdrawn extends ChatEvent {
  const RequestWithdrawn(super.sessionId, this.requestId);

  final String requestId;
}

/// The model the session runs on, as the gateway reports it.
final class ModelChanged extends ChatEvent {
  const ModelChanged(super.sessionId, {required this.model, this.provider});

  final String model;
  final String? provider;
}
