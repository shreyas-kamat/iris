/// One open conversation's state, and how events change it.
///
/// Pure: `apply` takes an event and returns the next state, so every streaming
/// edge case is a plain unit test rather than a widget test.
library;

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_event.dart';
import '../../data/chat/chat_models.dart';

enum ChatPhase {
  /// Reading the stored transcript.
  loading,

  /// Showing it; sending works.
  ready,

  /// The transcript could not be read.
  failed,
}

/// What the agent is doing in this conversation right now.
enum TurnPhase { idle, thinking, streaming, working, waiting }

@immutable
final class ChatState {
  const ChatState({
    this.phase = ChatPhase.loading,
    this.items = const [],
    this.turn = TurnPhase.idle,
    this.approvals = const [],
    this.questions = const [],
    this.title,
    this.failure,
    this.earlier,
    this.loadingEarlier = false,
    this.model,
    this.provider,
    this.commands = const [],
  });

  final ChatPhase phase;
  final List<TranscriptItem> items;
  final TurnPhase turn;
  final List<ApprovalRequest> approvals;
  final List<ClarifyRequest> questions;
  final String? title;

  /// Why the transcript could not be read, when [phase] is failed.
  final IrisFailure? failure;

  /// Where the page before the oldest shown message starts; null when the
  /// whole conversation is shown.
  final HistoryCursor? earlier;
  final bool loadingEarlier;

  /// The model the conversation runs on, when known.
  final String? model;
  final String? provider;

  /// The gateway's slash commands, once read.
  final List<SlashCommand> commands;

  bool get running => turn != TurnPhase.idle;

  ChatState copyWith({
    ChatPhase? phase,
    List<TranscriptItem>? items,
    TurnPhase? turn,
    List<ApprovalRequest>? approvals,
    List<ClarifyRequest>? questions,
    String? title,
    IrisFailure? failure,
    HistoryCursor? earlier,
    bool? loadingEarlier,
    String? model,
    String? provider,
    List<SlashCommand>? commands,
  }) => ChatState(
    phase: phase ?? this.phase,
    items: items ?? this.items,
    turn: turn ?? this.turn,
    approvals: approvals ?? this.approvals,
    questions: questions ?? this.questions,
    title: title ?? this.title,
    failure: failure ?? this.failure,
    earlier: earlier ?? this.earlier,
    loadingEarlier: loadingEarlier ?? this.loadingEarlier,
    model: model ?? this.model,
    provider: provider ?? this.provider,
    commands: commands ?? this.commands,
  );

  /// The state after [event].
  ChatState apply(ChatEvent event) => switch (event) {
    MessageStarted() => copyWith(
      items: _withLive(items),
      turn: TurnPhase.thinking,
    ),
    TextDelta(:final text) => copyWith(
      items: _appendLive(items, text: text),
      turn: TurnPhase.streaming,
    ),
    ReasoningDelta(:final text) => copyWith(
      items: _appendLive(items, reasoning: text),
      turn: turn == TurnPhase.streaming ? turn : TurnPhase.thinking,
    ),
    MessageCompleted(:final content, :final reasoning) => copyWith(
      items: _completed(items, content, reasoning),
      turn: _waitingOr(TurnPhase.idle),
    ),
    ToolStarted(:final toolId, :final name, :final input) => copyWith(
      items: [
        ..._settled(items),
        ToolCall(
          id: toolId ?? 'tool-${items.length}',
          name: name,
          arguments: input,
          status: ToolStatus.running,
        ),
      ],
      turn: TurnPhase.working,
    ),
    final ToolCompleted done => copyWith(
      items: _toolDone(items, done),
      turn: _waitingOr(TurnPhase.thinking),
    ),
    TurnFailed(:final message) => withError(message),
    TurnInterrupted() => copyWith(
      items: [
        ..._settled(items),
        Notice(id: 'notice-${items.length}', text: 'Stopped.'),
      ],
      turn: TurnPhase.idle,
    ),
    BusyChanged(:final busy) =>
      busy
          ? copyWith(turn: turn == TurnPhase.idle ? TurnPhase.thinking : turn)
          : copyWith(items: _settled(items), turn: _waitingOr(TurnPhase.idle)),
    TitleChanged(:final title) => copyWith(title: title),
    ModelChanged(:final model, :final provider) => copyWith(
      model: model,
      provider: provider,
    ),
    ApprovalAsked(:final request) => withApproval(request),
    ClarifyAsked(:final request) => withQuestion(request),
    RequestWithdrawn(:final requestId) => _decided(
      copyWith(
        approvals: [
          for (final approval in approvals)
            if (!approval.matches(requestId)) approval,
        ],
        questions: [
          for (final question in questions)
            if (question.requestId != requestId) question,
        ],
      ),
    ),
  };

  /// The newest page of stored history, replacing whatever was shown.
  ChatState withNewestPage(
    List<TranscriptItem> page,
    HistoryCursor? earlier,
  ) => ChatState(
    phase: ChatPhase.ready,
    items: page,
    turn: turn,
    approvals: approvals,
    questions: questions,
    title: title,
    earlier: earlier,
    model: model,
    provider: provider,
    commands: commands,
  );

  /// An earlier page, above what is shown.
  ChatState withEarlierPage(
    List<TranscriptItem> page,
    HistoryCursor? earlier,
  ) => ChatState(
    phase: phase,
    items: [...page, ...items],
    turn: turn,
    approvals: approvals,
    questions: questions,
    title: title,
    failure: failure,
    earlier: earlier,
    model: model,
    provider: provider,
    commands: commands,
  );

  /// The person's message, shown at once.
  ChatState withUserTurn(String text) => copyWith(
    items: [
      ..._settled(items),
      UserTurn(id: 'local-${items.length}', text: text),
    ],
    turn: TurnPhase.thinking,
  );

  /// A failure, shown inline; the turn ends unless a decision is waiting.
  ChatState withError(String message) => copyWith(
    items: [
      ..._settled(items),
      Notice(id: 'notice-${items.length}', text: message, isError: true),
    ],
    turn: _waitingOr(TurnPhase.idle),
  );

  /// A line that is not a turn — a command's output, a model change. The
  /// turn carries on as it was; blank text adds nothing.
  ChatState withNotice(String text) => text.trim().isEmpty
      ? this
      : copyWith(
          items: [
            ..._settled(items),
            Notice(id: 'notice-${items.length}', text: text.trim()),
          ],
        );

  /// The turn is over as far as Iris knows, unless a decision is waiting.
  ChatState settled() =>
      copyWith(items: _settled(items), turn: _waitingOr(TurnPhase.idle));

  ChatState withApproval(ApprovalRequest request) => copyWith(
    approvals: [
      for (final approval in approvals)
        if (!_sameApproval(approval, request)) approval,
      request,
    ],
    turn: TurnPhase.waiting,
  );

  ChatState withoutApproval(ApprovalRequest request) => _decided(
    copyWith(
      approvals: [
        for (final approval in approvals)
          if (!_sameApproval(approval, request)) approval,
      ],
    ),
  );

  ChatState withQuestion(ClarifyRequest request) => copyWith(
    questions: [
      for (final question in questions)
        if (question.requestId != request.requestId) question,
      request,
    ],
    turn: TurnPhase.waiting,
  );

  /// [question] of [request] answered; the request goes once none remain.
  ChatState withoutQuestion(ClarifyRequest request, ClarifyQuestion question) {
    final remaining = request.without(question.id);
    return _decided(
      copyWith(
        questions: [
          for (final pending in questions)
            if (pending.requestId != request.requestId)
              pending
            else if (remaining.questions.isNotEmpty)
              remaining,
        ],
      ),
    );
  }

  TurnPhase _waitingOr(TurnPhase phase) =>
      approvals.isNotEmpty || questions.isNotEmpty ? TurnPhase.waiting : phase;

  /// After a decision: back to thinking once nothing is waiting.
  static ChatState _decided(ChatState next) =>
      next.turn == TurnPhase.waiting &&
          next.approvals.isEmpty &&
          next.questions.isEmpty
      ? next.copyWith(turn: TurnPhase.thinking)
      : next;

  static bool _sameApproval(ApprovalRequest a, ApprovalRequest b) =>
      identical(a, b) ||
      (a.serverRequestId != null && a.serverRequestId == b.serverRequestId) ||
      (a.queueId != null && a.queueId == b.queueId);

  /// [items] with a live assistant turn at the end, creating one if needed.
  static List<TranscriptItem> _withLive(List<TranscriptItem> items) {
    final last = items.isEmpty ? null : items.last;
    if (last is AssistantTurn && last.streaming) return items;
    return [
      ...items,
      AssistantTurn(id: 'live-${items.length}', text: '', streaming: true),
    ];
  }

  static List<TranscriptItem> _appendLive(
    List<TranscriptItem> items, {
    String text = '',
    String reasoning = '',
  }) {
    final withLive = _withLive(items);
    final live = withLive.last;
    if (live is! AssistantTurn) return withLive;
    return [
      ...withLive.sublist(0, withLive.length - 1),
      live.copyWith(
        text: live.text + text,
        reasoning: live.reasoning + reasoning,
      ),
    ];
  }

  /// [items] with the live assistant turn finished: kept if it says
  /// anything, dropped if it never did.
  static List<TranscriptItem> _settled(List<TranscriptItem> items) {
    final last = items.isEmpty ? null : items.last;
    if (last is! AssistantTurn || !last.streaming) return items;
    final rest = items.sublist(0, items.length - 1);
    return last.isEmpty ? rest : [...rest, last.copyWith(streaming: false)];
  }

  static List<TranscriptItem> _completed(
    List<TranscriptItem> items,
    String? content,
    String? reasoning,
  ) {
    final last = items.isEmpty ? null : items.last;
    if (last is AssistantTurn && last.streaming) {
      final rest = items.sublist(0, items.length - 1);
      // The deltas win. The complete event's text fills in only when no text
      // arrived in this turn at all, because it may repeat what was said
      // before a tool call.
      final finished = last.copyWith(
        text: last.text.trim().isEmpty && _has(content) && !_turnHasText(rest)
            ? content
            : null,
        reasoning: last.reasoning.trim().isEmpty && _has(reasoning)
            ? reasoning
            : null,
        streaming: false,
      );
      return finished.isEmpty ? rest : [...rest, finished];
    }
    if (!_has(content) || _turnHasText(items)) return items;
    return [
      ...items,
      AssistantTurn(
        id: 'live-${items.length}',
        text: content!,
        reasoning: reasoning ?? '',
      ),
    ];
  }

  static bool _has(String? text) => text != null && text.trim().isNotEmpty;

  /// Whether the agent already said something since the person last spoke.
  static bool _turnHasText(List<TranscriptItem> items) {
    for (final item in items.reversed) {
      if (item is UserTurn) return false;
      if (item is AssistantTurn && item.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  static List<TranscriptItem> _toolDone(
    List<TranscriptItem> items,
    ToolCompleted done,
  ) {
    final status = done.failed ? ToolStatus.failed : ToolStatus.done;
    final toolId = done.toolId;
    var at = toolId == null
        ? null
        : _lastToolIndex(items, (call) => call.id == toolId);
    at ??= _lastToolIndex(
      items,
      (call) => call.status == ToolStatus.running && call.name == done.name,
    );
    if (at != null) {
      final call = items[at];
      if (call is ToolCall) {
        return [
          ...items.sublist(0, at),
          call.copyWith(output: done.output, status: status),
          ...items.sublist(at + 1),
        ];
      }
    }
    return [
      ..._settled(items),
      ToolCall(
        id: toolId ?? 'tool-${items.length}',
        name: done.name,
        output: done.output,
        status: status,
      ),
    ];
  }

  static int? _lastToolIndex(
    List<TranscriptItem> items,
    bool Function(ToolCall call) test,
  ) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is ToolCall && test(item)) return i;
    }
    return null;
  }
}
