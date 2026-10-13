/// One open conversation: loads it, follows its live events, sends, stops,
/// answers, pages back, switches model and runs slash commands.
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
  bool _loadingCommands = false;

  /// Called with text a slash command wants in the composer, for the person
  /// to finish and send.
  ValueChanged<String>? onPrefill;

  /// The stored id: given when opened, or set by a new chat's first send.
  String? get conversationId => _storedId;

  /// Attached to the live socket, so live calls — sending, switching model —
  /// can reach it.
  bool get isLive => _runtimeId != null;

  /// Starts following events, then reads the transcript and attaches to it.
  Future<void> open() async {
    _subscription ??= _backend.events.listen(_onEvent);
    _reconnects ??= _backend.reconnected.listen((_) => unawaited(_reattach()));
    final storedId = _storedId;
    if (storedId == null) return;
    _update(
      ChatState(
        title: value.title,
        model: value.model,
        provider: value.provider,
        commands: value.commands,
      ),
    );
    switch (await _backend.history(storedId)) {
      case Err(:final failure):
        _update(value.copyWith(phase: ChatPhase.failed, failure: failure));
        return;
      case Ok(value: final page):
        _update(value.withNewestPage(page.items, page.earlier));
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
          model: resumed.model,
          provider: resumed.provider,
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
    if (history case Ok(value: final page)) {
      _update(value.withNewestPage(page.items, page.earlier));
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
          model: again.model,
          provider: again.provider,
        );
        for (final event in again.pending) {
          next = next.apply(event);
        }
        _update(next);
    }
  }

  /// Reads the page before the oldest message shown.
  Future<void> loadEarlier() async {
    final storedId = _storedId;
    final cursor = value.earlier;
    if (storedId == null || cursor == null || value.loadingEarlier) return;
    _update(value.copyWith(loadingEarlier: true));
    final page = await _backend.history(storedId, before: cursor);
    switch (page) {
      case Err(:final failure):
        _update(
          value
              .copyWith(loadingEarlier: false)
              .withNotice(
                'Could not load earlier messages: ${describe(failure)}',
              ),
        );
      case Ok(value: final earlier):
        _update(value.withEarlierPage(earlier.items, earlier.earlier));
    }
  }

  /// Reads the slash-command catalogue once, the first time it is wanted —
  /// when the person types a slash — rather than with every conversation.
  Future<void> loadCommands() async {
    if (value.commands.isNotEmpty || _loadingCommands) return;
    _loadingCommands = true;
    final result = await _backend.commands();
    _loadingCommands = false;
    if (result case Ok(value: final commands)) {
      _update(value.copyWith(commands: commands));
    }
  }

  /// Sends [text], creating the conversation first if this is a new chat.
  /// Text that starts with a slash runs as a command.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || value.running) return;
    _update(value.withUserTurn(trimmed));
    final runtimeId = _runtimeId ?? await _create();
    if (runtimeId == null) return;
    if (trimmed.startsWith('/') && trimmed.length > 1) {
      await _slash(runtimeId, trimmed, depth: 0);
    } else {
      await _submit(runtimeId, trimmed);
    }
  }

  Future<void> _submit(String runtimeId, String text) async {
    final sent = await _backend.submit(runtimeId, text);
    if (sent case Err(:final failure)) {
      _update(value.withError(describe(failure)));
    }
  }

  /// Runs a slash command and does what it asks: show output, send a prompt,
  /// fill the composer, or follow an alias — at most three deep, so an alias
  /// loop cannot spin forever.
  Future<void> _slash(
    String runtimeId,
    String command, {
    required int depth,
  }) async {
    final result = await _backend.runSlash(runtimeId, command);
    if (_disposed) return;
    switch (result) {
      case Err(:final failure):
        _update(value.withError(describe(failure)));
      case Ok(value: final outcome):
        switch (outcome.kind) {
          case SlashKind.exec:
            final output = outcome.text.trim();
            _update(value.withNotice(output.isEmpty ? 'Done.' : output).settled());
          case SlashKind.send:
            final prompt = outcome.text.trim();
            if (prompt.isEmpty) {
              _update(value.settled());
            } else {
              _update(value.withUserTurn(prompt));
              await _submit(runtimeId, prompt);
            }
          case SlashKind.prefill:
            _update(value.withNotice(outcome.notice).settled());
            if (outcome.text.isNotEmpty) onPrefill?.call(outcome.text);
          case SlashKind.alias:
            final target = outcome.target.trim();
            if (target.isEmpty || depth >= 3) {
              final output = outcome.text.trim();
              _update(
                value
                    .withNotice(
                      output.isEmpty ? 'That command points nowhere.' : output,
                    )
                    .settled(),
              );
              return;
            }
            final space = command.indexOf(' ');
            final arguments = space < 0 ? '' : command.substring(space);
            final next = target.startsWith('/') ? target : '/$target';
            await _slash(runtimeId, '$next$arguments', depth: depth + 1);
        }
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

  /// What this conversation can switch to.
  Future<Result<ModelOptions>> modelOptions() =>
      _backend.modelOptions(runtimeId: _runtimeId);

  /// Switches this conversation's model. A switch Hermes wants confirmed
  /// changes nothing and comes back with `confirmRequired`, for the screen to
  /// ask and call again with [confirmed].
  Future<Result<ModelSwitch>> switchModel(
    String model,
    String provider, {
    required bool confirmed,
  }) async {
    final runtimeId = _runtimeId;
    if (runtimeId == null) {
      return const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'Send a message first: a new conversation has no model yet.',
        ),
      );
    }
    final result = await _backend.switchModel(
      runtimeId,
      model: model,
      provider: provider,
      confirmed: confirmed,
    );
    switch (result) {
      case Err(:final failure):
        _update(
          value.withNotice('Could not switch the model: ${describe(failure)}'),
        );
      case Ok(value: final change) when !change.confirmRequired:
        _update(
          value
              .copyWith(model: change.model, provider: provider)
              .withNotice(
                change.deferred
                    ? 'Switches to ${change.model} when this turn ends.'
                    : 'Now using ${change.model}.',
              ),
        );
      case Ok():
        break;
    }
    return result;
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
