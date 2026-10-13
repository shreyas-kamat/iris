/// Home: the active profile's conversations, newest first.
///
/// The header carries the link state, the same answer the Phase 1 status
/// screen gives, and opens that screen for the detail. With more than one
/// agent profile it also picks which profile the list shows.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../data/rpc/dashboard_session.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../home/link_status_screen.dart';
import 'chat_screen.dart';
import 'relative_time.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState
    extends ConsumerState<ConversationListScreen> {
  /// Pages loaded after the first, which the provider holds.
  final List<ConversationSummary> _more = [];
  bool _loadingMore = false;

  Future<void> _open(
    ChatBackend chat, {
    ConversationSummary? conversation,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          backend: chat,
          conversationId: conversation?.id,
          title: conversation?.title,
        ),
      ),
    );
    if (!mounted) return;
    // A send may have created a conversation or retitled one.
    ref.invalidate(conversationsProvider);
  }

  Future<void> _loadMore(ChatBackend chat, int offset) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final page = await chat.conversations(offset);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (page case Ok(:final value)) _more.addAll(value.items);
    });
  }

  Future<void> _pickProfile(List<AgentProfile> profiles, String current) async {
    final picked = await showIrisSheet<String>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Profile',
        subtitle: 'Each profile has its own conversations, memory and model.',
        child: Column(
          children: [
            for (final profile in profiles)
              IrisListRow(
                title: profile.name,
                subtitle: profile.model,
                selected: profile.name == current,
                onTap: () => Navigator.of(sheetContext).pop(profile.name),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(activeProfileProvider.notifier).select(picked);
  }

  @override
  Widget build(BuildContext context) {
    // A refreshed first page starts the list over.
    ref.listen(conversationsProvider, (_, _) => _more.clear());
    final server = ref.watch(activeServerProvider);
    final link =
        ref.watch(activeLinkProvider).value ??
        const LinkState(LinkPhase.connecting);
    final chat = ref.watch(activeChatProvider).value;
    final conversations = ref.watch(conversationsProvider);
    final profiles =
        ref.watch(profilesProvider).value ?? const <AgentProfile>[];
    final profile = ref.watch(activeProfileProvider);
    final (state, headline, _) = describeLink(link);
    final theme = context.iris;
    final gutter = context.window.gutter;

    return IrisScaffold(
      header: Row(
        children: [
          Expanded(
            child: IrisPressable(
              onTap: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LinkStatusScreen(),
                  ),
                ),
              ),
              semanticLabel: 'Connection: $headline',
              ensureTapTarget: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  IrisSpace.md,
                  IrisSpace.sm,
                  IrisSpace.md,
                ),
                child: Row(
                  children: [
                    IrisOrb(state: state),
                    const SizedBox(width: IrisSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            server?.label ?? 'Iris',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.title,
                          ),
                          Text(
                            headline,
                            style: theme.typography.caption.copyWith(
                              color: theme.palette.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (profiles.length > 1)
            Padding(
              padding: EdgeInsets.only(right: gutter),
              child: IrisChip(
                profile,
                onTap: () => unawaited(_pickProfile(profiles, profile)),
              ),
            ),
        ],
      ),
      body: _ConversationList(
        conversations: conversations,
        more: _more,
        loadingMore: _loadingMore,
        onOpen: chat == null
            ? null
            : (conversation) =>
                  unawaited(_open(chat, conversation: conversation)),
        onMore: chat == null
            ? null
            : (offset) => unawaited(_loadMore(chat, offset)),
        onRetry: () => ref.invalidate(conversationsProvider),
      ),
      footer: Padding(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.md),
        child: IrisButton(
          label: 'New conversation',
          tone: IrisButtonTone.primary,
          expand: true,
          onPressed: chat == null || link.phase != LinkPhase.live
              ? null
              : () => unawaited(_open(chat)),
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.conversations,
    required this.more,
    required this.loadingMore,
    required this.onOpen,
    required this.onMore,
    required this.onRetry,
  });

  final AsyncValue<ConversationPage?> conversations;
  final List<ConversationSummary> more;
  final bool loadingMore;
  final ValueChanged<ConversationSummary>? onOpen;

  /// Loads the next page from an offset; null when none can load.
  final ValueChanged<int>? onMore;
  final VoidCallback onRetry;

  static String? _subtitle(ConversationSummary conversation, DateTime now) {
    final parts = [
      if (conversation.startedAt case final at?) relativeTime(at, now),
      ?(conversation.source == 'desktop' ? null : conversation.source),
      if (conversation.messageCount > 0)
        '${conversation.messageCount} messages',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final gutter = context.window.gutter;
    final page = conversations.value;
    if (page == null) {
      if (conversations.error case final error?) {
        return IrisEmptyState(
          title: 'Could not load conversations',
          message: error is IrisFailure
              ? error.message ?? error.kind.name
              : '$error',
          action: IrisButton(label: 'Try again', onPressed: onRetry),
        );
      }
      // Loading, or waiting for the link: placeholders where rows will be.
      return ListView(
        padding: EdgeInsets.symmetric(
          horizontal: gutter,
          vertical: IrisSpace.md,
        ),
        children: [
          for (var i = 0; i < 6; i++) ...[
            const IrisSkeleton(width: 220, height: 16),
            const SizedBox(height: IrisSpace.xs),
            const IrisSkeleton(width: 120, height: 12),
            const SizedBox(height: IrisSpace.lg),
          ],
        ],
      );
    }
    final list = [...page.items, ...more];
    if (list.isEmpty) {
      return const IrisEmptyState(
        title: 'No conversations yet',
        message:
            'Start one below. It will show here and in every other '
            'client of this agent.',
      );
    }
    final hasMore = list.length < page.total;
    final now = DateTime.now();
    final open = onOpen;
    final next = onMore;
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: gutter - IrisSpace.md,
        vertical: IrisSpace.sm,
      ),
      itemCount: list.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == list.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: IrisSpace.md),
            child: Center(
              child: IrisButton(
                label: 'Show more',
                tone: IrisButtonTone.ghost,
                busy: loadingMore,
                onPressed: next == null ? null : () => next(list.length),
              ),
            ),
          );
        }
        final conversation = list[index];
        return IrisListRow(
          key: ValueKey(conversation.id),
          title: conversation.title,
          subtitle: _subtitle(conversation, now),
          onTap: open == null ? null : () => open(conversation),
        );
      },
    );
  }
}
