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
import '../../app/usage.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../data/rpc/dashboard_session.dart';
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
import '../home/link_status_screen.dart';
import '../home/usage_strip.dart';
import '../settings/settings_screen.dart';
import 'archived_screen.dart';
import 'chat_controller.dart';
import 'chat_screen.dart';
import 'conversation_actions.dart';
import 'conversation_row.dart';
import 'conversation_search.dart';
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

  /// Titles changed here, shown before the server's list catches up.
  final Map<String, String> _titles = {};

  /// Rows archived here, folded out of the list.
  final Set<String> _gone = {};

  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// Starts scrolled just past the search field, so it waits above the first
  /// row and a pull reveals it. A list too short to scroll simply shows it.
  final _scroll = ScrollController(initialScrollOffset: searchFieldExtent);

  /// The query the server is asked, settled 250 ms after the last keystroke.
  String _serverQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQuery);
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) unawaited(IrisHaptics.selection());
    });
  }

  void _onQuery() {
    _debounce?.cancel();
    final query = _search.text.trim();
    setState(() {
      if (query.isEmpty) _serverQuery = '';
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _serverQuery = query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

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
    ref
      ..invalidate(conversationsProvider)
      ..invalidate(usageOptionsProvider);
  }

  Future<void> _actions(
    ChatBackend chat,
    ConversationSummary conversation,
  ) async {
    final title = _titles[conversation.id] ?? conversation.title;
    final action = await showConversationActions(context, title);
    if (!mounted) return;
    switch (action) {
      case ConversationAction.rename:
        final next = await showRenameSheet(context, title);
        if (next == null || !mounted) return;
        unawaited(IrisHaptics.commit());
        setState(() => _titles[conversation.id] = next);
        final result = await chat.rename(conversation.id, next);
        if (!mounted) return;
        if (result case Err(:final failure)) {
          setState(() => _titles[conversation.id] = title);
          showIrisToast(
            context,
            message: 'Could not rename: ${ChatController.describe(failure)}',
          );
        }
      case ConversationAction.archive:
        await _archive(chat, conversation.id);
      case null:
        break;
    }
  }

  Future<void> _archive(ChatBackend chat, String id) async {
    unawaited(IrisHaptics.commit());
    setState(() => _gone.add(id));
    final result = await chat.setArchived(id, archived: true);
    if (!mounted) return;
    switch (result) {
      case Ok():
        showIrisToast(
          context,
          message: 'Archived',
          actionLabel: 'Undo',
          onAction: () => unawaited(_undoArchive(chat, id)),
        );
      case Err(:final failure):
        setState(() => _gone.remove(id));
        showIrisToast(
          context,
          message: 'Could not archive: ${ChatController.describe(failure)}',
        );
    }
  }

  Future<void> _undoArchive(ChatBackend chat, String id) async {
    setState(() => _gone.remove(id));
    final result = await chat.setArchived(id, archived: false);
    if (!mounted) return;
    if (result case Err(:final failure)) {
      setState(() => _gone.add(id));
      showIrisToast(
        context,
        message: 'Could not undo: ${ChatController.describe(failure)}',
      );
    }
  }

  Future<void> _openArchived(ChatBackend chat) async {
    await Navigator.of(
      context,
    ).push(IrisPageRoute<void>(builder: (_) => ArchivedScreen(backend: chat)));
    if (mounted) ref.invalidate(conversationsProvider);
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
    ref.listen(conversationsProvider, (_, _) {
      _more.clear();
      _titles.clear();
      _gone.clear();
    });
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
    final now = ref.read(clockProvider)();
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
                now: now,
                onGateway: () => unawaited(
                  Navigator.of(context).push(
                    IrisPageRoute<void>(
                      builder: (_) => const LinkStatusScreen(),
                    ),
                  ),
                ),
              ),
              const UsageStrip(),
              Expanded(
                child: _ConversationList(
                  conversations: conversations,
                  more: _more,
                  loadingMore: _loadingMore,
                  scroll: _scroll,
                  search: _search,
                  searchFocus: _searchFocus,
                  serverHits: _serverQuery.isEmpty
                      ? null
                      : ref.watch(conversationSearchProvider(_serverQuery)),
                  titles: _titles,
                  gone: _gone,
                  onActions: chat == null
                      ? null
                      : (conversation) =>
                            unawaited(_actions(chat, conversation)),
                  onArchived: chat == null
                      ? null
                      : () => unawaited(_openArchived(chat)),
                  onOpen: chat == null
                      ? null
                      : (conversation) =>
                            unawaited(_open(chat, conversation: conversation)),
                  onMore: chat == null
                      ? null
                      : (offset) => unawaited(_loadMore(chat, offset)),
                  onRetry: () => ref.invalidate(conversationsProvider),
                  onRefresh: () async {
                    ref
                      ..invalidate(conversationsProvider)
                      ..invalidate(usageOptionsProvider);
                    await ref.read(conversationsProvider.future);
                  },
                  now: now,
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
    required this.now,
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

  /// The moment the screen is drawn at, for the greeting.
  final DateTime now;

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
                Text(_greeting(now), style: type.serif),
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
              // The overlay shadow drops 16pt and the bar sits only that far
              // above the screen edge, so on a light ground its core is cut
              // off into a hard grey band. Light uses the shallow raised
              // shadow; dark keeps the design's deep one, which reads as
              // depth there rather than as a smudge.
              boxShadow: IrisDepth.of(
                palette.isDark ? IrisPlane.overlay : IrisPlane.raised,
                palette,
              ).shadows,
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
    required this.now,
    required this.conversations,
    required this.more,
    required this.loadingMore,
    required this.onOpen,
    required this.scroll,
    required this.search,
    required this.searchFocus,
    required this.serverHits,
    required this.titles,
    required this.gone,
    required this.onActions,
    required this.onArchived,
    required this.onMore,
    required this.onRetry,
    required this.onRefresh,
  });

  final Future<void> Function() onRefresh;
  final AsyncValue<ConversationPage?> conversations;
  final List<ConversationSummary> more;
  final bool loadingMore;
  final ValueChanged<ConversationSummary>? onOpen;
  final ScrollController scroll;
  final TextEditingController search;
  final FocusNode searchFocus;

  /// The server's answer to the settled query; null when none is active.
  final AsyncValue<List<SearchHit>>? serverHits;
  final Map<String, String> titles;
  final Set<String> gone;
  final ValueChanged<ConversationSummary>? onActions;
  final VoidCallback? onArchived;

  /// Loads the next page from an offset; null when none can load.
  final ValueChanged<int>? onMore;
  final VoidCallback onRetry;

  /// The moment the list is drawn at, for relative times.
  final DateTime now;

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
    final now = this.now;
    final open = onOpen;
    final next = onMore;
    final query = search.text.trim();
    final searching = query.isNotEmpty;

    /// Snaps a half-revealed field to open or closed, so it is never left
    /// cut in half.
    bool snap(ScrollEndNotification _) {
      final offset = scroll.hasClients ? scroll.offset : 0.0;
      if (searching || searchFocus.hasFocus) return false;
      if (offset <= 0 || offset >= searchFieldExtent) return false;
      final target = offset < searchFieldExtent / 2 ? 0.0 : searchFieldExtent;
      // After the current frame: a scroll cannot start inside its own end
      // notification.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scroll.hasClients) return;
        if (context.reduceMotion) {
          scroll.jumpTo(target);
        } else {
          unawaited(
            scroll.animateTo(
              target,
              duration: IrisDurations.normal,
              curve: IrisCurves.standard,
            ),
          );
        }
      });
      return false;
    }

    final children = <Widget>[
      Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: SearchField(
          controller: search,
          focusNode: searchFocus,
          searching: serverHits?.isLoading ?? false,
        ),
      ),
      if (searching)
        ..._searchItems(context, gutter, list, open)
      else ...[
        Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            IrisSpace.sm,
            gutter,
            IrisSpace.sm,
          ),
          child: IrisLabel('Recent', color: context.palette.inkFaint),
        ),
        for (final conversation in list)
          Leaving(
            key: ValueKey(conversation.id),
            gone: gone.contains(conversation.id),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.xs),
              child: ConversationRow(
                title: titles[conversation.id] ?? conversation.title,
                subtitle: _subtitle(conversation, now),
                onTap: open == null ? null : () => open(conversation),
                onLongPress: onActions == null
                    ? null
                    : () => onActions!(conversation),
              ),
            ),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IrisSpace.md),
            child: Center(
              child: IrisButton(
                label: 'Show more',
                tone: IrisButtonTone.ghost,
                busy: loadingMore,
                onPressed: next == null ? null : () => next(list.length),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, 0),
          child: IrisListRow(
            title: 'Archived',
            leading: Icon(
              Icons.archive_outlined,
              size: IrisSize.icon,
              color: context.palette.inkMuted,
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 16,
              color: context.palette.lineStrong,
            ),
            onTap: onArchived,
          ),
        ),
      ],
    ];
    // The bottom padding is the height of the floating bar plus its fade, so
    // the last row can be scrolled clear of it.
    /// A list too short to scroll the whole field away keeps it fully
    /// visible: parked half-hidden at its small maximum extent, it would
    /// look cut off.
    bool keepVisible(ScrollMetricsNotification notification) {
      final metrics = notification.metrics;
      if (searching ||
          metrics.maxScrollExtent >= searchFieldExtent ||
          metrics.pixels <= 0) {
        return false;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients && scroll.offset > 0) scroll.jumpTo(0);
      });
      return false;
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: keepVisible,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: snap,
        child: RefreshIndicator(
          color: context.palette.accent,
          backgroundColor: context.palette.surfaceRaised,
          onRefresh: onRefresh,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: _barClearance),
            children: children,
          ),
        ),
      ),
    );
  }

  /// What shows under the field while a query is typed: the server's hits
  /// once they arrive, the loaded rows that match until then, and what went
  /// wrong if the server could not be asked.
  List<Widget> _searchItems(
    BuildContext context,
    double gutter,
    List<ConversationSummary> list,
    ValueChanged<ConversationSummary>? open,
  ) {
    final palette = context.palette;
    final type = context.type;
    final hits = serverHits?.value;
    final failed = serverHits?.hasError ?? false;
    final local = localMatches(list, search.text);
    final rows = hits == null
        ? <Widget>[
            for (final conversation in local)
              Padding(
                key: ValueKey('local-${conversation.id}'),
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.xs),
                child: ConversationRow(
                  title: titles[conversation.id] ?? conversation.title,
                  subtitle: _subtitle(conversation, now),
                  onTap: open == null ? null : () => open(conversation),
                ),
              ),
          ]
        : <Widget>[
            for (final hit in hits.where((hit) => !hit.archived))
              Padding(
                key: ValueKey('hit-${hit.storedId}'),
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.xs),
                child: SearchHitRow(
                  hit: hit,
                  onTap: open == null
                      ? null
                      : () => open(
                          ConversationSummary(
                            id: hit.storedId,
                            title: hit.title,
                          ),
                        ),
                ),
              ),
          ];
    final settled = hits != null || failed;
    return [
      if (failed)
        Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            IrisSpace.xs,
            gutter,
            IrisSpace.sm,
          ),
          child: Text(
            "Couldn't search the server",
            style: type.caption.copyWith(color: palette.inkMuted),
          ),
        ),
      // The local matches give way to the server's hits with a cross-fade
      // rather than a swap.
      AnimatedSwitcher(
        duration: context.reduceMotion ? Duration.zero : IrisDurations.normal,
        switchInCurve: IrisCurves.standard,
        child: Column(
          key: ValueKey(hits != null),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
      if (rows.isEmpty && (settled || local.isEmpty))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: IrisSpace.xl),
          child: Center(
            child: Text(
              'No matches',
              style: type.caption.copyWith(color: palette.inkMuted),
            ),
          ),
        ),
    ];
  }

  /// Floating bar height plus the fade above it, so the last row clears it.
  static const double _barClearance = 130;
}
