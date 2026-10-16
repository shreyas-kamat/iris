/// One conversation: its transcript, the live turn, and the composer.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/device_state.dart';
import '../../core/result.dart';
import '../../data/chat/attachment.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';
import 'attachment_picker.dart';
import 'branched_header.dart';
import 'chat_controller.dart';
import 'chat_state.dart';
import 'composer.dart';
import 'connection_card.dart';
import 'context_sheet.dart';
import 'decision_cards.dart';
import 'login_card.dart';
import 'message_menu.dart';
import 'model_sheet.dart';
import 'queue_tray.dart';
import 'transcript_view.dart';
import 'voice_recorder.dart';

/// The orb state for what the agent is doing.
AgentState agentStateFor(TurnPhase turn) => switch (turn) {
  TurnPhase.idle => AgentState.idle,
  TurnPhase.thinking => AgentState.thinking,
  TurnPhase.streaming => AgentState.streaming,
  TurnPhase.working => AgentState.working,
  TurnPhase.waiting => AgentState.waiting,
};

/// The three prompts on an empty conversation. They are the kinds of thing the
/// app is for, so a new person sees what to ask before they have to think of it.
const _suggestions = [
  'Summarize what happened overnight',
  'Draft a cron for a weekly audit',
  'What can you do on this server?',
];

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.backend,
    this.conversationId,
    this.title,
    this.archived = false,
    this.suggestions,
    this.pickFiles,
    this.recorder,
    this.branch,
    this.onBranched,
    super.key,
  });

  final ChatBackend backend;

  /// Opens the file picker. Tests pass a fake; null uses the system picker.
  final PickFiles? pickFiles;

  /// Records dictation. Tests pass a fake; null uses the microphone.
  final VoiceRecorder? recorder;

  /// Where this chat was branched from, when it was.
  final BranchRecord? branch;

  /// Called when a branch is made from here, with the new chat's stored id
  /// and where it came from, so the caller can remember it.
  final void Function(String childStoredId, BranchRecord record)? onBranched;

  /// The stored conversation to open; null starts a new one.
  final String? conversationId;
  final String? title;

  /// The conversation is archived. Sending in it first asks to bring it back,
  /// so a reply never lands somewhere the person cannot find it.
  final bool archived;

  /// What a new chat offers to ask; the general suggestions when null.
  final List<String>? suggestions;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _chat = ChatController(
    widget.backend,
    conversationId: widget.conversationId,
    title: widget.title,
  );
  final _text = TextEditingController();
  bool _unarchived = false;

  @override
  void initState() {
    super.initState();
    _chat.onPrefill = _prefill;
    _chat.onSteerReturned = _steerReturned;
    _chat.onToast = _toast;
    _chat.onBranchRequested = () => unawaited(_branch());
    _chat.onPromptReturned = _prefill;
    _text.addListener(_watchForSlash);
    unawaited(_chat.open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under reduced motion the undone exchange leaves at once.
    _chat.collapseDelay = context.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);
  }

  @override
  void dispose() {
    _text.removeListener(_watchForSlash);
    _clock?.cancel();
    unawaited(_recorder.cancel());
    _chat.dispose();
    _text.dispose();
    super.dispose();
  }

  void _toast(String message, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    showIrisToast(
      context,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      top: true,
    );
  }

  Future<void> _hold(ChatState state, TranscriptItem item, Rect anchor) async {
    final isUser = item is UserTurn;
    final text = switch (item) {
      UserTurn(:final text) => text,
      AssistantTurn(:final text) => text,
      _ => '',
    };
    if (text.trim().isEmpty) return;
    final actions = [
      MessageAction.copy,
      MessageAction.select,
      if (item is AssistantTurn && _chat.canBranchFrom(item.id))
        MessageAction.branch,
      if (isUser &&
          item.id == state.lastExchangeStartId &&
          !state.running &&
          _chat.isLive)
        MessageAction.undo,
    ];
    final chosen = await showMessageMenu(
      context,
      anchor: anchor,
      alignEnd: isUser,
      actions: actions,
    );
    if (!mounted) return;
    switch (chosen) {
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) _toast('Copied');
      case MessageAction.select:
        await showSelectableText(context, text);
      case MessageAction.undo:
        await _chat.undo();
      case MessageAction.branch:
        await _branch(fromItemId: item.id);
      case null:
        break;
    }
  }

  /// Opens the chat this one was branched from.
  void _openParent() {
    final record = widget.branch;
    if (record == null) return;
    unawaited(
      Navigator.of(context).push(
        IrisPageRoute<void>(
          builder: (_) => ChatScreen(
            backend: widget.backend,
            conversationId: record.parentId,
            title: record.parentTitle,
            pickFiles: widget.pickFiles,
            recorder: widget.recorder,
          ),
        ),
      ),
    );
  }

  Future<void> _branch({String? fromItemId, bool summarise = false}) async {
    final title = _chat.value.title ?? 'this chat';
    final result = await withBranchingOverlay(
      context,
      title,
      _chat.branch(fromItemId: fromItemId, summarise: summarise),
    );
    if (!mounted) return;
    switch (result) {
      case Err(:final failure):
        _toast(
          failure.message ??
              'Could not branch: ${ChatController.describe(failure)}',
        );
      case Ok(value: final outcome):
        final record = BranchRecord(
          parentId: _chat.conversationId!,
          parentTitle: title,
          count: outcome.count,
          at: DateTime.now().millisecondsSinceEpoch,
        );
        widget.onBranched?.call(outcome.conversation.storedId, record);
        if (summarise && !outcome.summarised) {
          _toast("Branched, but couldn't summarise");
        }
        await Navigator.of(context).pushReplacement(
          IrisPageRoute<void>(
            builder: (_) => ChatScreen(
              backend: widget.backend,
              conversationId: outcome.conversation.storedId,
              title: 'Branch of $title',
              branch: record,
              onBranched: widget.onBranched,
              pickFiles: widget.pickFiles,
              recorder: widget.recorder,
            ),
          ),
        );
    }
  }

  int? _dividerAfter(List<TranscriptItem> items, BranchRecord? record) {
    if (record == null || record.count <= 0) {
      return null;
    }
    var seen = 0;
    for (final (i, item) in items.indexed) {
      if (item is UserTurn || item is AssistantTurn) {
        if (++seen == record.count) return i;
      }
    }
    return null;
  }

  /// The command catalogue is read the first time the person types a slash.
  void _watchForSlash() {
    if (_text.text.startsWith('/')) unawaited(_chat.loadCommands());
  }

  void _prefill(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// A steer Hermes could not take goes back where it was typed.
  void _steerReturned(String text) {
    unawaited(IrisHaptics.failed());
    _prefill(text);
  }

  Future<bool> _confirmUnarchive() async {
    final id = _chat.conversationId;
    if (!widget.archived || _unarchived || id == null) return true;
    final confirmed = await showIrisSheet<bool>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Unarchive this chat?',
        subtitle:
            'It moves back to your conversations, so the reply is easy to find.',
        actions: IrisSheetActions(
          secondary: IrisButton(
            label: 'Not now',
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
          primary: IrisButton(
            label: 'Unarchive and send',
            tone: IrisButtonTone.primary,
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
    if (confirmed != true || !mounted) return false;
    switch (await widget.backend.setArchived(id, archived: false)) {
      case Ok():
        _unarchived = true;
        return true;
      case Err(:final failure):
        if (mounted) {
          showIrisToast(
            context,
            message: 'Could not unarchive: ${ChatController.describe(failure)}',
          );
        }
        return false;
    }
  }

  final List<Attachment> _draft = [];

  late final VoiceRecorder _recorder = widget.recorder ?? RecordVoiceRecorder();
  static const _maxRecording = Duration(minutes: 2);
  Duration? _recording;
  bool _transcribing = false;
  Timer? _clock;

  Future<void> _startDictation() async {
    if (!await _recorder.start()) {
      if (mounted) {
        showIrisToast(
          context,
          message:
              'Iris needs the microphone. Allow it in Settings to dictate.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _recording = Duration.zero);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = (_recording ?? Duration.zero) + const Duration(seconds: 1);
      if (next >= _maxRecording) {
        unawaited(_stopDictation());
      } else {
        setState(() => _recording = next);
      }
    });
  }

  Future<void> _stopDictation() async {
    _clock?.cancel();
    setState(() {
      _recording = null;
      _transcribing = true;
    });
    final clip = await _recorder.stop();
    final result = clip == null
        ? const Ok<String>('')
        : await widget.backend.transcribe(clip);
    if (!mounted) return;
    setState(() => _transcribing = false);
    switch (result) {
      case Ok(value: ''):
        showIrisToast(
          context,
          message: "Didn't catch that. Try again a little closer.",
        );
      case Ok(:final value):
        final before = _text.text.trimRight();
        _text.text = before.isEmpty ? value : '$before $value';
      case Err(:final failure):
        showIrisToast(
          context,
          message: "Couldn't transcribe: ${ChatController.describe(failure)}",
        );
    }
  }

  Future<void> _cancelDictation() async {
    _clock?.cancel();
    setState(() => _recording = null);
    await _recorder.cancel();
  }

  Future<void> _attach() async {
    final picked = await (widget.pickFiles ?? pickFiles)();
    if (!mounted || picked.isEmpty) return;
    final tooBig = picked.where((f) => f.bytes.length > Attachment.maxBytes);
    final fits = picked
        .where((f) => f.bytes.length <= Attachment.maxBytes)
        .toList();
    final room = Attachment.maxPerMessage - _draft.length;
    setState(() => _draft.addAll(fits.take(room)));
    if (tooBig.isNotEmpty) {
      showIrisToast(
        context,
        message: '${tooBig.first.name} is over 20 MB, so it was left out.',
      );
    } else if (fits.length > room) {
      showIrisToast(
        context,
        message: 'Up to ${Attachment.maxPerMessage} files per message.',
      );
    }
  }

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty && _draft.isEmpty) return;
    if (!await _confirmUnarchive()) return;
    final files = List.of(_draft);
    _text.clear();
    setState(_draft.clear);
    unawaited(_chat.send(text, attachments: files));
  }

  /// A suggestion takes the same path as typing it and pressing send, so it
  /// behaves identically, including clearing the field.
  void _sendSuggestion(String text) {
    _text.value = TextEditingValue(text: text);
    unawaited(_send());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ChatState>(
    valueListenable: _chat,
    builder: (context, state, _) => IrisScaffold(
      header: _ChatHeader(
        title: state.title ?? 'New conversation',
        turn: state.turn,
        connecting: state.phase == ChatPhase.loading,
        branch: widget.branch,
        onOpenParent: widget.branch == null ? null : _openParent,
      ),
      body: _body(context, state),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One decision at a time, arriving on the standard curve and
          // collapsing its height when answered, so the composer glides
          // rather than jumping.
          IrisAnimatedSize(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: context.reduceMotion
                  ? Duration.zero
                  : IrisDurations.normal,
              switchInCurve: IrisCurves.standard,
              switchOutCurve: IrisCurves.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _decision(state),
            ),
          ),
          IrisAnimatedSize(
            alignment: Alignment.bottomCenter,
            child: state.queue.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      context.window.gutter,
                      IrisSpace.sm,
                      context.window.gutter,
                      0,
                    ),
                    child: QueueTray(
                      items: state.queue,
                      paused: state.queuePaused,
                      onRemove: _chat.removeQueued,
                      onSendNext: () => unawaited(_chat.sendNextQueued()),
                      onClear: _chat.clearQueue,
                    ),
                  ),
          ),
          Composer(
            controller: _text,
            running: state.running,
            busyMode: state.busyMode,
            enabled: state.phase == ChatPhase.ready,
            commands: state.commands,
            model: state.model == null
                ? null
                : state.effort == null
                ? state.model
                : '${state.model} · ${state.effort!.wire}',
            onModel: _chat.isLive
                ? () => unawaited(showModelPicker(context, _chat))
                : null,
            contextUsage: state.context,
            attachments: [for (final f in _draft) f.name],
            onAttach: () => unawaited(_attach()),
            onRemoveAttachment: (i) => setState(() => _draft.removeAt(i)),
            recording: _recording,
            transcribing: _transcribing,
            onMic: () => unawaited(_startDictation()),
            onStopRecording: () => unawaited(_stopDictation()),
            onCancelRecording: () => unawaited(_cancelDictation()),
            onContext: state.context == null
                ? null
                : () => unawaited(
                    showContextSheet(
                      context,
                      state.context!,
                      model: state.model,
                    ),
                  ),
            state: agentStateFor(state.turn),
            onSend: () => unawaited(_send()),
            onStop: () => unawaited(_chat.stop()),
          ),
        ],
      ),
    ),
  );

  /// The most a connection card may take: 60% of the screen left over
  /// once the keyboard (up while typing a credential) and the system bars
  /// are out, and never so much that the header and composer cannot fit.
  static double _connectionRoom(BuildContext context) {
    final media = MediaQuery.of(context);
    final room =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    // The header, the composer and the gaps around the card.
    const chrome = 200.0;
    return math.max(96, math.min(room * .6, room - chrome));
  }

  Widget _decision(ChatState state) {
    if (state.approvals.isNotEmpty) {
      final request = state.approvals.first;
      return _Decision(
        key: ValueKey('approval-${request.serverRequestId ?? request.queueId}'),
        child: ApprovalCard(
          request: request,
          onChoose: (choice) => unawaited(_chat.approve(request, choice)),
        ),
      );
    }
    if (state.questions.isNotEmpty) {
      final request = state.questions.first;
      return _Decision(
        key: ValueKey(
          'clarify-${request.requestId}/${request.questions.length}',
        ),
        child: ClarifyCard(
          request: request,
          onAnswer: (question, answer) =>
              unawaited(_chat.answer(request, question, answer)),
        ),
      );
    }
    if (state.inputs.isNotEmpty) {
      final request = state.inputs.first;
      return _Decision(
        key: ValueKey('input-${request.requestId}'),
        child: InputCard(
          request: request,
          onAnswer: (value) => _chat.answerInput(request, value),
        ),
      );
    }
    if (state.connections.isNotEmpty) {
      final request = state.connections.first;
      return _Decision(
        key: ValueKey('connection-${request.opId}'),
        // A card with many rows scrolls inside a bounded slot, so it never
        // pushes the composer off the screen.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _connectionRoom(context)),
          child: SingleChildScrollView(
            child: ConnectionCard(
              request: request,
              onAnswer: (answer) =>
                  unawaited(_chat.answerConnectionTarget(request, answer)),
              onContinue: () => unawaited(_chat.settleConnection(request)),
              onOpenSignIn: (target) => unawaited(_chat.openSignIn(target)),
              onExpired: () => _chat.expireConnection(request.opId),
            ),
          ),
        ),
      );
    }
    if (state.logins.isNotEmpty) {
      final request = state.logins.first;
      return _Decision(
        key: ValueKey('login-${request.requestId}'),
        child: LoginCard(
          request: request,
          onSave: (identifier, password) => _chat.answerLogin(
            request,
            identifier: identifier,
            password: password,
          ),
          onSkip: () => _chat.skipLogin(request),
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('none'));
  }

  Widget _body(BuildContext context, ChatState state) {
    switch (state.phase) {
      case ChatPhase.loading:
        return const Center(
          child: IrisOrb(state: AgentState.loading, size: 32),
        );
      case ChatPhase.failed:
        return IrisEmptyState(
          title: 'Could not open this conversation',
          message: state.failure?.message ?? 'The dashboard did not return it.',
          action: IrisButton(
            label: 'Try again',
            tone: IrisButtonTone.primary,
            onPressed: () => unawaited(_chat.open()),
          ),
        );
      case ChatPhase.ready:
        final items = state.items;
        if (items.isEmpty) {
          return _EmptyConversation(
            onSuggestion: _sendSuggestion,
            suggestions: widget.suggestions ?? _suggestions,
          );
        }
        final hasEarlier = state.earlier != null;
        final dividerAt = _dividerAfter(items, widget.branch);
        final liveState = agentStateFor(state.turn);
        // Reversed, so the newest entry sits at the bottom and new output
        // appears where the eye already is; the way to earlier messages is
        // therefore the last item, at the top.
        return ListView.separated(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          itemCount: items.length + (hasEarlier ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 22),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return Center(
                child: IrisButton(
                  label: 'Show earlier messages',
                  tone: IrisButtonTone.ghost,
                  busy: state.loadingEarlier,
                  onPressed: () => unawaited(_chat.loadEarlier()),
                ),
              );
            }
            final item = items[items.length - 1 - index];
            // Only the turn still arriving carries the live state. Every other
            // entry is finished and rests.
            final live = item is AssistantTurn && item.streaming
                ? liveState
                : null;
            // Full readable width, so replies sit at the left edge and the
            // person's bubbles at the right, instead of each entry shrinking
            // to its own width inside the centred column.
            return ReadableColumn(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TranscriptEntry(
                      item,
                      live: live,
                      onRetry: _chat.isLive && !state.running
                          ? () => unawaited(_chat.retry())
                          : null,
                      retrying: state.retrying,
                      collapsing: state.collapsing.contains(item.id),
                      onHold: (rect) => unawaited(_hold(state, item, rect)),
                      key: ValueKey(item.id),
                    ),
                    // Where the copy ended and this chat began.
                    if (items.length - 1 - index == dividerAt)
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: BranchedDivider(
                          at: DateTime.fromMillisecondsSinceEpoch(
                            widget.branch?.at ?? 0,
                          ),
                          known: (widget.branch?.at ?? 0) > 0,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
    }
  }
}

/// The header: back, the orb in the turn's state, the title and the state's
/// word beneath it. The model no longer lives here; it moved to the composer.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.turn,
    required this.connecting,
    this.branch,
    this.onOpenParent,
  });

  final String title;
  final TurnPhase turn;

  /// True while the conversation is being opened, before any turn exists.
  final bool connecting;

  /// Where this chat was branched from, shown under the title.
  final BranchRecord? branch;
  final VoidCallback? onOpenParent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final state = connecting ? AgentState.loading : agentStateFor(turn);
    return Container(
      padding: EdgeInsets.fromLTRB(14, IrisSpace.sm, 14, IrisSpace.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.line, width: IrisStroke.hairline),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IrisCircleButton(
                icon: Icons.arrow_back_ios_new,
                semanticLabel: 'Back',
                onPressed: () => unawaited(Navigator.of(context).maybePop()),
              ),
              const SizedBox(width: IrisSpace.md - 2),
              IrisOrb(state: state, size: 34),
              const SizedBox(width: IrisSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // The colour animates with the state, so a change of state is
                    // seen as a change rather than a jump.
                    AnimatedDefaultTextStyle(
                      duration: context.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 400),
                      curve: IrisCurves.standard,
                      style: type.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: palette.colorFor(state),
                      ),
                      child: Text(connecting ? 'Connecting' : state.label),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (branch case final record?)
            BranchedHeader(
              parentTitle: record.parentTitle,
              onOpen: onOpenParent ?? () {},
            ),
        ],
      ),
    );
  }
}

/// A new conversation: the orb, a prompt, and three things to ask.
class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.onSuggestion,
    required this.suggestions,
  });

  final ValueChanged<String> onSuggestion;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IrisOrb(state: AgentState.idle, size: 110),
            const SizedBox(height: 18),
            Text(
              'What should we\nwork on?',
              textAlign: TextAlign.center,
              style: type.serif.copyWith(fontSize: 30, height: 1.1),
            ),
            const SizedBox(height: IrisSpace.sm),
            for (final text in suggestions)
              Padding(
                padding: const EdgeInsets.only(top: IrisSpace.sm),
                child: IrisPressable(
                  onTap: () => onSuggestion(text),
                  ensureTapTarget: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: IrisSpace.lg,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: palette.line,
                        width: IrisStroke.hairline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            text,
                            style: type.body.copyWith(
                              fontSize: 14,
                              color: palette.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: IrisSpace.md),
                        Icon(
                          Icons.north_east,
                          size: IrisSize.iconSmall,
                          color: palette.inkFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Room around a decision card above the composer.
class _Decision extends StatelessWidget {
  const _Decision({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      context.window.gutter,
      IrisSpace.sm,
      context.window.gutter,
      0,
    ),
    child: child,
  );
}
