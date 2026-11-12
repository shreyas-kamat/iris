/// "Study my work": explains what a study reads, starts one in an "Iris setup" chat, shows how it is going, and says
/// what it found. Reviewing the proposals is a separate screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/genui_providers.dart';
import '../../app/providers.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../chat/chat_screen.dart';
import 'study_controller.dart';

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({this.onReview, super.key});

  /// Opens the review of what was found; the button is left out when null.
  final VoidCallback? onReview;

  /// What a study reads, said plainly before anything starts.
  static const reads = [
    'Your agent’s memory',
    'Your chats from about the last 90 days',
    'Your skills and scheduled jobs',
    'Your Kanban board and enabled toolsets',
  ];

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  StudyController? _study;
  bool _opening = false;

  @override
  void dispose() {
    _study?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_opening) return;
    setState(() => _opening = true);
    unawaited(IrisHaptics.selection());
    final backend = await ref.read(activeChatProvider.future);
    final api = await ref.read(genUiApiProvider.future);
    if (!mounted) return;
    if (backend == null || api == null) {
      setState(() => _opening = false);
      return;
    }
    final study = _study ??= StudyController(backend, api);
    setState(() {});
    await study.start();
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _openChat(String id) async {
    final backend = await ref.read(activeChatProvider.future);
    if (backend == null || !mounted) return;
    await Navigator.of(context).push(
      IrisPageRoute<void>(
        builder: (_) => ChatScreen(
          backend: backend,
          conversationId: id,
          title: StudyController.chatTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gutter = context.window.gutter;
    final theme = context.iris;
    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.sm,
          gutter,
          IrisSpace.sm,
        ),
        child: Row(
          children: [
            IrisCircleButton(
              icon: Icons.arrow_back_ios_new,
              semanticLabel: 'Back',
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.xs, gutter, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.xs),
              child: Text(
                'Study my work',
                style: theme.typography.serif.copyWith(fontSize: 34, height: 1),
              ),
            ),
            const SizedBox(height: 22),
            if (_study case final study?)
              ValueListenableBuilder(
                valueListenable: study,
                builder: (context, state, _) => _Progress(
                  state: state,
                  onOpenChat: state.conversationId == null
                      ? null
                      : () => unawaited(_openChat(state.conversationId!)),
                  onRetry: () {
                    _study?.dispose();
                    setState(() => _study = null);
                  },
                  onReview: widget.onReview,
                ),
              )
            else
              _Intro(busy: _opening, onStart: _start),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.busy, required this.onStart});

  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hermes reads what is already on your server and proposes a short '
          'profile of your work, a few display templates and some reply kits, '
          'so generated displays look like yours.',
          style: type.body.copyWith(color: palette.inkMuted),
        ),
        const SizedBox(height: IrisSpace.lg),
        const IrisLabel('What it reads'),
        const SizedBox(height: IrisSpace.sm),
        for (final line in StudyScreen.reads)
          Padding(
            padding: const EdgeInsets.only(bottom: IrisSpace.xs),
            child: Text('•  $line', style: type.body),
          ),
        const SizedBox(height: IrisSpace.lg),
        Text(
          'It all stays on your server. Nothing is used until you have looked '
          'at it and approved it, and you can drop any of it. A study takes a '
          'few minutes and runs in a chat called “Iris setup”.',
          style: type.body.copyWith(color: palette.inkMuted),
        ),
        const SizedBox(height: IrisSpace.xl),
        IrisButton(
          label: 'Study my work',
          tone: IrisButtonTone.primary,
          expand: true,
          busy: busy,
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.state,
    required this.onOpenChat,
    required this.onRetry,
    required this.onReview,
  });

  final StudyState state;
  final VoidCallback? onOpenChat;
  final VoidCallback onRetry;
  final VoidCallback? onReview;

  /// "a profile and 4 templates (2 reply kits)", or null when nothing has come in yet.
  static String? _summary(StudyState s) {
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final kits = s.proposedKits > 0
        ? ' (${plural(s.proposedKits, 'reply kit')})'
        : '';
    final parts = [
      if (s.profileProposed) 'a profile',
      if (s.proposedTemplates > 0)
        '${plural(s.proposedTemplates, 'template')}$kits',
    ];
    return parts.isEmpty ? null : parts.join(' and ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final summary = _summary(state);

    final (agent, headline, detail) = switch (state.phase) {
      StudyPhase.intro || StudyPhase.starting => (
        AgentState.thinking,
        'Starting',
        'Making the Iris setup chat.',
      ),
      StudyPhase.working => (
        AgentState.working,
        'Hermes is reading your work',
        summary == null
            ? 'Nothing proposed yet. This can take several minutes.'
            : 'So far: $summary. This can take several minutes.',
      ),
      StudyPhase.done when state.found => (
        AgentState.idle,
        'Hermes has proposals for you',
        'It proposed $summary. Nothing is used until you approve it.',
      ),
      StudyPhase.done => (
        AgentState.idle,
        'Hermes did not propose anything',
        'Open the chat to see what it found and why.',
      ),
      StudyPhase.failed => (
        AgentState.failed,
        'The study did not finish',
        state.message ?? 'Something went wrong.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          label: '$headline. $detail',
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IrisOrb(state: agent),
                const SizedBox(width: IrisSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline, style: type.title),
                      const SizedBox(height: IrisSpace.xs),
                      Text(
                        detail,
                        style: type.body.copyWith(color: palette.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: IrisSpace.xl),
        if (state.phase == StudyPhase.done && state.found && onReview != null)
          Padding(
            padding: const EdgeInsets.only(bottom: IrisSpace.sm),
            child: IrisButton(
              label: 'Review what it found',
              tone: IrisButtonTone.primary,
              expand: true,
              onPressed: onReview,
            ),
          ),
        if (onOpenChat != null)
          IrisButton(
            label: state.phase == StudyPhase.working
                ? 'Watch in the chat'
                : 'Open the chat',
            expand: true,
            onPressed: onOpenChat,
          ),
        if (state.phase == StudyPhase.failed) ...[
          const SizedBox(height: IrisSpace.sm),
          IrisButton(label: 'Try again', expand: true, onPressed: onRetry),
        ],
      ],
    );
  }
}
