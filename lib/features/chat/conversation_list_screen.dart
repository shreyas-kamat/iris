/// Home: the active profile's conversations, newest first.
///
/// The top bar picks the profile and opens settings. The hero carries the
/// agent's state in the iris orb, with a line for the gateway that opens the
/// link detail. Below it, the usage strip, the search field and the
/// conversations, all in one scroll; as the hero scrolls away, the link folds
/// into the bar. Over everything, a floating bar that starts a new
/// conversation.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/device_state.dart';
import '../../app/providers.dart';
import '../../app/usage.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../data/rpc/dashboard_session.dart';
import '../../demo/demo_content.dart';
import '../../demo/demo_mode.dart';
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
import 'delete_sheet.dart';
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
  final _scroll = ScrollController();

  /// How far the hero has scrolled under the bar: 0 in full view, 1 gone.
  final _collapse = ValueNotifier<double>(0);
  final _heroKey = GlobalKey();

  /// The hero's height when last laid out. Kept, because the list drops the
  /// hero once it is scrolled far enough away.
  double _heroHeight = 140;

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
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final hero = _heroKey.currentContext?.findRenderObject();
    if (hero is RenderBox && hero.hasSize && hero.size.height > 0) {
      _heroHeight = hero.size.height;
    }
    _collapse.value = (_scroll.offset / _heroHeight).clamp(0.0, 1.0);
  }

  /// Settles a half-collapsed hero to open or closed, so the bar is never
  /// left between its two forms.
  bool _snap(ScrollEndNotification notification) {
    // Only the list itself: text fields hold scrollables of their own.
    if (notification.depth != 0 || _searchFocus.hasFocus) return false;
    final metrics = notification.metrics;
    final offset = metrics.pixels;
    if (offset <= 0 || offset >= _heroHeight) return false;
    final target = offset < _heroHeight / 2
        ? 0.0
        : math.min(_heroHeight, metrics.maxScrollExtent);
    if (target == offset) return false;
    // After the current frame: a scroll cannot start inside its own end
    // notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (context.reduceMotion) {
        _scroll.jumpTo(target);
      } else {
        unawaited(
          _scroll.animateTo(
            target,
            duration: IrisDurations.normal,
            curve: IrisCurves.standard,
          ),
        );
      }
    });
    return false;
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
    _collapse.dispose();
    super.dispose();
  }

  bool _loadingMore = false;

  /// The conversation whose menu is open, drawn lifted.
  String? _lifted;

  final Map<String, ConversationSummary> _fetchedPins = {};
  final Set<String> _fetching = {};

  /// Pins whose chat is not in the loaded pages are read one by one, so a
  /// pin on an older chat still shows. A chat that no longer exists drops
  /// its pin.
  Future<void> _fetchMissingPins(
    ChatBackend chat,
    List<String> pins,
    Set<String> loaded,
  ) async {
    for (final id in pins) {
      if (loaded.contains(id) ||
          _fetchedPins.containsKey(id) ||
          !_fetching.add(id)) {
        continue;
      }
      switch (await chat.conversation(id)) {
        case Ok(:final value):
          if (mounted) setState(() => _fetchedPins[id] = value);
        case Err(:final failure) when failure.kind == FailureKind.notFound:
          if (mounted) ref.read(pinsProvider.notifier).unpin(id);
        case Err():
          break;
      }
    }
  }

  Future<void> _open(
    ChatBackend chat, {
    ConversationSummary? conversation,
  }) async {
    await Navigator.of(context).push(
      IrisPageRoute<void>(
        builder: (_) => ChatScreen(
          suggestions: ref.read(demoModeProvider)
              ? [for (final script in demoScripts) script.prompt]
              : null,
          backend: chat,
          conversationId: conversation?.id,
          title: conversation?.title,
        ),
      ),
    );
    if (!mounted) return;
    // A send may have created a conversation or retitled one. A frame later:
    // the home screen is revealed in the next build, and invalidating just
    // before it makes the usage rows rebuild mid-build, which Riverpod asserts
    // against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
        ..invalidate(conversationsProvider)
        ..invalidate(usageOptionsProvider);
    });
  }

  Future<void> _actions(
    ChatBackend chat,
    ConversationSummary conversation,
  ) async {
    final title = _titles[conversation.id] ?? conversation.title;
    setState(() => _lifted = conversation.id);
    final action = await showConversationActions(
      context,
      title,
      pinned: ref.read(pinsProvider).contains(conversation.id),
    );
    if (mounted) setState(() => _lifted = null);
    if (!mounted) return;
    switch (action) {
      case ConversationAction.pin:
        unawaited(IrisHaptics.commit());
        ref.read(pinsProvider.notifier).toggle(conversation.id);
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
      case ConversationAction.delete:
        await _delete(chat, conversation, title);
      case null:
        break;
    }
  }

  Future<void> _delete(
    ChatBackend chat,
    ConversationSummary conversation,
    String title,
  ) async {
    if (!await showDeleteSheet(context, title) || !mounted) return;
    unawaited(IrisHaptics.commit());
    setState(() => _gone.add(conversation.id));
    final result = await chat.delete(conversation.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.read(pinsProvider.notifier).unpin(conversation.id);
        ref.read(branchRecordsProvider).forget(conversation.id);
        showIrisToast(context, message: 'Deleted ‘$title’');
      case Err(:final failure):
        setState(() => _gone.remove(conversation.id));
        showIrisToast(
          context,
          message: refusedAsLive(failure)
              ? 'Stop the reply before deleting this chat.'
              : 'Could not delete: ${ChatController.describe(failure)}',
          actionLabel: refusedAsLive(failure) ? 'Open' : null,
          onAction: refusedAsLive(failure)
              ? () => unawaited(_open(chat, conversation: conversation))
              : null,
        );
    }
  }

  Future<void> _archive(ChatBackend chat, String id) async {
    unawaited(IrisHaptics.commit());
    // An archived chat is not pinned: it is out of home.
    ref.read(pinsProvider.notifier).unpin(id);
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
      return;
    }
    // A refresh since the archive dropped the row from the list, so there is
    // nothing on screen to bring back: ask the server again.
    final listed = [
      ...?ref.read(conversationsProvider).value?.items,
      ..._more,
    ].any((row) => row.id == id);
    if (!listed) ref.invalidate(conversationsProvider);
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
      if (page case Ok(:final value)) {
        // The pages can overlap when the list changed between them.
        final have = {for (final row in _more) row.id};
        _more.addAll(value.items.where((row) => !have.contains(row.id)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A refreshed first page starts the list over.
    ref.listen(conversationsProvider, (_, next) {
      // While it loads, the old rows are still on screen: keep what was
      // archived or renamed so they do not flicker back.
      if (next.isLoading) return;
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
    final pinnedIds = ref.watch(pinsProvider);
    final replying =
        ref.watch(liveChatsProvider).value ?? const <String, LiveStatus>{};
    final profiles =
        ref.watch(profilesProvider).value ?? const <AgentProfile>[];
    final profile = ref.watch(activeProfileProvider);
    final (linkState, headline, _) = describeLink(link);
    final headlineText = replying.isEmpty
        ? headline
        : '$headline · ${replying.length} replying';
    final live = link.phase == LinkPhase.live;
    final now = ref.read(clockProvider)();
    // The orb shows the agent as idle while the link is up. Only a broken
    // link changes it, so a healthy home does not look busy.
    final orbState = live ? AgentState.idle : linkState;
    void openGateway() => unawaited(
      Navigator.of(
        context,
      ).push(IrisPageRoute<void>(builder: (_) => const LinkStatusScreen())),
    );

    if (chat != null && conversations.value != null && pinnedIds.isNotEmpty) {
      final loaded = {
        for (final c in [...conversations.value!.items, ..._more]) c.id,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_fetchMissingPins(chat, pinnedIds, loaded));
      });
    }

    return IrisScaffold(
      header: _HomeBar(
        demo: ref.watch(demoModeProvider),
        collapse: _collapse,
        profile: profile,
        // The pill only opens something when there is a choice to make.
        onProfile: profiles.length > 1
            ? () => unawaited(showProfilePicker(context, ref))
            : null,
        onSettings: () => unawaited(
          Navigator.of(
            context,
          ).push(IrisPageRoute<void>(builder: (_) => const SettingsScreen())),
        ),
        linkState: linkState,
        headline: headline,
        onGateway: openGateway,
      ),
      body: Stack(
        children: [
          NotificationListener<ScrollEndNotification>(
            onNotification: _snap,
            child: _ConversationList(
              pins: pinnedIds,
              live: replying,
              lifted: _lifted,
              fetchedPins: _fetchedPins,
              top: [
                // Fades as it scrolls under the bar, where the compact link
                // takes over.
                ValueListenableBuilder<double>(
                  valueListenable: _collapse,
                  builder: (context, t, child) => Opacity(
                    opacity: (1 - t * 1.4).clamp(0.0, 1.0),
                    child: child,
                  ),
                  child: KeyedSubtree(
                    key: _heroKey,
                    child: _Hero(
                      orbState: orbState,
                      linkState: linkState,
                      headline: headlineText,
                      host: server == null ? '' : _hostOf(server.baseUrl),
                      total: conversations.value == null
                          ? null
                          : conversations.value!.total - _gone.length,
                      now: now,
                      onGateway: openGateway,
                    ),
                  ),
                ),
                const UsageStrip(),
              ],
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
                  : (conversation) => unawaited(_actions(chat, conversation)),
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

/// The bar pinned above the list. The profile and settings are always there;
/// once the hero has scrolled under it, the link joins them, so the
/// connection stays in view.
class _HomeBar extends StatelessWidget {
  const _HomeBar({
    required this.demo,
    required this.collapse,
    required this.profile,
    required this.onProfile,
    required this.onSettings,
    required this.linkState,
    required this.headline,
    required this.onGateway,
  });

  /// 0 with the hero in full view, 1 once it is under the bar.
  final ValueListenable<double> collapse;
  final String profile;
  final VoidCallback? onProfile;
  final VoidCallback onSettings;
  final AgentState linkState;
  final String headline;
  final VoidCallback onGateway;

  /// Whether this is the demo, which is marked beside the profile.
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gutter = context.window.gutter;
    final pill = _ProfilePill(name: profile, onTap: onProfile);
    final settings = IrisCircleButton(
      icon: Icons.tune,
      semanticLabel: 'Settings',
      onPressed: onSettings,
    );
    return ValueListenableBuilder<double>(
      valueListenable: collapse,
      builder: (context, t, _) {
        // The compact link arrives over the second half of the collapse, as
        // the hero's own fades out beneath it.
        final shown = ((t - .5) / .5).clamp(0.0, 1.0);
        return DecoratedBox(
          // A hairline appears under the bar once rows pass beneath it.
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: palette.line.withValues(alpha: palette.line.a * t),
                width: IrisStroke.hairline,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              IrisSpace.sm,
              gutter,
              IrisSpace.sm,
            ),
            child: Row(
              children: [
                pill,
                if (demo) ...[
                  const SizedBox(width: IrisSpace.sm),
                  IrisChip.state('Demo', AgentState.waiting, palette),
                ],
                Expanded(
                  child: shown == 0
                      ? const SizedBox.shrink()
                      : IgnorePointer(
                          ignoring: shown < .5,
                          child: ExcludeSemantics(
                            excluding: shown < .5,
                            child: Opacity(
                              opacity: shown,
                              child: Transform.translate(
                                offset: Offset(0, (1 - shown) * 8),
                                child: Center(
                                  child: _CompactLink(
                                    linkState: linkState,
                                    headline: headline,
                                    onTap: onGateway,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                settings,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The hero folded into the bar: the link's dot and headline.
class _CompactLink extends StatelessWidget {
  const _CompactLink({
    required this.linkState,
    required this.headline,
    required this.onTap,
  });

  final AgentState linkState;
  final String headline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: 'Connection: $headline',
      ensureTapTarget: false,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: palette.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
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
    required this.pins,
    required this.live,
    required this.lifted,
    required this.fetchedPins,
    required this.top,
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

  /// Pinned conversation ids, newest pin first.
  final List<String> pins;

  /// Conversations replying right now, by stored id.
  final Map<String, LiveStatus> live;

  /// The conversation whose menu is open.
  final String? lifted;

  /// Pinned conversations that were not in the loaded pages.
  final Map<String, ConversationSummary> fetchedPins;

  /// What scrolls in above the rows: the hero and the usage strip.
  final List<Widget> top;
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
    final page = conversations.value;
    return RefreshIndicator(
      color: context.palette.accent,
      backgroundColor: context.palette.surfaceRaised,
      onRefresh: onRefresh,
      child: ListView(
        controller: scroll,
        // A short list still pulls to refresh.
        physics: const AlwaysScrollableScrollPhysics(),
        // The bottom padding is the height of the floating bar plus its
        // fade, so the last row can be scrolled clear of it.
        padding: const EdgeInsets.only(bottom: _barClearance),
        children: [
          ...top,
          if (page == null)
            ..._placeholder(context)
          else
            ..._rows(context, page),
        ],
      ),
    );
  }

  /// Before the first page: what went wrong, or placeholders where rows will
  /// be while it loads or the link comes up.
  List<Widget> _placeholder(BuildContext context) {
    final gutter = context.window.gutter;
    if (conversations.error case final error?) {
      return [
        IrisEmptyState(
          title: 'Could not load conversations',
          message: error is IrisFailure
              ? error.message ?? error.kind.name
              : '$error',
          action: IrisButton(label: 'Try again', onPressed: onRetry),
        ),
      ];
    }
    return [
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: gutter,
          vertical: IrisSpace.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 6; i++) ...[
              const IrisSkeleton(width: 220, height: 16),
              const SizedBox(height: IrisSpace.xs),
              const IrisSkeleton(width: 120, height: 12),
              const SizedBox(height: IrisSpace.lg),
            ],
          ],
        ),
      ),
    ];
  }

  /// The search field, then the rows or what the search found.
  List<Widget> _rows(BuildContext context, ConversationPage page) {
    final gutter = context.window.gutter;
    final list = [...page.items, ...more];
    if (list.isEmpty) {
      return const [
        IrisEmptyState(
          title: 'No conversations yet',
          message:
              'Start one below. It will show here and in every other '
              'client of this agent.',
        ),
      ];
    }
    final hasMore = list.length < page.total;
    final now = this.now;
    final open = onOpen;
    final next = onMore;
    final searching = search.text.trim().isNotEmpty;
    final byId = {...fetchedPins, for (final c in list) c.id: c};
    final pinnedRows = [
      for (final id in pins)
        if (byId[id] != null) byId[id]!,
    ];
    final liveRows = [
      for (final c in list)
        if (live.containsKey(c.id) && !pins.contains(c.id)) c,
    ];
    final recentRows = [
      for (final c in list)
        if (!pins.contains(c.id) && !live.containsKey(c.id)) c,
    ];

    return [
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
        ..._section(
          context,
          gutter,
          'Pinned',
          pinnedRows,
          now,
          open,
          pinned: true,
        ),
        ..._section(context, gutter, 'Live', liveRows, now, open),
        ..._section(context, gutter, 'Recent', recentRows, now, open),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IrisSpace.md),
            child: Center(
              child: IrisButton(
                label: 'Show more',
                tone: IrisButtonTone.ghost,
                busy: loadingMore,
                // The server no longer counts what was archived here.
                onPressed: next == null
                    ? null
                    : () => next(
                        list.length -
                            list.where((row) => gone.contains(row.id)).length,
                      ),
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
  }

  /// A labelled run of rows; nothing at all when [rows] is empty, so Pinned
  /// and Live only show when there is something to show.
  List<Widget> _section(
    BuildContext context,
    double gutter,
    String label,
    List<ConversationSummary> rows,
    DateTime now,
    ValueChanged<ConversationSummary>? open, {
    bool pinned = false,
  }) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.sm,
          gutter,
          IrisSpace.sm,
        ),
        child: IrisLabel(label, color: context.palette.inkFaint),
      ),
      for (final conversation in rows)
        Leaving(
          key: ValueKey(conversation.id),
          gone: gone.contains(conversation.id),
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.xs),
            child: ConversationRow(
              title: titles[conversation.id] ?? conversation.title,
              subtitle: _subtitle(conversation, now),
              pinned: pinned,
              lifted: lifted == conversation.id,
              live: live[conversation.id],
              onTap: open == null ? null : () => open(conversation),
              onLongPress: onActions == null
                  ? null
                  : () => onActions!(conversation),
            ),
          ),
        ),
    ];
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
    // What was archived or renamed here counts, ahead of the server's view.
    final local = localMatches([
      for (final row in list)
        if (!gone.contains(row.id))
          if (titles[row.id] case final title?)
            ConversationSummary(
              id: row.id,
              title: title,
              startedAt: row.startedAt,
              messageCount: row.messageCount,
              source: row.source,
              profile: row.profile,
            )
          else
            row,
    ], search.text);
    final rows = hits == null
        ? <Widget>[
            for (final conversation in local)
              Padding(
                key: ValueKey('local-${conversation.id}'),
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, IrisSpace.xs),
                child: ConversationRow(
                  title: conversation.title,
                  subtitle: _subtitle(conversation, now),
                  onTap: open == null ? null : () => open(conversation),
                ),
              ),
          ]
        : <Widget>[
            for (final found in hits.where(
              (hit) => !hit.archived && !gone.contains(hit.storedId),
            ))
              Builder(
                key: ValueKey('hit-${found.storedId}'),
                builder: (context) {
                  final title = titles[found.storedId] ?? found.title;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      IrisSpace.xs,
                    ),
                    child: SearchHitRow(
                      hit: SearchHit(
                        storedId: found.storedId,
                        title: title,
                        snippet: found.snippet,
                        lastActive: found.lastActive,
                        messageCount: found.messageCount,
                      ),
                      onTap: open == null
                          ? null
                          : () => open(
                              ConversationSummary(
                                id: found.storedId,
                                title: title,
                              ),
                            ),
                    ),
                  );
                },
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
