/// Home: the active profile's conversations, newest first.
///
/// The top bar picks the profile and opens settings. The hero carries the
/// agent's state in the iris orb, with a line for the gateway that opens the
/// link detail. Below it, the conversations; over them, a floating bar that
/// starts a new one.
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
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../home/link_status_screen.dart';
import '../settings/settings_screen.dart';
import 'chat_screen.dart';
import 'profile_picker.dart';
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
      IrisPageRoute<void>(
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
    final (linkState, headline, _) = describeLink(link);
    final live = link.phase == LinkPhase.live;
    final gutter = context.window.gutter;

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
            _ProfilePill(
              name: profile,
              // The pill only opens something when there is a choice to make.
              onTap: profiles.length > 1
                  ? () => unawaited(showProfilePicker(context, ref))
                  : null,
            ),
            const Spacer(),
            IrisCircleButton(
              icon: Icons.tune,
              semanticLabel: 'Settings',
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  IrisPageRoute<void>(builder: (_) => const SettingsScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _Hero(
                // The orb shows the agent as idle while the link is up. Only a
                // broken link changes it, so a healthy home does not look busy.
                orbState: live ? AgentState.idle : linkState,
                linkState: linkState,
                headline: headline,
                host: server == null ? '' : _hostOf(server.baseUrl),
                total: conversations.value?.total,
                onGateway: () => unawaited(
                  Navigator.of(context).push(
                    IrisPageRoute<void>(
                      builder: (_) => const LinkStatusScreen(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _ConversationList(
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
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NewChatBar(
              enabled: chat != null && live,
              onTap: chat == null || !live
                  ? null
                  : () => unawaited(_open(chat)),
            ),
          ),
        ],
      ),
    );
  }

  /// The host part of the server's address, for the gateway line. A full URL
  /// is too long for a line of mono text; the host is what identifies it.
  static String _hostOf(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host.isEmpty ? baseUrl : host;
  }
}

/// The active profile, as a pill. With more than one profile it shows a
/// chevron and opens the picker; with one, it is a label.
class _ProfilePill extends StatelessWidget {
  const _ProfilePill({required this.name, this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.all(IrisRadius.full),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: IrisSize.avatar,
            height: IrisSize.avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accentQuiet,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: type.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(width: IrisSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile',
                style: type.caption.copyWith(
                  fontSize: 10,
                  height: 1.1,
                  color: palette.inkMuted,
                ),
              ),
              Text(
                name,
                style: type.body.copyWith(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          if (onTap != null) ...[
            const SizedBox(width: IrisSpace.sm),
            Icon(Icons.keyboard_arrow_down, size: 14, color: palette.inkMuted),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Profile: $name',
      ensureTapTarget: false,
      child: pill,
    );
  }
}

/// The greeting, the orb and the gateway line.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.orbState,
    required this.linkState,
    required this.headline,
    required this.host,
    required this.total,
    required this.onGateway,
  });

  /// The state the orb shows. Can differ from [linkState] while the link is up.
  final AgentState orbState;

  /// The link's own state, for the gateway dot.
  final AgentState linkState;
  final String headline;
  final String host;

  /// Conversations in all, when the first page has loaded.
  final int? total;
  final VoidCallback onGateway;

  /// The design's time-of-day greeting. Read on each build, which is what the
  /// screen needs: it is rebuilt on every link change, and that is often enough.
  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning.';
    if (now.hour < 17) return 'Good afternoon.';
    return 'Good evening.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    final stateColor = palette.colorFor(orbState);
    final gatewayStyle = type.codeSmall.copyWith(
      fontSize: 11,
      color: palette.inkFaint,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, IrisSpace.lg, gutter, IrisSpace.xl),
      child: Row(
        children: [
          IrisOrb(state: orbState, size: 84),
          const SizedBox(width: IrisSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_greeting(DateTime.now()), style: type.serif),
                const SizedBox(height: IrisSpace.xs),
                Text.rich(
                  TextSpan(
                    style: type.caption.copyWith(
                      fontSize: 13.5,
                      height: 1.35,
                      color: palette.inkMuted,
                    ),
                    children: [
                      const TextSpan(text: 'Iris is '),
                      TextSpan(
                        text: orbState.label.toLowerCase(),
                        style: TextStyle(color: stateColor),
                      ),
                      if (total != null)
                        TextSpan(text: ' · $total conversations'),
                    ],
                  ),
                ),
                const SizedBox(height: IrisSpace.xs),
                IrisPressable(
                  onTap: onGateway,
                  semanticLabel: 'Connection: $headline',
                  ensureTapTarget: false,
                  // The label above already says the connection state, so the
                  // text under it is excluded rather than read a second time.
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: palette.colorFor(linkState),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: IrisSpace.xs + 2),
                        Flexible(
                          child: Text(
                            host.isEmpty ? headline : '$host · $headline',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: gatewayStyle,
                          ),
                        ),
                      ],
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

/// The floating bar that starts a new conversation.
///
/// It sits over the bottom of the list on a fade from the canvas, so rows scroll
/// under it rather than being cut off by it. The bottom padding on the list is
/// what keeps the last row clear of the bar.
class _NewChatBar extends StatelessWidget {
  const _NewChatBar({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final window = context.window;
    final gutter = window.gutter;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            palette.canvas,
            palette.canvas,
            palette.canvas.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.xl,
          gutter,
          IrisSpace.lg + window.safeArea.bottom,
        ),
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: Container(
            padding: const EdgeInsets.all(IrisSpace.xs + 2),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: palette.line,
                width: IrisStroke.hairline,
              ),
              boxShadow: IrisDepth.of(IrisPlane.overlay, palette).shadows,
            ),
            child: IrisPressable(
              onTap: enabled ? onTap : null,
              semanticLabel: 'New conversation',
              ensureTapTarget: false,
              // The visible prompt is the same words as the label, so it is
              // excluded from semantics to keep the button reading once.
              child: ExcludeSemantics(
                child: SizedBox(
                  height: IrisSize.control,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IrisSpace.md,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 18, color: palette.accent),
                        const SizedBox(width: IrisSpace.sm + 2),
                        Text(
                          'Ask Iris anything…',
                          style: type.body.copyWith(
                            fontSize: 15,
                            color: palette.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
    // Index 0 is the section label. The bottom padding is the height of the
    // floating bar plus its fade, so the last row can be scrolled clear of it.
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: _barClearance),
      itemCount: list.length + 1 + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              IrisSpace.sm,
              gutter,
              IrisSpace.sm,
            ),
            child: IrisLabel('Recent', color: context.palette.inkFaint),
          );
        }
        final rowIndex = index - 1;
        if (rowIndex == list.length) {
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
        final conversation = list[rowIndex];
        return Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.xs),
          child: _ConversationRow(
            key: ValueKey(conversation.id),
            title: conversation.title,
            subtitle: _subtitle(conversation, now),
            onTap: open == null ? null : () => open(conversation),
          ),
        );
      },
    );
  }

  /// Floating bar height plus the fade above it, so the last row clears it.
  static const double _barClearance = 130;
}

/// One conversation: a tile holding the resting orb, the title and its
/// metadata. Rows carry no fill at rest, so the list reads as text on the page.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      ensureTapTarget: false,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: const BorderRadius.all(IrisRadius.md),
              ),
              child: const IrisOrb(
                state: AgentState.rest,
                size: 30,
                glow: false,
              ),
            ),
            const SizedBox(width: IrisSpace.md),
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
                      height: 1.25,
                      color: palette.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: IrisSpace.xs - 1),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.codeSmall.copyWith(
                        fontSize: 11,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: IrisSpace.sm),
            Icon(Icons.chevron_right, size: 16, color: palette.lineStrong),
          ],
        ),
      ),
    );
  }
}
