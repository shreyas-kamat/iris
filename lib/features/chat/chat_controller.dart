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
import '../../data/chat/attachment.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_event.dart';
import '../../data/chat/chat_models.dart';
import '../../data/rpc/rpc_frame.dart';
import 'chat_state.dart';

typedef ToastCallback =
    void Function(
      String message, {
      String? actionLabel,
      VoidCallback? onAction,
    });

/// What branching made.
final class BranchOutcome {
  const BranchOutcome({
    required this.conversation,
    required this.count,
    required this.summarised,
  });

  final NewConversation conversation;

  /// Messages copied from the parent.
  final int count;

  /// The new chat was compressed too (the context strip's Branch).
  final bool summarised;
}

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

  /// A retry ran; read the newest page once the new turn settles.
  bool _reloadWhenIdle = false;

  /// Called with text a slash command wants in the composer, for the person
  /// to finish and send.
  ValueChanged<String>? onPrefill;

  /// Called with steer text Hermes could not take, so the screen can put it
  /// back in the composer.
  ValueChanged<String>? onSteerReturned;

  /// Shows a short message to the person; the screen turns it into a toast.
  ToastCallback? onToast;

  /// Called when `/branch` is typed: the screen branches with its own
  /// overlay and navigation.
  VoidCallback? onBranchRequested;

  /// Called with the text of an undone prompt, so the screen can put it back
  /// in the composer for editing.
  ValueChanged<String>? onPromptReturned;

  /// How long the undone exchange takes to collapse before it leaves the
  /// transcript. The screen sets zero under reduced motion.
  Duration collapseDelay = const Duration(milliseconds: 320);

  /// Commands Iris itself answers, offered even when the server's catalogue
  /// lacks them.
  static const localCommands = [
    SlashCommand(name: '/queue', description: 'Send after the current reply'),
    SlashCommand(
      name: '/steer',
      description: 'Slip into the running turn at its next step',
    ),
    SlashCommand(
      name: '/undo',
      description: 'Remove the last turn and edit your prompt',
    ),
    SlashCommand(name: '/branch', description: 'Copy this chat into a new one'),
  ];

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
          context: resumed.context,
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
          inputs: const [],
          model: again.model,
          provider: again.provider,
          context: again.context,
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
      _update(value.copyWith(commands: _withLocalCommands(commands)));
    }
  }

  static List<SlashCommand> _withLocalCommands(List<SlashCommand> served) => [
    ...served,
    for (final local in localCommands)
      if (!served.any((c) => c.name == local.name)) local,
  ];

  /// Sends [text], creating the conversation first if this is a new chat.
  /// Text that starts with a slash runs as a command. During a run, text
  /// steers the turn instead; a command cannot steer, so it waits.
  Future<void> send(
    String text, {
    List<Attachment> attachments = const [],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    if (trimmed == '/undo') {
      await undo();
      return;
    }
    if (trimmed == '/branch') {
      onBranchRequested?.call();
      return;
    }
    if (value.running) {
      if (!trimmed.startsWith('/')) await _steer(trimmed);
      return;
    }
    _update(
      value.withUserTurn(
        trimmed,
        attachments: [for (final file in attachments) file.name],
      ),
    );
    final runtimeId = _runtimeId ?? await _create();
    if (runtimeId == null) return;
    if (attachments.isEmpty && trimmed.startsWith('/') && trimmed.length > 1) {
      await _slash(runtimeId, trimmed, depth: 0);
      return;
    }
    final references = <String>[];
    for (final file in attachments) {
      switch (await _backend.attach(runtimeId, file)) {
        case Ok(value: final reference?):
          references.add(reference);
        case Ok():
          break;
        case Err(:final failure):
          _update(value.withError(describe(failure)));
          return;
      }
    }
    await _submit(runtimeId, promptWithReferences(trimmed, references));
  }

  /// The user and assistant text in [items], oldest first. Tool calls,
  /// notices and empty turns are left out: they are not conversation.
  static List<SeedMessage> seedFrom(List<TranscriptItem> items) => [
    for (final item in items)
      if (item is UserTurn && item.text.trim().isNotEmpty)
        SeedMessage('user', item.text)
      else if (item is AssistantTurn && item.text.trim().isNotEmpty)
        SeedMessage('assistant', item.text),
  ];

  /// Whether a branch can start at [itemId]: the chat is stored, and that
  /// reply is finished.
  bool canBranchFrom(String itemId) {
    if (_storedId == null) return false;
    final item = value.items.where((i) => i.id == itemId);
    if (item.isEmpty) return false;
    final it = item.first;
    return it is AssistantTurn && !it.streaming;
  }

  /// The prefix up to and including [itemId], reading earlier pages first
  /// so it is whole. Null when [itemId] is not in this conversation.
  Future<List<SeedMessage>?> prefixThrough(String itemId) async {
    var pages = 0;
    while (value.earlier != null && pages++ < 60) {
      await loadEarlier();
      if (_disposed) return null;
    }
    final at = value.items.indexWhere((i) => i.id == itemId);
    if (at < 0) return null;
    return seedFrom(value.items.sublist(0, at + 1));
  }

  /// Copies this conversation into a new one: all of it, or up to the reply
  /// [fromItemId]. With [summarise], the copy is compressed too.
  Future<Result<BranchOutcome>> branch({
    String? fromItemId,
    bool summarise = false,
  }) async {
    final storedId = _storedId;
    if (storedId == null) {
      return const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'Send a message first: there is nothing to branch yet.',
        ),
      );
    }
    final lastReply = value.items.whereType<AssistantTurn>().isEmpty
        ? null
        : value.items.whereType<AssistantTurn>().last.id;
    final whole = fromItemId == null || fromItemId == lastReply;
    final List<SeedMessage>? prefix;
    if (whole) {
      prefix = null;
    } else {
      prefix = await prefixThrough(fromItemId);
      if (prefix == null) {
        return const Err(
          IrisFailure(
            FailureKind.rejected,
            message: "That message isn't in this chat any more.",
          ),
        );
      }
    }
    final result = whole
        ? await _backend.branchWhole(storedId)
        : await _backend.branchFrom(
            storedId,
            prefix!,
            title: 'Branch of ${value.title ?? 'conversation'}',
          );
    switch (result) {
      case Err(:final failure):
        return Err(
          (failure.rpcError?.isMethodNotFound ?? false)
              ? const IrisFailure(
                  FailureKind.rejected,
                  message: "This server can't branch conversations.",
                )
              : failure,
        );
      case Ok(value: final created):
        var summarised = false;
        if (summarise) {
          summarised = (await _backend.compress(created.runtimeId)).isOk;
        }
        return Ok(
          BranchOutcome(
            conversation: created,
            count: (prefix ?? seedFrom(value.items)).length,
            summarised: summarised,
          ),
        );
    }
  }

  /// Takes back the last exchange and hands its prompt back for editing.
  Future<void> undo() async {
    final runtimeId = _runtimeId;
    void say(String message, {String? actionLabel, VoidCallback? onAction}) =>
        onToast?.call(message, actionLabel: actionLabel, onAction: onAction);
    if (runtimeId == null) {
      say('Nothing to undo');
      return;
    }
    if (value.running) {
      say(
        'Stop the reply first to undo.',
        actionLabel: 'Stop',
        onAction: () => unawaited(stop()),
      );
      return;
    }
    final result = await _backend.undo(runtimeId);
    if (_disposed) return;
    switch (result) {
      case Err(:final failure):
        final rpc = failure.rpcError;
        if (rpc?.isMethodNotFound ?? false) {
          say("Undo isn't supported on this server.");
        } else if (rpc?.code == 4009) {
          say(
            'Stop the reply first to undo.',
            actionLabel: 'Stop',
            onAction: () => unawaited(stop()),
          );
        } else {
          say('Could not undo: ${describe(failure)}');
        }
      case Ok(value: 0):
        say('Nothing to undo');
      case Ok():
        final start = value.lastExchangeStartId;
        if (start == null) {
          // The turn began before the page that is loaded: read it again.
          await _reloadNewest();
          say('Undid the last turn');
          return;
        }
        final turn = value.items.firstWhere((i) => i.id == start) as UserTurn;
        _update(value.withCollapsing(value.lastExchangeIds));
        if (collapseDelay > Duration.zero) {
          await Future<void>.delayed(collapseDelay);
        }
        if (_disposed) return;
        _update(value.withoutLastExchange());
        onPromptReturned?.call(turn.text);
        say(
          turn.attachments.isEmpty
              ? 'Undid the last turn'
              : 'Undid the last turn. Re-attach any files.',
        );
    }
  }

  Future<void> _submit(String runtimeId, String text) async {
    final sent = await _backend.submit(runtimeId, text);
    if (sent case Err(:final failure)) {
      _update(value.withError(describe(failure)));
    }
  }

  Future<void> _steer(String text) async {
    final runtimeId = _runtimeId;
    if (runtimeId == null) return;
    final result = await _backend.steer(runtimeId, text);
    if (_disposed) return;
    switch (result) {
      case Ok(value: SteerOutcome.accepted):
        _update(value.withSteer(text));
      case Ok() when !value.running:
        // The turn ended while the steer was on its way: it becomes a prompt.
        _update(value.withUserTurn(text));
        await _submit(runtimeId, text);
      case Ok():
        onSteerReturned?.call(text);
        _update(
          value.withNotice(
            "Hermes couldn't take that mid-turn — send it when the turn ends.",
          ),
        );
      case Err(:final failure):
        onSteerReturned?.call(text);
        _update(value.withNotice('Could not steer: ${describe(failure)}'));
    }
  }

  /// Asks Hermes to run the failed turn again. Hermes replaces the failed
  /// exchange itself, so once the new turn settles the newest page is read
  /// again, and the transcript shows what Hermes now holds rather than the
  /// failure and the retry side by side.
  Future<void> retry() async {
    final runtimeId = _runtimeId;
    if (runtimeId == null || value.running || value.retrying) return;
    _update(value.copyWith(retrying: true, turn: TurnPhase.thinking));
    await _slash(runtimeId, '/retry', depth: 0);
    if (_disposed) return;
    if (value.running) {
      _reloadWhenIdle = true;
    } else {
      await _reloadNewest();
    }
  }

  Future<void> _reloadNewest() async {
    _reloadWhenIdle = false;
    final storedId = _storedId;
    if (storedId == null) return;
    final page = await _backend.history(storedId);
    if (_disposed) return;
    _update(switch (page) {
      Ok(value: final newest) => value.withNewestPage(
        newest.items,
        newest.earlier,
      ),
      Err() => value.copyWith(retrying: false),
    });
  }

  /// Answers a sudo or secret prompt; an empty [answer] skips it. The card
  /// goes at once. The answer is passed straight to the backend and kept
  /// nowhere, not even in the notice that records it was sent.
  Future<void> answerInput(InputRequest request, String answer) async {
    _update(value.withoutInput(request));
    final result = await _backend.answerInput(request, answer);
    if (_disposed) return;
    switch (result) {
      case Ok():
        _update(
          value.withNotice(
            answer.isEmpty
                ? 'Skipped.'
                : request.kind == InputKind.sudo
                ? 'Sent your sudo password.'
                : 'Sent.',
          ),
        );
      case Err(:final failure):
        _update(
          value
              .withInput(request)
              .withError('Could not send that: ${describe(failure)}'),
        );
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
            _update(
              value.withNotice(output.isEmpty ? 'Done.' : output).settled(),
            );
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
    if (_reloadWhenIdle && !value.running) unawaited(_reloadNewest());
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
