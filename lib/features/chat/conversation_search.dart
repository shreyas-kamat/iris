/// Finding a conversation from home: a field above the list, and rows for
/// what the server's full-text search found.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/motion.dart';
import '../../design/tokens/palette.dart';
import 'relative_time.dart';

/// The field's row height, including its breathing room.
const double searchFieldExtent = 64;

/// The server's hits for a query, one per conversation.
final conversationSearchProvider = FutureProvider.autoDispose
    .family<List<SearchHit>, String>((ref, query) async {
      final chat = await ref.watch(activeChatProvider.future);
      if (chat == null) return const [];
      return switch (await chat.search(query)) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

/// The loaded rows whose title holds [query], ignoring case: shown the
/// moment someone types, before the server is asked.
List<ConversationSummary> localMatches(
  List<ConversationSummary> rows,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return rows;
  return [
    for (final row in rows)
      if (row.title.toLowerCase().contains(needle)) row,
  ];
}

class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.focusNode,
    required this.searching,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The server is being asked; a thin line runs under the field.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return SizedBox(
      height: searchFieldExtent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: IrisSize.control,
            padding: const EdgeInsets.symmetric(horizontal: IrisSpace.md),
            decoration: BoxDecoration(
              color: palette.surfaceSunken,
              borderRadius: const BorderRadius.all(IrisRadius.full),
              border: Border.all(
                color: palette.line,
                width: IrisStroke.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: IrisSize.iconSmall,
                  color: palette.inkMuted,
                ),
                const SizedBox(width: IrisSpace.sm),
                Expanded(
                  child: Semantics(
                    textField: true,
                    label: 'Search conversations',
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // The hint is drawn underneath in the same metrics,
                        // as IrisField does, so it lines up with the first
                        // typed character.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: controller,
                              builder: (context, value, _) => Align(
                                alignment: Alignment.centerLeft,
                                child: Opacity(
                                  opacity: value.text.isEmpty ? 1 : 0,
                                  child: Text(
                                    'Search conversations',
                                    style: type.body.copyWith(
                                      color: palette.inkFaint,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        EditableText(
                          controller: controller,
                          focusNode: focusNode,
                          style: type.body.copyWith(color: palette.ink),
                          cursorColor: palette.accent,
                          backgroundCursorColor: palette.inkFaint,
                          selectionColor: palette.accent.withValues(alpha: .28),
                          textInputAction: TextInputAction.search,
                        ),
                      ],
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      // Its own semantics node, so it is not folded into the
                      // list's.
                      : Semantics(
                          container: true,
                          child: IrisPressable(
                            onTap: () {
                              controller.clear();
                              focusNode.unfocus();
                            },
                            semanticLabel: 'Clear search',
                            child: Icon(
                              Icons.close,
                              size: IrisSize.iconSmall,
                              color: palette.inkMuted,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: AnimatedOpacity(
              opacity: searching ? 1 : 0,
              duration: context.reduceMotion
                  ? Duration.zero
                  : IrisDurations.quick,
              child: searching && !context.reduceMotion
                  ? LinearProgressIndicator(
                      minHeight: 1.5,
                      color: palette.accent,
                      backgroundColor: const Color(0x00000000),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A conversation the search found (frame B4): its title with the matched
/// words in accent, the matching snippet with them marked, and a mono line
/// of when and how many messages matched. The best hit sits in a card.
class SearchHitRow extends StatelessWidget {
  const SearchHitRow({
    required this.hit,
    required this.onTap,
    this.query = '',
    this.now,
    this.pinned = false,
    this.best = false,
    super.key,
  });

  final SearchHit hit;
  final VoidCallback? onTap;

  /// What was searched for, to mark in the title.
  final String query;

  /// For the relative time; without it the time is left out.
  final DateTime? now;
  final bool pinned;

  /// The first hit, drawn in a card.
  final bool best;

  bool get _matchesTitle {
    final needle = query.trim().toLowerCase();
    return needle.isNotEmpty && hit.title.toLowerCase().contains(needle);
  }

  List<TextSpan> _title(Color accent) {
    final needle = query.trim().toLowerCase();
    final title = hit.title;
    final at = needle.isEmpty ? -1 : title.toLowerCase().indexOf(needle);
    if (at < 0) return [TextSpan(text: title)];
    return [
      TextSpan(text: title.substring(0, at)),
      TextSpan(
        text: title.substring(at, at + needle.length),
        style: TextStyle(color: accent),
      ),
      TextSpan(text: title.substring(at + needle.length)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final meta = [
      if (hit.lastActive != null && now != null)
        relativeTime(hit.lastActive!, now!),
      '${hit.matches} ${hit.matches == 1 ? 'match' : 'matches'}',
      if (pinned) 'pinned',
    ].join(' · ');
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceSunken,
              borderRadius: const BorderRadius.all(IrisRadius.md),
            ),
            child: const IrisOrb(state: AgentState.rest, size: 30, glow: false),
          ),
          const SizedBox(width: IrisSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_matchesTitle)
                  Text.rich(
                    TextSpan(children: _title(palette.accent)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(fontSize: 14, color: palette.ink),
                  )
                else
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(fontSize: 14, color: palette.ink),
                  ),
                if (hit.snippet.isNotEmpty) ...[
                  const SizedBox(height: IrisSpace.xxs),
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final run in hit.snippet)
                          TextSpan(
                            text: run.text,
                            style: run.matched
                                ? TextStyle(
                                    color: palette.ink,
                                    backgroundColor: palette.accentQuiet,
                                  )
                                : null,
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: palette.inkMuted),
                  ),
                ],
                const SizedBox(height: IrisSpace.xs),
                Text(
                  meta,
                  style: type.codeSmall.copyWith(
                    fontSize: 11,
                    color: palette.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return IrisPressable(
      onTap: onTap,
      semanticLabel: hit.title,
      ensureTapTarget: false,
      child: best
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: palette.line,
                  width: IrisStroke.hairline,
                ),
              ),
              child: row,
            )
          : row,
    );
  }
}

/// Under an empty, focused field: the last searches as chips, newest first,
/// with Clear, and what a search covers.
class RecentSearchChips extends StatelessWidget {
  const RecentSearchChips({
    required this.queries,
    required this.onPick,
    required this.onClear,
    super.key,
  });

  final List<String> queries;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (queries.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: IrisLabel('Recent searches', color: palette.inkFaint),
              ),
              IrisPressable(
                onTap: onClear,
                semanticLabel: 'Clear recent searches',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: IrisSpace.xs),
                  child: Text(
                    'Clear',
                    style: type.caption.copyWith(color: palette.accent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: IrisSpace.sm),
          Wrap(
            spacing: IrisSpace.sm,
            runSpacing: IrisSpace.sm,
            children: [
              for (final query in queries)
                IrisPressable(
                  onTap: () => onPick(query),
                  semanticLabel: 'Search $query',
                  ensureTapTarget: false,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: palette.lineStrong,
                        width: IrisStroke.hairline,
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        query,
                        style: type.body.copyWith(
                          fontSize: 14,
                          color: palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: IrisSpace.md),
        ],
        Text(
          'Searches titles and messages on this server, including archived '
          'chats.',
          style: type.caption.copyWith(color: palette.inkMuted),
        ),
      ],
    );
  }
}
