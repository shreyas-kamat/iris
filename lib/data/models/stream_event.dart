/// The Hermes agent event stream, as typed values.
///
/// This is the most important contract in Iris. Everything the agent does while
/// working reaches the app as one of these, and the whole Generative UI Layer 1
/// is a function from [StreamEvent] to a widget. The wire names come from
/// hermes-webui's `session-sse-contract-v1` "authoritative emitted events"
/// table, which is explicit that clients should target the live wire names
/// rather than the aspirational semantic taxonomy in the same document.
///
/// Two rules hold throughout:
///
/// 1. **Unknown events survive.** A wire name Iris does not recognise becomes an
///    [UnknownEvent] carrying its raw payload, never an exception and never a
///    silent drop. Upstream ships new event types regularly; the transcript must
///    keep rendering when it does.
/// 2. **Every field is optional on the wire.** Payloads are read through [Json],
///    so a renamed or retyped field degrades to a fallback rather than failing
///    the whole frame.
library;

import '../../core/json.dart';
import '../sse/sse_frame.dart';

/// A single event emitted by an agent run.
sealed class StreamEvent {
  const StreamEvent({required this.wireName, required this.raw, this.eventId});

  /// The `event:` field exactly as it arrived, kept for diagnostics and for
  /// [UnknownEvent] display.
  final String wireName;

  /// The undecoded payload, so a debug surface can always show the truth and a
  /// future field can be read without changing this file.
  final Json raw;

  /// The SSE `id:`, opaque, echoed back as `Last-Event-ID` when resuming.
  final String? eventId;

  /// Whether this event ends the stream and the client should stop reading.
  ///
  /// Per the contract the relay-closing events are `stream_end`, `cancel`,
  /// `apperror`, and the legacy `error`. Note `done` is **not** terminal: the
  /// server may still send `title` and then `stream_end` after it.
  bool get isTerminal => false;

  /// Decodes a wire frame. Never throws; never returns `null`.
  factory StreamEvent.fromFrame(SseFrame frame) {
    final json = frame.json;
    final id = frame.id;
    final name = frame.event;

    return switch (name) {
      'token' => TokenEvent(
        text: json.any(['text', 'delta', 'content']).string(),
        raw: json,
        eventId: id,
      ),
      'reasoning' => ReasoningEvent(
        text: json.any(['text', 'delta', 'content', 'reasoning']).string(),
        raw: json,
        eventId: id,
      ),
      'interim_assistant' => InterimAssistantEvent(
        text: json.any(['text', 'content', 'message']).string(),
        raw: json,
        eventId: id,
      ),
      'tool' => ToolStartedEvent(
        callId: json.any(['id', 'call_id', 'tool_call_id']).stringOrNull,
        name: json.any(['name', 'tool', 'tool_name']).string('tool'),
        preview: json.any(['preview', 'summary', 'description']).stringOrNull,
        arguments: json.any(['args', 'arguments', 'input']),
        raw: json,
        eventId: id,
      ),
      'tool_complete' => ToolCompletedEvent(
        callId: json.any(['id', 'call_id', 'tool_call_id']).stringOrNull,
        name: json.any(['name', 'tool', 'tool_name']).string('tool'),
        output: json.any(['result', 'output', 'content', 'text']).stringOrNull,
        error: json.any(['error', 'err', 'exception']).stringOrNull,
        durationMs: json.any(['duration_ms', 'elapsed_ms', 'ms']).intOrNull,
        raw: json,
        eventId: id,
      ),
      'approval' => ApprovalEvent(
        command: json.any(['command', 'cmd']).string(),
        description: json.any(['description', 'reason', 'why']).stringOrNull,
        patternKeys: json
            .any(['pattern_keys', 'patterns'])
            .list
            .map((key) => key.string())
            .where((key) => key.isNotEmpty)
            .toList(growable: false),
        raw: json,
        eventId: id,
      ),
      'clarify' => ClarifyEvent(
        question: json.any(['question', 'prompt', 'message', 'text']).string(),
        fields: json.any(['fields', 'inputs', 'schema']),
        options: json
            .any(['options', 'choices'])
            .list
            .map((option) => option.any(['label', 'value', 'id']).string())
            .where((label) => label.isNotEmpty)
            .toList(growable: false),
        raw: json,
        eventId: id,
      ),
      'compressing' => CompressionEvent(
        finished: false,
        detail: json.any(['message', 'reason', 'status']).stringOrNull,
        raw: json,
        eventId: id,
      ),
      'compressed' => CompressionEvent(
        finished: true,
        detail: json.any(['message', 'reason', 'status']).stringOrNull,
        tokensBefore: json.any(['before', 'tokens_before']).intOrNull,
        tokensAfter: json.any(['after', 'tokens_after']).intOrNull,
        raw: json,
        eventId: id,
      ),
      'title' => TitleEvent(
        title: json.any(['title', 'text', 'value']).string(),
        raw: json,
        eventId: id,
      ),
      'title_status' => TitleStatusEvent(
        status: json.any(['status', 'state']).string(),
        reason: json.any(['reason', 'message', 'skip_reason']).stringOrNull,
        raw: json,
        eventId: id,
      ),
      'warning' => WarningEvent(
        message: json.any(['message', 'text', 'warning']).string(),
        raw: json,
        eventId: id,
      ),
      'apperror' || 'error' => AppErrorEvent(
        message: json.any(['message', 'error', 'text']).string('Agent error'),
        trace: json.any(['trace', 'traceback', 'stack']).stringOrNull,
        raw: json,
        eventId: id,
      ),
      'cancel' => CancelEvent(
        reason: json.any(['reason', 'message']).stringOrNull,
        raw: json,
        eventId: id,
      ),
      'done' => DoneEvent(session: json['session'], raw: json, eventId: id),
      'stream_end' => StreamEndEvent(raw: json, eventId: id),
      'metering' => MeteringEvent(
        inputTokens: json.any([
          'input_tokens',
          'prompt_tokens',
          'input',
        ]).intOrNull,
        outputTokens: json.any([
          'output_tokens',
          'completion_tokens',
          'output',
        ]).intOrNull,
        costUsd: json.any(['cost', 'cost_usd', 'total_cost']).doubleOrNull,
        model: json.any(['model', 'model_id']).stringOrNull,
        raw: json,
        eventId: id,
      ),
      'context_status' => ContextStatusEvent(
        usedTokens: json.any(['used', 'used_tokens', 'tokens']).intOrNull,
        windowTokens: json.any([
          'window',
          'max_tokens',
          'context_window',
          'limit',
        ]).intOrNull,
        percent: json.any(['percent', 'pct', 'usage']).doubleOrNull,
        raw: json,
        eventId: id,
      ),
      'goal' => GoalEvent(
        title: json.any(['title', 'goal', 'name', 'text']).stringOrNull,
        status: json.any(['status', 'state']).stringOrNull,
        steps: _decodeChecklist(json.any(['steps', 'plan', 'items'])),
        raw: json,
        eventId: id,
      ),
      'goal_continue' => GoalContinueEvent(
        reason: json.any(['reason', 'message']).stringOrNull,
        raw: json,
        eventId: id,
      ),
      'todo_state' => TodoStateEvent(
        items: _decodeChecklist(json.any(['todos', 'items', 'state', 'list'])),
        raw: json,
        eventId: id,
      ),
      'pending_steer_leftover' => PendingSteerEvent(
        text: json.any(['text', 'message', 'leftover']).string(),
        raw: json,
        eventId: id,
      ),
      'state_saved' => StateSavedEvent(raw: json, eventId: id),
      'session_snapshot' => SessionSnapshotEvent(
        session: json.any(['session', 'snapshot']),
        raw: json,
        eventId: id,
      ),
      _ => UnknownEvent(wireName: name, raw: json, eventId: id),
    };
  }

  /// Reads a checklist from any of the shapes upstream uses for plans and
  /// todos: a list of strings, or a list of objects with a label and a status.
  static List<ChecklistItem> _decodeChecklist(Json source) =>
      source.mapList((element) {
        if (element.isMap) {
          final label = element.any([
            'text',
            'label',
            'title',
            'content',
            'step',
          ]).stringOrNull;
          if (label == null || label.isEmpty) return null;
          return ChecklistItem(
            label: label,
            status: ChecklistStatus.parse(
              element.any(['status', 'state']).stringOrNull,
              done: element.any(['done', 'completed', 'checked']).boolOrNull,
            ),
          );
        }
        final label = element.stringOrNull;
        if (label == null || label.isEmpty) return null;
        return ChecklistItem(label: label, status: ChecklistStatus.pending);
      });
}

/// Where a plan or todo item stands. Drives the tick animation in the UI.
enum ChecklistStatus {
  pending,
  active,
  done,
  failed,
  skipped;

  /// Maps the several vocabularies upstream uses onto one enum.
  static ChecklistStatus parse(String? value, {bool? done}) {
    switch (value?.trim().toLowerCase()) {
      case 'done' || 'complete' || 'completed' || 'finished' || 'success':
        return ChecklistStatus.done;
      case 'active' || 'in_progress' || 'running' || 'current' || 'started':
        return ChecklistStatus.active;
      case 'failed' || 'error' || 'blocked':
        return ChecklistStatus.failed;
      case 'skipped' || 'cancelled' || 'canceled':
        return ChecklistStatus.skipped;
      case 'pending' || 'todo' || 'queued' || 'waiting':
        return ChecklistStatus.pending;
    }
    // Older payloads carry only a boolean.
    if (done != null) {
      return done ? ChecklistStatus.done : ChecklistStatus.pending;
    }
    return ChecklistStatus.pending;
  }
}

/// One line in a plan or todo panel.
final class ChecklistItem {
  const ChecklistItem({required this.label, required this.status});

  final String label;
  final ChecklistStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChecklistItem &&
          other.label == label &&
          other.status == status);

  @override
  int get hashCode => Object.hash(label, status);

  @override
  String toString() => 'ChecklistItem($label, ${status.name})';
}

// --- Text ------------------------------------------------------------------

/// An assistant text delta. The most frequent event by far.
final class TokenEvent extends StreamEvent {
  const TokenEvent({required this.text, required super.raw, super.eventId})
    : super(wireName: 'token');

  final String text;
}

/// A model reasoning / extended-thinking delta.
final class ReasoningEvent extends StreamEvent {
  const ReasoningEvent({required this.text, required super.raw, super.eventId})
    : super(wireName: 'reasoning');

  final String text;
}

/// Mid-turn assistant prose emitted before the final answer, typically between
/// tool calls. Rendered distinctly so it is not mistaken for the conclusion.
final class InterimAssistantEvent extends StreamEvent {
  const InterimAssistantEvent({
    required this.text,
    required super.raw,
    super.eventId,
  }) : super(wireName: 'interim_assistant');

  final String text;
}

// --- Tools -----------------------------------------------------------------

/// A tool call has started.
final class ToolStartedEvent extends StreamEvent {
  const ToolStartedEvent({
    required this.name,
    required this.arguments,
    required super.raw,
    this.callId,
    this.preview,
    super.eventId,
  }) : super(wireName: 'tool');

  /// Correlates with [ToolCompletedEvent.callId] when the server supplies one.
  /// When it does not, the transcript pairs by name against the newest open
  /// call, which is correct for the sequential execution Hermes performs.
  final String? callId;
  final String name;
  final String? preview;
  final Json arguments;
}

/// A tool call has finished, with either output or an error.
final class ToolCompletedEvent extends StreamEvent {
  const ToolCompletedEvent({
    required this.name,
    required super.raw,
    this.callId,
    this.output,
    this.error,
    this.durationMs,
    super.eventId,
  }) : super(wireName: 'tool_complete');

  final String? callId;
  final String name;
  final String? output;
  final String? error;
  final int? durationMs;

  bool get failed => error != null && error!.isNotEmpty;
}

// --- Interaction gates -----------------------------------------------------

/// The agent wants to run something dangerous and is blocked until answered.
final class ApprovalEvent extends StreamEvent {
  const ApprovalEvent({
    required this.command,
    required this.patternKeys,
    required super.raw,
    this.description,
    super.eventId,
  }) : super(wireName: 'approval');

  final String command;
  final String? description;

  /// The rule keys an "always allow" answer would whitelist. Shown verbatim so
  /// the user knows the exact scope of what they are permitting.
  final List<String> patternKeys;
}

/// A structured question the agent needs answered to continue.
final class ClarifyEvent extends StreamEvent {
  const ClarifyEvent({
    required this.question,
    required this.fields,
    required this.options,
    required super.raw,
    super.eventId,
  }) : super(wireName: 'clarify');

  final String question;

  /// A field schema when the server sent one, rendered as a native form.
  final Json fields;

  /// Simple choice labels, when the question is a pick-one.
  final List<String> options;
}

// --- Run lifecycle ---------------------------------------------------------

/// Context compression started or finished.
final class CompressionEvent extends StreamEvent {
  const CompressionEvent({
    required this.finished,
    required super.raw,
    this.detail,
    this.tokensBefore,
    this.tokensAfter,
    super.eventId,
  }) : super(wireName: finished ? 'compressed' : 'compressing');

  final bool finished;
  final String? detail;
  final int? tokensBefore;
  final int? tokensAfter;
}

/// The session title was generated or changed. Often arrives after `done`.
final class TitleEvent extends StreamEvent {
  const TitleEvent({required this.title, required super.raw, super.eventId})
    : super(wireName: 'title');

  final String title;
}

/// Progress or a skip reason for title generation.
final class TitleStatusEvent extends StreamEvent {
  const TitleStatusEvent({
    required this.status,
    required super.raw,
    this.reason,
    super.eventId,
  }) : super(wireName: 'title_status');

  final String status;
  final String? reason;
}

/// A non-fatal problem: a provider fell back, a feature was unavailable.
final class WarningEvent extends StreamEvent {
  const WarningEvent({required this.message, required super.raw, super.eventId})
    : super(wireName: 'warning');

  final String message;
}

/// A terminal application error. No `stream_end` follows it.
final class AppErrorEvent extends StreamEvent {
  const AppErrorEvent({
    required this.message,
    required super.raw,
    this.trace,
    super.eventId,
  }) : super(wireName: 'apperror');

  final String message;
  final String? trace;

  @override
  bool get isTerminal => true;
}

/// The run was cancelled.
final class CancelEvent extends StreamEvent {
  const CancelEvent({required super.raw, this.reason, super.eventId})
    : super(wireName: 'cancel');

  final String? reason;

  @override
  bool get isTerminal => true;
}

/// The turn finalised, carrying a full session snapshot.
///
/// Not terminal: `title` and `stream_end` may still follow. Treating this as
/// the end of the stream is the classic bug against this contract.
final class DoneEvent extends StreamEvent {
  const DoneEvent({required this.session, required super.raw, super.eventId})
    : super(wireName: 'done');

  /// The authoritative session state, used to reconcile the optimistic
  /// transcript built from deltas against what the server actually stored.
  final Json session;
}

/// The SSE fence. Close the connection when this arrives.
final class StreamEndEvent extends StreamEvent {
  const StreamEndEvent({required super.raw, super.eventId})
    : super(wireName: 'stream_end');

  @override
  bool get isTerminal => true;
}

/// A full session projection sent because a resume cursor could not be honoured.
///
/// The client must discard its cursor state and adopt this snapshot rather than
/// expecting the missed events to be replayed.
final class SessionSnapshotEvent extends StreamEvent {
  const SessionSnapshotEvent({
    required this.session,
    required super.raw,
    super.eventId,
  }) : super(wireName: 'session_snapshot');

  final Json session;
}

// --- Telemetry and planning ------------------------------------------------

/// Token and cost accounting for the run so far.
final class MeteringEvent extends StreamEvent {
  const MeteringEvent({
    required super.raw,
    this.inputTokens,
    this.outputTokens,
    this.costUsd,
    this.model,
    super.eventId,
  }) : super(wireName: 'metering');

  final int? inputTokens;
  final int? outputTokens;
  final double? costUsd;
  final String? model;

  int? get totalTokens => inputTokens == null && outputTokens == null
      ? null
      : (inputTokens ?? 0) + (outputTokens ?? 0);
}

/// How full the context window is.
final class ContextStatusEvent extends StreamEvent {
  const ContextStatusEvent({
    required super.raw,
    this.usedTokens,
    this.windowTokens,
    this.percent,
    super.eventId,
  }) : super(wireName: 'context_status');

  final int? usedTokens;
  final int? windowTokens;
  final double? percent;

  /// Fill level in `0..1`, from whichever of the fields the server sent.
  ///
  /// `percent` is accepted as either a fraction or a 0–100 value, because both
  /// have been observed; a value above 1 is read as a percentage.
  double? get fraction {
    final reported = percent;
    if (reported != null && reported.isFinite) {
      final normalised = reported > 1 ? reported / 100 : reported;
      return normalised.clamp(0.0, 1.0);
    }
    final used = usedTokens;
    final window = windowTokens;
    if (used == null || window == null || window <= 0) return null;
    return (used / window).clamp(0.0, 1.0);
  }
}

/// The agent's current goal and plan.
final class GoalEvent extends StreamEvent {
  const GoalEvent({
    required this.steps,
    required super.raw,
    this.title,
    this.status,
    super.eventId,
  }) : super(wireName: 'goal');

  final String? title;
  final String? status;
  final List<ChecklistItem> steps;
}

/// The agent is continuing toward its goal after a checkpoint.
final class GoalContinueEvent extends StreamEvent {
  const GoalContinueEvent({required super.raw, this.reason, super.eventId})
    : super(wireName: 'goal_continue');

  final String? reason;
}

/// The current todo checklist.
final class TodoStateEvent extends StreamEvent {
  const TodoStateEvent({required this.items, required super.raw, super.eventId})
    : super(wireName: 'todo_state');

  final List<ChecklistItem> items;
}

/// Text the user typed while steering that the run did not consume.
///
/// Iris restores it into the composer so the words are never lost.
final class PendingSteerEvent extends StreamEvent {
  const PendingSteerEvent({
    required this.text,
    required super.raw,
    super.eventId,
  }) : super(wireName: 'pending_steer_leftover');

  final String text;
}

/// The server durably persisted session state.
final class StateSavedEvent extends StreamEvent {
  const StateSavedEvent({required super.raw, super.eventId})
    : super(wireName: 'state_saved');
}

/// An event this build of Iris does not know about.
///
/// Kept and rendered as a labelled debug chip rather than dropped, so a server
/// running ahead of the app degrades visibly instead of silently.
final class UnknownEvent extends StreamEvent {
  const UnknownEvent({
    required super.wireName,
    required super.raw,
    super.eventId,
  });
}
