/// One open conversation: loads it, follows its live events, sends, stops and
/// answers.
///
/// A [ValueNotifier] rather than a provider: a conversation lives exactly as
/// long as its screen, and the screen owns it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_event.dart';
import '../../data/chat/chat_models.dart';
import 'chat_state.dart';

final class ChatController extends ValueNotifier<ChatState> {
  ChatController(this._backend, {String? conversationId, String? title})
    : _storedId = conversationId,
      super(
        ChatState(
          phase: conversationId == null ? ChatPhase.ready : ChatPhase.loading,
          title: title,
        ),
      );

  final ChatBackend _backend;
  String? _storedId;
  String? _runtimeId;
  StreamSubscription<ChatEvent>? _subscription;
  StreamSubscription<void>? _reconnects;
  bool _disposed = false;

  /// The stored id: given when opened, or set by a new chat's first send.
  String? get conversationId => _storedId;

  /// Starts following events, then reads the transcript and attaches to it.
  Future<void> open() async {
    _subscription ??= _backend.events.listen(_onEvent);
    _reconnects ??= _backend.reconnected.listen((_) => unawaited(_reattach()));
    final storedId = _storedId;
    if (storedId == null) return;
    _update(ChatState(title: value.title));
    switch (await _backend.history(storedId)) {
      case Err(:final failure):
        _update(value.copyWith(phase: ChatPhase.failed, failure: failure));
        return;
      case Ok(value: final items):
        _update(value.copyWith(phase: ChatPhase.ready, items: items));
    }
    if (_disposed) return;
    switch (await _backend.resume(storedId)) {
      case Err(:final failure):
        // Readable but not live: the history stays, and the transcript says
        // why sending may not work.
        _update(value.withError(describe(failure)));
      case Ok(value: final resumed):
        _runtimeId = resumed.runtimeId;
        var next = value.copyWith(
          turn: resumed.running ? TurnPhase.thinking : null,
        );
        for (final event in resumed.pending) {
          next = next.apply(event);
        }
        _update(next);
    }
  }

  /// After a reconnect. The old runtime session went with the old socket, so
  /// its events and any Stop would go nowhere: read what was said while away,
  /// then attach again. The old runtime id is kept until the new one arrives,
  /// so a send in between does not start a second conversation.
  Future<void> _reattach() async {
    final storedId = _storedId;
    if (storedId == null || _disposed) return;
    final history = await _backend.history(storedId);
    if (_disposed) return;
    if (history case Ok(value: final items)) {
      _update(value.copyWith(phase: ChatPhase.ready, items: items));
    }
    final resumed = await _backend.resume(storedId);
    if (_disposed) return;
    switch (resumed) {
      case Err(:final failure):
        _update(value.withError(describe(failure)));
      case Ok(value: final again):
        _runtimeId = again.runtimeId;
        // Decisions are re-announced by the resume, so stale cards go.
        var next = value.copyWith(
          turn: again.running
              ? (value.running ? value.turn : TurnPhase.thinking)
              : TurnPhase.idle,
          approvals: const [],
          questions: const [],
        );
        for (final event in again.pending) {
          next = next.apply(event);
        }
        _update(next);
    }
  }

  /// Sends [text], creating the conversation first if this is a new chat.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || value.running) return;
    _update(value.withUserTurn(trimmed));
    final runtimeId = _runtimeId ?? await _create();
    if (runtimeId == null) return;
    final sent = await _backend.submit(runtimeId, trimmed);
    if (sent case Err(:final failure)) {
      _update(value.withError(describe(failure)));
    }
  }

  /// Stops the running turn.
  Future<void> stop() async {
    final runtimeId = _runtimeId;
    if (runtimeId == null || !value.running) return;
    final result = await _backend.interrupt(runtimeId);
    if (result case Err(:final failure)) {
      _update(value.withError(describe(failure)));
    }
  }

  /// Answers [request] with [choice]. The card goes at once and comes back if
  /// the answer could not be sent, so the agent is never left waiting on a
  /// card nobody can see.
  Future<void> approve(ApprovalRequest request, String choice) async {
    _update(value.withoutApproval(request));
    final result = await _backend.answerApproval(request, choice);
    if (result case Err(:final failure)) {
      _update(
        value
            .withApproval(request)
            .withError('Could not send the answer: ${describe(failure)}'),
      );
    }
  }

  /// Answers one [question] of [request].
  Future<void> answer(
    ClarifyRequest request,
    ClarifyQuestion question,
    String answer,
  ) async {
    final text = answer.trim();
    if (text.isEmpty) return;
    _update(value.withoutQuestion(request, question));
    final result = await _backend.answerClarify(request, question, text);
    if (result case Err(:final failure)) {
      _update(
        value
            .withQuestion(request)
            .withError('Could not send the answer: ${describe(failure)}'),
      );
    }
  }

  /// What to say about [failure] in the transcript.
  static String describe(IrisFailure failure) => switch (failure.kind) {
    FailureKind.offline =>
      'Not connected to your agent. Iris reconnects on its own; try again in '
          'a moment.',
    FailureKind.timeout => 'Your agent did not answer in time.',
    _ => failure.message ?? 'Something went wrong (${failure.kind.name}).',
  };

  /// Creates the conversation behind a new chat. Null if that failed, after
  /// saying why in the transcript.
  Future<String?> _create() async {
    switch (await _backend.create()) {
      case Err(:final failure):
        _update(value.withError(describe(failure)));
        return null;
      case Ok(value: final created):
        _storedId = created.storedId;
        return _runtimeId = created.runtimeId;
    }
  }

  void _onEvent(ChatEvent event) {
    final id = event.sessionId;
    if (id.isEmpty || (id != _runtimeId && id != _storedId)) return;
    _update(value.apply(event));
  }

  void _update(ChatState next) {
    if (!_disposed) value = next;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_reconnects?.cancel());
    super.dispose();
  }
}
