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
import '../voice/mic_permission_sheet.dart';
import '../voice/voice_call.dart';
import '../voice/voice_call_screen.dart';
import '../voice/voice_host.dart';
import 'attachment_picker.dart';
import 'branched_header.dart';
import 'chat_controller.dart';
import 'chat_export.dart';
import 'chat_menu_sheet.dart';
import 'chat_state.dart';
import 'composer.dart';
import 'connection_card.dart';
import 'context_sheet.dart';
import 'conversation_actions.dart';
import 'decision_cards.dart';
import 'login_card.dart';
import 'message_menu.dart';
import 'model_sheet.dart';
import 'queue_tray.dart';
import 'session_info_sheet.dart';
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

/// What the host can do to this conversation beyond what the chat itself
/// owns. A host that passes none gets a menu without Pin, Archive and Delete.
class ChatMenuHooks {
  const ChatMenuHooks({
    required this.isPinned,
    required this.onTogglePin,
    required this.onArchive,
    required this.onDelete,
  });

  final bool Function() isPinned;
  final VoidCallback onTogglePin;

  /// Archives the conversation; true when it was archived.
  final Future<bool> Function() onArchive;

  /// Deletes it, after its own confirm; true when it was deleted.
  final Future<bool> Function() onDelete;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.backend,
    this.conversationId,
    this.title,
    this.archived = false,
    this.suggestions,
    this.pickFiles,
    this.recorder,
    this.voice,
    this.branch,
    this.onBranched,
    this.menu,
    this.shareMarkdown,
    super.key,
  });

  final ChatBackend backend;

  /// Opens the file picker. Tests pass a fake; null uses the system picker.
  final PickFiles? pickFiles;

  /// Records dictation. Tests pass a fake; null uses the microphone.
  final VoiceRecorder? recorder;

  /// What voice needs from the app: null where there is no voice (the
  /// server has none, or the host screen does not offer it).
  final VoiceHost? voice;

  /// Where this chat was branched from, when it was.
  final BranchRecord? branch;

  /// Called when a branch is made from here, with the new chat's stored id
  /// and where it came from, so the caller can remember it.
  final void Function(String childStoredId, BranchRecord record)? onBranched;

  /// Pin, Archive and Delete from the ⋯ menu; those rows are left out when null.
  final ChatMenuHooks? menu;

  /// Shares the exported transcript. Tests pass a fake; null opens the system
  /// share sheet.
  final ShareMarkdown? shareMarkdown;

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

  /// The open voice call, if there is one.
  VoiceCall? _call;

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
    _missedTimer?.cancel();
    unawaited(_recorder.cancel());
    unawaited(_call?.end());
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
            onBranched: widget.onBranched,
            pickFiles: widget.pickFiles,
            recorder: widget.recorder,
            shareMarkdown: widget.shareMarkdown,
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
              shareMarkdown: widget.shareMarkdown,
            ),
          ),
        );
    }
  }

  Future<void> _openMenu(ChatState state) async {
    final menu = widget.menu;
    final id = _chat.conversationId;
    final title = state.title ?? 'this chat';
    final action = await showChatMenu(
      context,
      title: title,
      pinned: menu?.isPinned() ?? false,
      replying: state.running,
      live: _chat.isLive,
      canPin: menu != null && id != null,
      canArchive: menu != null && id != null && !widget.archived,
      canDelete: menu != null && id != null,
      canUndo: state.lastExchangeStartId != null,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case ChatMenuAction.rename:
        final next = await showRenameSheet(context, title);
        if (next != null && mounted) await _chat.rename(next);
      case ChatMenuAction.pin:
        menu?.onTogglePin();
      case ChatMenuAction.branch:
        await _branch();
      case ChatMenuAction.archive:
        if (menu != null && await menu.onArchive() && mounted) {
          Navigator.of(context).pop();
        }
      case ChatMenuAction.compress:
        await _chat.compress();
      case ChatMenuAction.undo:
        await _chat.undo();
      case ChatMenuAction.export:
        await _export(state);
      case ChatMenuAction.info:
        await _showInfo(state);
      case ChatMenuAction.delete:
        if (menu != null && await menu.onDelete() && mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  Future<void> _showInfo(ChatState state) async {
    final id = _chat.conversationId;
    final summary = id == null
        ? null
        : (await widget.backend.conversation(id)).valueOrNull;
    if (!mounted) return;
    final used = state.context;
    await showSessionInfo(
      context,
      SessionInfo(
        title: state.title ?? 'New conversation',
        profile: summary?.profile ?? 'default',
        model: state.model,
        lastActive: summary?.startedAt,
        // 0 is what an unread count looks like: leave the row out instead.
        messages: summary != null && summary.messageCount > 0
            ? summary.messageCount
            : null,
        contextPercent: used?.percent,
        contextUsed: used?.used,
        contextMax: used?.max,
        sessionId: id,
      ),
    );
  }

  Future<void> _export(ChatState state) async {
    final title = state.title ?? 'Chat';
    _toast('Preparing…');
    final items = await _chat.fullTranscript();
    if (!mounted) return;
    try {
      await (widget.shareMarkdown ?? shareMarkdownFile)(
        fileName: exportFileName(title),
        title: title,
        markdown: transcriptMarkdown(title, items),
      );
    } on Object {
      if (mounted) _toast("Couldn't share this chat");
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

  /// The server's cap on a clip; two minutes when it has not said.
  Duration get _maxRecording =>
      widget.voice?.capabilities.tuning.maxRecording ??
      const Duration(minutes: 2);
  Duration? _recording;
  bool _transcribing = false;
  Timer? _clock;

  /// The clip said nothing: a note above the composer offers another go.
  bool _missed = false;
  Timer? _missedTimer;

  Future<void> _startDictation() async {
    _missedTimer?.cancel();
    if (_missed) setState(() => _missed = false);
    if (await ensureMicAccess(context) == MicAccess.denied) return;
    if (!mounted) return;
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

  /// The voice button. Asks for the microphone the way dictation does, then
  /// opens the call screen. "Call again" on that screen starts the next call
  /// from here, so only one call exists at a time.
  Future<void> _startCall() async {
    final host = widget.voice;
    if (host == null || _call != null) return;
    if (await ensureMicAccess(context) == MicAccess.denied) return;
    if (!mounted || _call != null) return;
    var again = true;
    while (again && mounted) {
      final parts = host.parts(host.settings);
      final call = _call = VoiceCall(
        chat: _chat,
        backend: widget.backend,
        voice: host.backend,
        capabilities: host.capabilities,
        settings: host.settings,
        mic: parts.mic,
        out: parts.out,
        route: parts.route,
        server: host.server,
        livePeer: parts.livePeer,
        service: parts.service,
      );
      final startedAt = DateTime.now();
      final fromIndex = _chat.value.items.length;
      var listened = false;
      void watch() {
        final mode = call.value.mode;
        if (mode != CallMode.connecting &&
            mode != CallMode.error &&
            mode != CallMode.ended) {
          listened = true;
        }
      }

      call.addListener(watch);
      unawaited(call.begin());
      if (!mounted) break;
      final exit = await openVoiceCall(context, call: call, awake: parts.awake);
      call.removeListener(watch);
      _call = null;
      await call.end();
      call.dispose();
      final storedId = _chat.conversationId;
      if (listened && storedId != null) {
        host.onCallEnded(
          storedId,
          VoiceCallSpan(
            startedAt: startedAt,
            endedAt: DateTime.now(),
            fromIndex: fromIndex,
          ),
        );
      }
      again = exit == VoiceCallExit.again;
    }
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
        setState(() => _missed = true);
        _missedTimer?.cancel();
        _missedTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _missed = false);
        });
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

  Future<void> _attach(AttachSource source) async {
    final picked = await (widget.pickFiles ?? pickFiles)(source);
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
        message: '${tooBig.first.name} is too large. Files can be up to 20 MB.',
        top: true,
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
        onMenu: () => unawaited(_openMenu(state)),
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
          if (_missed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.window.gutter,
                IrisSpace.sm,
                context.window.gutter,
                0,
              ),
              child: _MissedNote(
                onTryAgain: () => unawaited(_startDictation()),
              ),
            ),
          if ((state.context?.percent ?? 0) >= 95)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.window.gutter,
                IrisSpace.sm,
                context.window.gutter,
                0,
              ),
              child: ContextStrip(
                onBranch: () => unawaited(_branch(summarise: true)),
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
            attachments: _draft,
            onAttach: (source) => unawaited(_attach(source)),
            onRemoveAttachment: (i) => setState(() => _draft.removeAt(i)),
            recording: _recording,
            level: _recording == null ? null : _recorder.level,
            transcribing: _transcribing,
            onMic: () => unawaited(_startDictation()),
            maxRecording: _maxRecording,
            voiceMode: widget.voice?.capabilities.voiceMode ?? false,
            onVoice: widget.voice?.capabilities.voiceMode ?? false
                ? () => unawaited(_startCall())
                : null,
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
                      attempt: state.attempt,
                      onStop: () => unawaited(_chat.stop()),
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
    this.onMenu,
  });

  final String title;
  final TurnPhase turn;

  /// True while the conversation is being opened, before any turn exists.
  final bool connecting;

  /// Where this chat was branched from, shown under the title.
  final BranchRecord? branch;
  final VoidCallback? onOpenParent;
  final VoidCallback? onMenu;

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
              if (onMenu != null) ...[
                const SizedBox(width: IrisSpace.sm),
                IrisCircleButton(
                  icon: Icons.more_horiz,
                  semanticLabel: 'More',
                  onPressed: onMenu,
                ),
              ],
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

/// Shown after a clip that said nothing (frame B9): the mic is one tap from
/// trying again. It goes by itself after six seconds.
class _MissedNote extends StatelessWidget {
  const _MissedNote({required this.onTryAgain});

  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: IrisSpace.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: Row(
        children: [
          const IrisOrb(state: AgentState.rest, size: 24, glow: false),
          const SizedBox(width: IrisSpace.sm),
          Expanded(
            child: Text(
              "Didn't catch that.",
              style: context.type.body.copyWith(
                fontSize: 13.5,
                color: palette.ink,
              ),
            ),
          ),
          IrisPressable(
            onTap: onTryAgain,
            semanticLabel: 'Try again',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.md),
              child: Text(
                'Try again',
                style: context.type.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
