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
  const UserTurn({
    required String id,
    required this.text,
    this.steered = false,
    this.attachments = const [],
    this.steerPending = false,
    this.steerStep,
    this.fromQueue = false,
  }) : super(id);

  final String text;

  /// Sent mid-turn to steer the agent, rather than as a prompt of its own.
  final bool steered;

  /// The names of the files sent with it.
  final List<String> attachments;

  /// A steer Hermes has not yet picked up: it waits for the next step.
  final bool steerPending;

  /// For a steer, the step (the nth tool of the turn) that picked it up.
  final int? steerStep;

  /// Sent from the queue tray when the previous turn finished.
  final bool fromQueue;
}

/// Something the agent said, possibly still arriving.
final class AssistantTurn extends TranscriptItem {
  const AssistantTurn({
    required String id,
    required this.text,
    this.reasoning = '',
    this.streaming = false,
    this.redirected = false,
  }) : super(id);

  final String text;

  /// The model's visible thinking, when it shares it.
  final String reasoning;

  /// Still arriving.
  final bool streaming;

  /// Cut off because the person redirected the turn.
  final bool redirected;

  /// Says nothing at all — neither text nor thinking.
  bool get isEmpty => text.trim().isEmpty && reasoning.trim().isEmpty;

  AssistantTurn copyWith({
    String? text,
    String? reasoning,
    bool? streaming,
    bool? redirected,
  }) => AssistantTurn(
    id: id,
    text: text ?? this.text,
    reasoning: reasoning ?? this.reasoning,
    streaming: streaming ?? this.streaming,
    redirected: redirected ?? this.redirected,
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
  const Notice({
    required String id,
    required this.text,
    this.isError = false,
    this.retryable = false,
  }) : super(id);

  final String text;
  final bool isError;

  /// The turn this notice reports failed, and asking Hermes to retry it makes
  /// sense. Only the newest failure carries it.
  final bool retryable;

  Notice copyWith({bool? retryable}) => Notice(
    id: id,
    text: text,
    isError: isError,
    retryable: retryable ?? this.retryable,
  );
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
    this.usage,
    this.capabilities = const {},
  });

  /// What `config.set` names it by.
  final String slug;
  final String name;
  final List<String> models;
  final bool isCurrent;

  /// Signed in, so its models can actually run.
  final bool authenticated;

  /// How much of its subscription is spent, when the gateway knows.
  final ProviderUsage? usage;

  /// What each model can do, by model id. Empty when the gateway does not say.
  final Map<String, ModelCaps> capabilities;
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
  /// What [model] can do on [provider], or null when the gateway did not say.
  ModelCaps? capsFor(String model, {String? provider}) {
    for (final candidate in providers) {
      if (provider != null && candidate.slug != provider) continue;
      final caps = candidate.capabilities[model];
      if (caps != null) return caps;
    }
    return null;
  }

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

/// What kind of value an input prompt wants.
enum InputKind { sudo, secret, vaultUnlock, vaultCode }

/// The agent needs a value typed in that must never be shown or kept: a sudo
/// password, an API key. Answered once, then forgotten.
@immutable
final class InputRequest {
  const InputRequest({
    required this.requestId,
    required this.sessionId,
    required this.kind,
    this.command = '',
    this.envVar = '',
    this.prompt = '',
    this.displayName = '',
    this.site = '',
    this.hint = '',
  });

  /// The `srq-…` server request the answer is addressed to.
  final String requestId;
  final String sessionId;
  final InputKind kind;

  /// sudo: the command that needs the password, as Hermes redacted it.
  final String command;

  /// secret: the environment variable the value is stored under.
  final String envVar;

  /// secret: what Hermes says it needs.
  final String prompt;

  /// vaultUnlock: the password manager's name.
  final String displayName;

  /// vaultCode: the site the code is for, and Hermes's hint about it.
  final String site;
  final String hint;

  /// The card's headline.
  String get title => switch (kind) {
    InputKind.sudo => 'Hermes needs your sudo password',
    InputKind.secret when prompt.isNotEmpty => prompt,
    InputKind.secret when envVar.isNotEmpty =>
      'Hermes needs a value for $envVar',
    InputKind.secret => 'Hermes needs a secret value',
    InputKind.vaultUnlock =>
      '${displayName.isEmpty ? 'Your password manager' : displayName} is locked',
    InputKind.vaultCode =>
      site.isEmpty ? 'Hermes needs a one-time code' : 'Code for $site',
  };
}

/// How full the conversation's context window is.
@immutable
final class ContextUsage {
  const ContextUsage({required this.percent, this.used, this.max});

  /// 0 to 100.
  final double percent;

  /// Tokens in the window and its size, when the gateway says.
  final int? used;
  final int? max;
}

/// One subscription window: a five-hour session, a week.
@immutable
final class UsageWindow {
  const UsageWindow({
    required this.label,
    required this.usedPercent,
    this.resetsAt,
    this.accountScoped = true,
  });

  final String label;

  /// 0 to 100.
  final double usedPercent;
  final DateTime? resetsAt;

  /// False for a window that caps one model family only, which never means
  /// the whole account is out.
  final bool accountScoped;

  double get leftPercent => (100 - usedPercent).clamp(0, 100).toDouble();
}

enum UsageAccountState { ready, limited, unavailable, unknown }

/// One login of a provider that has several.
@immutable
final class UsageAccount {
  const UsageAccount({
    required this.label,
    required this.state,
    this.windows = const [],
    this.resetsAt,
  });

  final String label;
  final UsageAccountState state;
  final List<UsageWindow> windows;
  final DateTime? resetsAt;
}

/// How much of a provider's subscription is spent.
@immutable
final class ProviderUsage {
  const ProviderUsage({this.windows = const [], this.accounts = const []});

  /// For a single-account provider.
  final List<UsageWindow> windows;

  /// For a provider with a pool of accounts, one each.
  final List<UsageAccount> accounts;

  /// The window closest to its limit, which is what a collapsed row shows. For
  /// a pool, the best account's tightest window: the pool keeps working while
  /// any account does.
  UsageWindow? get tightest {
    UsageWindow? worst(List<UsageWindow> windows) => windows.isEmpty
        ? null
        : windows.reduce((a, b) => b.usedPercent > a.usedPercent ? b : a);
    if (windows.isNotEmpty) return worst(windows);
    UsageWindow? best;
    for (final account in accounts) {
      final candidate = worst(account.windows);
      if (candidate != null &&
          (best == null || candidate.usedPercent < best.usedPercent)) {
        best = candidate;
      }
    }
    return best;
  }
}

/// A piece of a search snippet, matched or not.
@immutable
final class SnippetRun {
  const SnippetRun(this.text, {this.matched = false});

  final String text;
  final bool matched;
}

/// A conversation a search found.
@immutable
final class SearchHit {
  const SearchHit({
    required this.storedId,
    required this.title,
    this.snippet = const [],
    this.lastActive,
    this.archived = false,
    this.messageCount = 0,
  });

  final String storedId;
  final String title;

  /// The best matching message, with the matched words marked.
  final List<SnippetRun> snippet;
  final DateTime? lastActive;
  final bool archived;
  final int messageCount;
}

/// What became of a steer.
enum SteerOutcome { accepted, rejected }

/// The agent wants to save a login: a username and password for a site.
/// Answered once and forgotten, like [InputRequest].
@immutable
final class LoginRequest {
  const LoginRequest({
    required this.requestId,
    required this.sessionId,
    required this.origin,
    this.site = '',
  });

  final String requestId;
  final String sessionId;

  /// `https://github.com`.
  final String origin;

  /// Hermes's name for the site, when it has one.
  final String site;

  /// What to call the site: Hermes's name, else the origin's host.
  String get siteName =>
      site.isNotEmpty ? site : (Uri.tryParse(origin)?.host ?? origin);
}

/// What Hermes does with a message sent while a reply is running
/// (`display.busy_input_mode`, profile-wide).
enum BusyMode {
  queue('queue', 'Queue', 'Your message runs after the current reply.'),
  steer('steer', 'Steer', 'It joins the running reply at the next step.'),
  interrupt(
    'interrupt',
    'Interrupt',
    'The reply stops and Hermes answers this instead.',
  );

  const BusyMode(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  /// Hermes's own default is interrupt, so that is what an unknown or
  /// missing value means.
  static BusyMode fromWire(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'queue' => queue,
        'steer' => steer,
        _ => interrupt,
      };
}

/// How hard the model thinks. Hermes also knows `minimal`, `xhigh` and
/// `ultra`; they fold onto the nearest of these five for display.
enum ReasoningEffort {
  none,
  low,
  medium,
  high,
  max;

  String get wire => name;

  String get label => '${name[0].toUpperCase()}${name.substring(1)}';

  static ReasoningEffort? fromWire(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'none' || 'false' || 'disabled' => none,
        'minimal' || 'low' => low,
        'medium' => medium,
        'high' => high,
        'xhigh' || 'max' || 'ultra' => max,
        _ => null,
      };
}

/// What `prompt.submit` did with a message.
enum SubmitOutcome {
  /// A new turn began.
  started,

  /// The session was busy and Hermes held the message for after the turn.
  queued,

  /// The session was busy and Hermes slipped it into the running turn.
  steered,

  /// The session was busy and Hermes stopped the turn to answer this.
  redirected;

  static SubmitOutcome fromStatus(String? status) =>
      switch (status?.trim().toLowerCase()) {
        'queued' => queued,
        'steered' => steered,
        'redirected' => redirected,
        _ => started,
      };
}

/// One message of the prefix a branch is seeded with.
@immutable
final class SeedMessage {
  const SeedMessage(this.role, this.content);

  /// `user` or `assistant`.
  final String role;
  final String content;

  Map<String, Object?> toWire() => {'role': role, 'content': content};
}

/// A row of `session.active_list`: a live runtime session on the gateway.
@immutable
final class LiveStatus {
  const LiveStatus({
    required this.runtimeId,
    required this.storedId,
    required this.status,
  });

  final String runtimeId;
  final String storedId;

  /// `working`, `waiting`, `starting` or `idle`.
  final String status;

  /// A turn is running or a decision is pending. `starting` only means an
  /// agent is being built, which can happen without any prompt.
  bool get replying => status == 'working' || status == 'waiting';
  bool get waiting => status == 'waiting';
}

/// What a model can do beyond answering.
@immutable
final class ModelCaps {
  const ModelCaps({this.reasoning = false, this.fast = false});

  final bool reasoning;
  final bool fast;
}
