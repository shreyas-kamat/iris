/// One conversation: its transcript, the live turn, and the composer.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/chat_backend.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'chat_controller.dart';
import 'chat_state.dart';
import 'composer.dart';
import 'decision_cards.dart';
import 'model_sheet.dart';
import 'transcript_view.dart';

/// The aperture state for what the agent is doing.
AgentState agentStateFor(TurnPhase turn) => switch (turn) {
  TurnPhase.idle => AgentState.idle,
  TurnPhase.thinking => AgentState.thinking,
  TurnPhase.streaming => AgentState.streaming,
  TurnPhase.working => AgentState.working,
  TurnPhase.waiting => AgentState.waiting,
};

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.backend,
    this.conversationId,
    this.title,
    super.key,
  });

  final ChatBackend backend;

  /// The stored conversation to open; null starts a new one.
  final String? conversationId;
  final String? title;

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

  @override
  void initState() {
    super.initState();
    _chat.onPrefill = _prefill;
    _text.addListener(_watchForSlash);
    unawaited(_chat.open());
  }

  @override
  void dispose() {
    _text.removeListener(_watchForSlash);
    _chat.dispose();
    _text.dispose();
    super.dispose();
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

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    unawaited(_chat.send(text));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ChatState>(
    valueListenable: _chat,
    builder: (context, state, _) => IrisScaffold(
      header: _ChatHeader(
        title: state.title ?? 'New conversation',
        turn: state.turn,
        model: state.model,
        onModel: _chat.isLive
            ? () => unawaited(showModelPicker(context, _chat))
            : null,
      ),
      body: _body(context, state),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.approvals.isNotEmpty)
            _Decision(
              child: ApprovalCard(
                request: state.approvals.first,
                onChoose: (choice) =>
                    unawaited(_chat.approve(state.approvals.first, choice)),
              ),
            )
          else if (state.questions.isNotEmpty)
            _Decision(
              child: ClarifyCard(
                key: ValueKey(
                  '${state.questions.first.requestId}/'
                  '${state.questions.first.questions.length}',
                ),
                request: state.questions.first,
                onAnswer: (question, answer) => unawaited(
                  _chat.answer(state.questions.first, question, answer),
                ),
              ),
            ),
          Composer(
            controller: _text,
            running: state.running,
            enabled: state.phase == ChatPhase.ready,
            commands: state.commands,
            onSend: _send,
            onStop: () => unawaited(_chat.stop()),
          ),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context, ChatState state) {
    switch (state.phase) {
      case ChatPhase.loading:
        return const Center(
          child: IrisOrb(state: AgentState.thinking, size: 32),
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
          return const IrisEmptyState(
            title: 'New conversation',
            message: 'Ask your agent anything.',
          );
        }
        final hasEarlier = state.earlier != null;
        // Reversed, so the newest entry sits at the bottom and new output
        // appears where the eye already is; the way to earlier messages is
        // therefore the last item, at the top.
        return ListView.separated(
          reverse: true,
          padding: EdgeInsets.symmetric(
            horizontal: context.window.gutter,
            vertical: IrisSpace.lg,
          ),
          itemCount: items.length + (hasEarlier ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: IrisSpace.md),
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
            // Full readable width, so replies sit at the left edge and the
            // person's bubbles at the right, instead of each entry shrinking
            // to its own width inside the centred column.
            return ReadableColumn(
              child: SizedBox(
                width: double.infinity,
                child: TranscriptEntry(item, key: ValueKey(item.id)),
              ),
            );
          },
        );
    }
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.turn,
    this.model,
    this.onModel,
  });

  final String title;
  final TurnPhase turn;
  final String? model;

  /// Opens the model picker; null while the conversation is not live.
  final VoidCallback? onModel;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        IrisSpace.xs,
        IrisSpace.sm,
        context.window.gutter,
        IrisSpace.sm,
      ),
      child: Row(
        children: [
          IrisPressable(
            onTap: () => unawaited(Navigator.of(context).maybePop()),
            semanticLabel: 'Back',
            child: SizedBox.square(
              dimension: IrisSize.minTapTarget,
              child: Icon(
                Icons.arrow_back_ios_new,
                size: IrisSize.icon,
                color: theme.palette.ink,
              ),
            ),
          ),
          const SizedBox(width: IrisSpace.xs),
          IrisOrb(state: agentStateFor(turn)),
          const SizedBox(width: IrisSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.heading,
                ),
                if (model case final model?)
                  IrisPressable(
                    onTap: onModel,
                    semanticLabel: 'Model: $model',
                    ensureTapTarget: false,
                    child: Text(
                      onModel == null ? model : '$model ▾',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption.copyWith(
                        color: theme.palette.inkMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Room around a decision card above the composer.
class _Decision extends StatelessWidget {
  const _Decision({required this.child});

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
