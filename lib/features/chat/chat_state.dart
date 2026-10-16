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
import '../../data/chat/connection_models.dart';

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
    this.inputs = const [],
    this.title,
    this.failure,
    this.earlier,
    this.loadingEarlier = false,
    this.model,
    this.provider,
    this.commands = const [],
    this.context,
    this.retrying = false,
    this.attempt = 1,
    this.logins = const [],
    this.connections = const [],
    this.effort,
    this.fast,
    this.collapsing = const {},
    this.queue = const [],
    this.queuePaused = false,
    this.busyMode = BusyMode.interrupt,
  });

  final ChatPhase phase;
  final List<TranscriptItem> items;
  final TurnPhase turn;
  final List<ApprovalRequest> approvals;
  final List<ClarifyRequest> questions;

  /// Password and secret prompts waiting for the person.
  final List<InputRequest> inputs;
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

  /// How full the context window is, once the gateway says.
  final ContextUsage? context;

  /// A retry is on its way; the failed card shows it working.
  final bool retrying;

  /// Which try the turn is on: 1, then up by one for each retry. A new
  /// message from the person starts again at 1.
  final int attempt;

  /// Login prompts waiting for the person.
  final List<LoginRequest> logins;

  /// Connection cards waiting for the person.
  final List<ConnectionRequest> connections;

  /// The reasoning effort and fast mode in force, once Hermes says.
  final ReasoningEffort? effort;
  final bool? fast;

  /// The ids of an undone exchange, folding away before it leaves.
  final Set<String> collapsing;

  /// Messages waiting for the running reply to finish, oldest first.
  final List<QueuedMessage> queue;

  /// A failed or stopped turn paused the tray until the person says.
  final bool queuePaused;

  /// What sending does while a reply runs.
  final BusyMode busyMode;

  bool get running => turn != TurnPhase.idle;

  ChatState copyWith({
    ChatPhase? phase,
    List<TranscriptItem>? items,
    TurnPhase? turn,
    List<ApprovalRequest>? approvals,
    List<ClarifyRequest>? questions,
    List<InputRequest>? inputs,
    String? title,
    IrisFailure? failure,
    HistoryCursor? earlier,
    bool? loadingEarlier,
    String? model,
    String? provider,
    List<SlashCommand>? commands,
    ContextUsage? context,
    bool? retrying,
    int? attempt,
    List<LoginRequest>? logins,
    List<ConnectionRequest>? connections,
    ReasoningEffort? effort,
    bool? fast,
    Set<String>? collapsing,
    List<QueuedMessage>? queue,
    bool? queuePaused,
    BusyMode? busyMode,
  }) => ChatState(
    phase: phase ?? this.phase,
    items: items ?? this.items,
    turn: turn ?? this.turn,
    approvals: approvals ?? this.approvals,
    questions: questions ?? this.questions,
    inputs: inputs ?? this.inputs,
    title: title ?? this.title,
    failure: failure ?? this.failure,
    earlier: earlier ?? this.earlier,
    loadingEarlier: loadingEarlier ?? this.loadingEarlier,
    model: model ?? this.model,
    provider: provider ?? this.provider,
    commands: commands ?? this.commands,
    context: context ?? this.context,
    retrying: retrying ?? this.retrying,
    attempt: attempt ?? this.attempt,
    logins: logins ?? this.logins,
    connections: connections ?? this.connections,
    effort: effort ?? this.effort,
    fast: fast ?? this.fast,
    collapsing: collapsing ?? this.collapsing,
    queue: queue ?? this.queue,
    queuePaused: queuePaused ?? this.queuePaused,
    busyMode: busyMode ?? this.busyMode,
  );

  /// The state after [event].
  ChatState apply(ChatEvent event) => switch (event) {
    MessageStarted() => copyWith(
      items: _withLive(retrying ? _withoutRetry(items) : items),
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
      items: _pickedUp([
        ..._settled(items),
        ToolCall(
          id: toolId ?? 'tool-${items.length}',
          name: name,
          arguments: input,
          status: ToolStatus.running,
        ),
      ]),
      turn: TurnPhase.working,
    ),
    final ToolCompleted done => copyWith(
      items: _toolDone(items, done),
      turn: _waitingOr(TurnPhase.thinking),
    ),
    TurnFailed(:final message) => withFailure(message),
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
    InputAsked(:final request) => withInput(request),
    ContextChanged(:final usage) => copyWith(context: usage),
    LoginAsked(:final request) => withLogin(request),
    ConnectionAsked(:final request) => withConnection(request),
    final ConnectionChanged changed => withConnectionChange(changed),
    SessionInfoChanged(:final effort, :final fast) => copyWith(
      effort: effort,
      fast: fast,
    ),
    RequestWithdrawn(:final requestId) => _withdrawn(requestId),
  };

  /// The newest page of stored history, replacing whatever was shown.
  ChatState withNewestPage(List<TranscriptItem> page, HistoryCursor? earlier) =>
      ChatState(
        phase: ChatPhase.ready,
        items: page,
        turn: turn,
        approvals: approvals,
        questions: questions,
        inputs: inputs,
        title: title,
        earlier: earlier,
        model: model,
        provider: provider,
        commands: commands,
        context: context,
        attempt: attempt,
        logins: logins,
        connections: connections,
        effort: effort,
        fast: fast,
        queue: queue,
        queuePaused: queuePaused,
        busyMode: busyMode,
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
    inputs: inputs,
    title: title,
    failure: failure,
    earlier: earlier,
    model: model,
    provider: provider,
    commands: commands,
    context: context,
    attempt: attempt,
    logins: logins,
    connections: connections,
    effort: effort,
    fast: fast,
    collapsing: collapsing,
    queue: queue,
    queuePaused: queuePaused,
    busyMode: busyMode,
  );

  /// The id of the last turn the person started: where "the last exchange"
  /// begins. Steered turns are corrections inside a turn, not starts. Null
  /// when none is loaded.
  String? get lastExchangeStartId {
    for (final item in items.reversed) {
      if (item is UserTurn && !item.steered) return item.id;
    }
    return null;
  }

  /// The ids of the last exchange: its user turn and everything after.
  Set<String> get lastExchangeIds {
    final start = lastExchangeStartId;
    if (start == null) return const {};
    final at = items.indexWhere((i) => i.id == start);
    return {for (final item in items.sublist(at)) item.id};
  }

  ChatState withCollapsing(Set<String> ids) => copyWith(collapsing: ids);

  /// The transcript without its last exchange.
  ChatState withoutLastExchange() {
    final start = lastExchangeStartId;
    if (start == null) return this;
    final at = items.indexWhere((i) => i.id == start);
    return copyWith(items: items.sublist(0, at), collapsing: const {});
  }

  /// The person's message, shown at once.
  ChatState withUserTurn(
    String text, {
    List<String> attachments = const [],
    bool fromQueue = false,
  }) => copyWith(
    items: [
      ..._settled(items),
      UserTurn(
        id: 'local-${items.length}',
        text: text,
        attachments: attachments,
        fromQueue: fromQueue,
      ),
    ],
    turn: TurnPhase.thinking,
    attempt: 1,
  );

  /// The person steered the running turn. The reply so far is finished, so
  /// what the agent says next starts below the steer, and the turn carries on.
  ChatState withSteer(String text) => copyWith(
    items: [
      ..._settled(items),
      UserTurn(
        id: 'local-${items.length}',
        text: text,
        steered: true,
        steerPending: true,
      ),
    ],
  );

  /// The person redirected the running turn: Hermes stopped it to answer
  /// this. What was said so far stays, marked as cut off.
  ChatState withRedirect(String text) {
    final settled = _settled(items);
    final last = settled.isEmpty ? null : settled.last;
    final marked = last is AssistantTurn
        ? [
            ...settled.sublist(0, settled.length - 1),
            last.copyWith(redirected: true),
          ]
        : settled;
    return copyWith(
      items: [
        ...marked,
        UserTurn(id: 'local-${items.length}', text: text),
      ],
      turn: TurnPhase.thinking,
    );
  }

  ChatState withQueued(String id, String text) => copyWith(
    queue: [
      ...queue,
      QueuedMessage(id: id, text: text),
    ],
  );

  ChatState withoutQueued(String id) => copyWith(
    queue: [
      for (final q in queue)
        if (q.id != id) q,
    ],
    queuePaused: queue.length <= 1 ? false : queuePaused,
  );

  /// The turn failed. Only the newest failure can be retried: retrying an
  /// older one would ask Hermes to repeat something it has moved past.
  ChatState withFailure(String message) => copyWith(
    items: [
      ..._withoutRetry(_settled(items)),
      Notice(
        id: 'notice-${items.length}',
        text: message,
        isError: true,
        retryable: true,
      ),
    ],
    turn: _waitingOr(TurnPhase.idle),
    retrying: false,
  );

  static List<TranscriptItem> _withoutRetry(List<TranscriptItem> items) => [
    for (final item in items)
      if (item is Notice && item.retryable)
        item.copyWith(retryable: false)
      else
        item,
  ];

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

  ChatState _withdrawn(String requestId) {
    final next = _decided(
      copyWith(
        approvals: [
          for (final approval in approvals)
            if (!approval.matches(requestId)) approval,
        ],
        questions: [
          for (final question in questions)
            if (question.requestId != requestId) question,
        ],
        inputs: [
          for (final input in inputs)
            if (input.requestId != requestId) input,
        ],
        logins: [
          for (final login in logins)
            if (login.requestId != requestId) login,
        ],
        connections: [
          for (final open in connections)
            if (open.opId != requestId) open,
        ],
      ),
    );
    // The card vanishing on its own would be a mystery; the controller, which
    // has the clock and the request, leaves an expired line saying why.
    return next;
  }

  /// A settled prompt: one line where the card was.
  ChatState withPromptRecord(PromptRecord record) =>
      copyWith(items: [..._settled(items), record]);

  ChatState withInput(InputRequest request) => copyWith(
    inputs: [
      for (final input in inputs)
        if (input.requestId != request.requestId) input,
      request,
    ],
    turn: TurnPhase.waiting,
  );

  ChatState withoutInput(InputRequest request) => _decided(
    copyWith(
      inputs: [
        for (final input in inputs)
          if (input.requestId != request.requestId) input,
      ],
    ),
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

  ChatState withLogin(LoginRequest request) => copyWith(
    logins: [
      for (final login in logins)
        if (login.requestId != request.requestId) login,
      request,
    ],
    turn: TurnPhase.waiting,
  );

  ChatState withoutLogin(LoginRequest request) => _decided(
    copyWith(
      logins: [
        for (final login in logins)
          if (login.requestId != request.requestId) login,
      ],
    ),
  );

  ChatState withConnection(ConnectionRequest request) => copyWith(
    connections: [
      for (final open in connections)
        if (open.opId != request.opId) open,
      request,
    ],
    turn: TurnPhase.waiting,
  );

  ChatState withoutConnection(String opId) => _decided(
    copyWith(
      connections: [
        for (final open in connections)
          if (open.opId != opId) open,
      ],
    ),
  );

  /// An update for an open card merges in; a settled one closes it. An update
  /// for a card that is not open is ignored.
  ChatState withConnectionChange(ConnectionChanged change) {
    final open = connections.where((c) => c.opId == change.opId);
    if (open.isEmpty) return this;
    if (change.settled) return withoutConnection(change.opId);
    final updated = open.first.withTargets(change.targets, settled: false);
    return copyWith(
      connections: [
        for (final c in connections)
          if (c.opId == change.opId) updated else c,
      ],
    );
  }

  TurnPhase _waitingOr(TurnPhase phase) =>
      approvals.isNotEmpty ||
          questions.isNotEmpty ||
          inputs.isNotEmpty ||
          logins.isNotEmpty ||
          connections.isNotEmpty
      ? TurnPhase.waiting
      : phase;

  /// After a decision: back to thinking once nothing is waiting.
  static ChatState _decided(ChatState next) =>
      next.turn == TurnPhase.waiting &&
          next.approvals.isEmpty &&
          next.questions.isEmpty &&
          next.inputs.isEmpty &&
          next.logins.isEmpty &&
          next.connections.isEmpty
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
  /// Steers waiting for a step are picked up by the tool that just started:
  /// its position among this turn's tools is the step.
  static List<TranscriptItem> _pickedUp(List<TranscriptItem> items) {
    var tools = 0;
    for (final item in items.reversed) {
      if (item is UserTurn && !item.steered) break;
      if (item is ToolCall) tools++;
    }
    return [
      for (final item in items)
        if (item is UserTurn && item.steerPending)
          item.copyWith(steerPending: false, steerStep: tools)
        else
          item,
    ];
  }

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
