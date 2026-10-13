/// Home: the active server's conversations, newest first.
///
/// The header carries the link state, the same answer the Phase 1 status
/// screen gives, and opens that screen for the detail.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../data/rpc/dashboard_session.dart';
import '../../design/components/aperture.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../home/link_status_screen.dart';
import 'chat_screen.dart';
import 'relative_time.dart';

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
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
    // A send may have created a conversation or retitled one.
    ref.invalidate(conversationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    final link =
        ref.watch(activeLinkProvider).value ??
        const LinkState(LinkPhase.connecting);
    final chat = ref.watch(activeChatProvider).value;
    final conversations = ref.watch(conversationsProvider);
    final (state, headline, _) = describeLink(link);
    final theme = context.iris;
    final gutter = context.window.gutter;

    return IrisScaffold(
      header: IrisPressable(
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LinkStatusScreen()),
          ),
        ),
        semanticLabel: 'Connection: $headline',
        ensureTapTarget: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: IrisSpace.md,
          ),
          child: Row(
            children: [
              Aperture(state: state),
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
      body: _ConversationList(
        conversations: conversations,
        onOpen: chat == null
            ? null
            : (conversation) => unawaited(
                _open(context, ref, chat, conversation: conversation),
              ),
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
              : () => unawaited(_open(context, ref, chat)),
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.conversations,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<ConversationPage?> conversations;
  final ValueChanged<ConversationSummary>? onOpen;
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
    final list = conversations.value?.items;
    if (list == null) {
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
    if (list.isEmpty) {
      return const IrisEmptyState(
        title: 'No conversations yet',
        message: 'Start one below. It will show here and in every other '
            'client of this agent.',
      );
    }
    final now = DateTime.now();
    final open = onOpen;
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: gutter - IrisSpace.md,
        vertical: IrisSpace.sm,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
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
