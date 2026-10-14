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

/// The field's row height, including its breathing room: how far the list
/// starts scrolled, so the field waits just above the first row.
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
                          selectionColor: palette.accent.withValues(
                            alpha: .28,
                          ),
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

/// A conversation the search found: its title, and the matching words in
/// ink among muted text.
class SearchHitRow extends StatelessWidget {
  const SearchHitRow({required this.hit, required this.onTap, super.key});

  final SearchHit hit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: hit.title,
      ensureTapTarget: false,
      child: Padding(
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
                children: [
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
                                      fontWeight: FontWeight.w500,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
