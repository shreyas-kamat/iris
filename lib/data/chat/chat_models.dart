/// What a conversation is made of, as Iris shows it.
///
/// These are view values, not wire formats: the parsers in this folder read
/// whatever shape the dashboard sends and produce these, so a renamed server
/// field is fixed in one parser rather than in every widget.
library;

import 'package:flutter/foundation.dart';

/// One row of the conversation list.
@immutable
final class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    this.startedAt,
    this.messageCount = 0,
    this.source,
    this.profile,
  });

  /// The stored session id: what history and resume are addressed by.
  final String id;
  final String title;
  final DateTime? startedAt;
  final int messageCount;

  /// Where the conversation began — `telegram`, `cli`, `desktop` — or null.
  final String? source;

  /// The agent profile it belongs to, when the server says.
  final String? profile;
}

/// One entry in a transcript.
@immutable
sealed class TranscriptItem {
  const TranscriptItem(this.id);

  /// Stable within one transcript, for keys and in-place updates.
  final String id;
}

/// Something the person said.
final class UserTurn extends TranscriptItem {
  const UserTurn({required String id, required this.text}) : super(id);

  final String text;
}

/// Something the agent said, possibly still arriving.
final class AssistantTurn extends TranscriptItem {
  const AssistantTurn({
    required String id,
    required this.text,
    this.reasoning = '',
    this.streaming = false,
  }) : super(id);

  final String text;

  /// The model's visible thinking, when it shares it.
  final String reasoning;

  /// Still arriving.
  final bool streaming;

  /// Says nothing at all — neither text nor thinking.
  bool get isEmpty => text.trim().isEmpty && reasoning.trim().isEmpty;

  AssistantTurn copyWith({String? text, String? reasoning, bool? streaming}) =>
      AssistantTurn(
        id: id,
        text: text ?? this.text,
        reasoning: reasoning ?? this.reasoning,
        streaming: streaming ?? this.streaming,
      );
}

enum ToolStatus { running, done, failed }

/// A tool the agent ran.
final class ToolCall extends TranscriptItem {
  const ToolCall({
    required String id,
    required this.name,
    this.arguments,
    this.output,
    this.status = ToolStatus.done,
  }) : super(id);

  final String name;

  /// What the agent passed, usually JSON text.
  final String? arguments;
  final String? output;
  final ToolStatus status;

  ToolCall copyWith({String? output, ToolStatus? status}) => ToolCall(
    id: id,
    name: name,
    arguments: arguments,
    output: output ?? this.output,
    status: status ?? this.status,
  );
}

/// A line that is not a turn: an error, a stop.
final class Notice extends TranscriptItem {
  const Notice({required String id, required this.text, this.isError = false})
    : super(id);

  final String text;
  final bool isError;
}

/// The agent wants permission to run something.
@immutable
final class ApprovalRequest {
  const ApprovalRequest({
    required this.sessionId,
    required this.command,
    required this.description,
    required this.choices,
    this.queueId,
    this.serverRequestId,
  });

  /// The live session it belongs to.
  final String sessionId;
  final String command;
  final String description;

  /// What the gateway accepts as an answer: `once`, `session`, `always`,
  /// `deny`.
  final List<String> choices;

  /// The approval queue's own id, which `approval.respond` addresses.
  final String? queueId;

  /// The `srq-…` id when it arrived as a server request. The gateway withdraws
  /// that request itself once the queue entry is answered.
  final String? serverRequestId;

  /// Whether a withdrawal naming [id] refers to this request.
  bool matches(String id) => id == serverRequestId || id == queueId;

  /// What a button for [choice] says.
  static String labelFor(String choice) => switch (choice) {
    'once' => 'Allow once',
    'session' => 'Allow for this chat',
    'always' => 'Always allow',
    'deny' => 'Deny',
    _ => choice,
  };
}

/// One offered answer to a clarifying question.
@immutable
final class ClarifyChoice {
  const ClarifyChoice({required this.label, required this.value});

  final String label;
  final String value;
}

/// One clarifying question.
@immutable
final class ClarifyQuestion {
  const ClarifyQuestion({
    required this.id,
    required this.text,
    this.choices = const [],
    this.synthetic = false,
  });

  final String id;
  final String text;
  final List<ClarifyChoice> choices;

  /// Iris made [id] up for a single-question request. It must never be sent
  /// as a `question_id`: that would address a question that does not exist.
  final bool synthetic;
}

/// The agent asks the person something before it continues.
@immutable
final class ClarifyRequest {
  const ClarifyRequest({
    required this.requestId,
    required this.sessionId,
    required this.questions,
  });

  /// `srq-…` for a server request; otherwise a legacy `clarify.request` id.
  final String requestId;
  final String sessionId;

  /// Still unanswered, in the order asked.
  final List<ClarifyQuestion> questions;

  bool get isServerRequest => requestId.startsWith('srq-');

  /// This request with question [questionId] answered.
  ClarifyRequest without(String questionId) => ClarifyRequest(
    requestId: requestId,
    sessionId: sessionId,
    questions: [
      for (final question in questions)
        if (question.id != questionId) question,
    ],
  );
}

/// One page of the conversation list.
@immutable
final class ConversationPage {
  const ConversationPage({required this.items, required this.total});

  final List<ConversationSummary> items;

  /// How many conversations the profile has in all, for "Show more".
  final int total;
}

/// An agent profile on the dashboard: its own conversations, memory and
/// model.
@immutable
final class AgentProfile {
  const AgentProfile({
    required this.name,
    this.isDefault = false,
    this.model,
    this.provider,
    this.running = false,
  });

  final String name;
  final bool isDefault;
  final String? model;
  final String? provider;

  /// Its messaging gateway (Telegram and the like) is running.
  final bool running;
}

/// One provider in the model picker.
@immutable
final class ModelProvider {
  const ModelProvider({
    required this.slug,
    required this.name,
    required this.models,
    this.isCurrent = false,
    this.authenticated = true,
  });

  /// What `config.set` names it by.
  final String slug;
  final String name;
  final List<String> models;
  final bool isCurrent;

  /// Signed in, so its models can actually run.
  final bool authenticated;
}

/// What the model picker offers.
@immutable
final class ModelOptions {
  const ModelOptions({this.model, this.provider, this.providers = const []});

  final String? model;
  final String? provider;
  final List<ModelProvider> providers;

  /// Providers worth offering: signed in, or the one in use, with at least
  /// one model. Hermes 0.18.2 reports the configured provider in use as
  /// unauthenticated, yet it is the one running the conversation.
  List<ModelProvider> get usable => [
    for (final provider in providers)
      if ((provider.authenticated || provider.isCurrent) &&
          provider.models.isNotEmpty)
        provider,
  ];
}

/// The gateway's answer to a model switch.
@immutable
final class ModelSwitch {
  const ModelSwitch({
    required this.model,
    this.confirmRequired = false,
    this.confirmMessage = '',
    this.deferred = false,
  });

  final String model;

  /// Nothing changed yet: the person must confirm [confirmMessage] first.
  final bool confirmRequired;
  final String confirmMessage;

  /// The conversation is mid-turn; the switch applies when the turn ends.
  final bool deferred;
}

/// A slash command and what it does.
@immutable
final class SlashCommand {
  const SlashCommand({required this.name, required this.description});

  /// With its leading slash, such as `/model`.
  final String name;
  final String description;
}

enum SlashKind {
  /// Ran on the server; show its output.
  exec,

  /// Expands to a prompt to send.
  send,

  /// Puts text in the composer for the person to finish.
  prefill,

  /// Stands for another command.
  alias,
}

/// What running a slash command asks Iris to do next.
@immutable
final class SlashOutcome {
  const SlashOutcome({
    required this.kind,
    this.text = '',
    this.notice = '',
    this.target = '',
  });

  final SlashKind kind;

  /// The output to show, the prompt to send, or the text to prefill.
  final String text;

  /// A note to show alongside a prefill.
  final String notice;

  /// The command an alias stands for.
  final String target;
}
