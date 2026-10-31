/// Markdown, drawn with Iris's own type and colour.
///
/// The agent writes Markdown, and a reply should read as typeset text, not as
/// source. `package:gpt_markdown` parses and lays it out (headings, lists,
/// task lists, tables, quotes, alerts, citations, LaTeX, links, images); this
/// file feeds it design-system tokens rather than a generic Markdown theme, so
/// a reply looks like the rest of the app in every skin, and swaps in Iris's
/// own code block and tap-to-load image. Half-written Markdown — normal while
/// a reply streams — never throws.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../theme/iris_theme.dart';
import '../tokens/code_colors.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';
import 'markdown_image.dart';
import 'media_image.dart';
import 'primitives.dart';

class IrisMarkdown extends StatelessWidget {
  const IrisMarkdown(
    this.data, {
    this.onTapLink,
    this.loadMediaImage,
    this.highlight = true,
    super.key,
  });

  final String data;
  final MediaImageLoader? loadMediaImage;

  /// Colour code blocks by language. Off while a reply is still arriving:
  /// re-highlighting on every delta is wasted work, and a block that
  /// recolours as it grows flickers.
  final bool highlight;

  /// Called with a link's target when it is tapped. Without it, links are
  /// drawn but inert.
  final ValueChanged<String>? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final blocks = <Widget>[];
    final loader = loadMediaImage;
    var from = 0;
    if (loader != null) {
      for (final match in _mediaLine.allMatches(data)) {
        final path = _imagePath(match.group(1)!);
        if (path == null) continue;
        _addText(blocks, theme, data.substring(from, match.start));
        blocks.add(MediaImage(path: path, load: loader));
        from = match.end;
      }
    }
    _addText(blocks, theme, data.substring(from));
    return GptMarkdownTheme(
      gptThemeData: _gptTheme(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: IrisSpace.sm),
            blocks[i],
          ],
        ],
      ),
    );
  }

  void _addText(List<Widget> blocks, IrisThemeData theme, String text) {
    if (text.trim().isEmpty) return;
    final tap = onTapLink;
    blocks.add(
      GptMarkdown(
        text,
        style: theme.typography.bodyLarge.copyWith(color: theme.palette.ink),
        useDollarSignsForLatex: true,
        isStreaming: false,
        onLinkTap: tap == null ? null : (url, _) => tap(url),
        imageBuilder: (context, url, _, _) => MarkdownImage.canShow(url)
            ? MarkdownImage(url: url)
            : const SizedBox.shrink(),
        codeBuilder: (context, language, code, _) => _CodeBlock(
          code: code.replaceFirst(RegExp(r'\n$'), ''),
          language: language.trim().isEmpty ? null : language.trim(),
          highlight: highlight,
        ),
      ),
    );
  }
}

final _mediaLine = RegExp(r'^[ \t]*MEDIA:([^\r\n]+)[ \t]*$', multiLine: true);
final _imageExtension = RegExp(
  r'\.(?:png|jpe?g|gif|webp)$',
  caseSensitive: false,
);

String? _imagePath(String raw) {
  var path = raw.trim();
  if (path.length >= 2 &&
      ((path.startsWith('"') && path.endsWith('"')) ||
          (path.startsWith("'") && path.endsWith("'")))) {
    path = path.substring(1, path.length - 1);
  }
  return _imageExtension.hasMatch(path) ? path : null;
}

/// Iris's tokens, in the shape `gpt_markdown` reads them.
GptMarkdownThemeData _gptTheme(IrisThemeData theme) {
  final palette = theme.palette;
  final type = theme.typography;
  final body = type.bodyLarge.copyWith(color: palette.ink);
  final heading = type.heading.copyWith(color: palette.ink);
  final title = type.title.copyWith(color: palette.ink);
  final minor = body.copyWith(fontWeight: FontWeight.w600);

  AlertStyle alert(AgentState state) {
    final color = palette.colorFor(state);
    return AlertStyle(
      color: color,
      backgroundColor: color.withValues(alpha: .10),
      titleStyle: type.codeSmall.copyWith(
        fontSize: 11,
        letterSpacing: 1,
        color: color,
      ),
      borderRadius: const Radius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  return GptMarkdownThemeData(
    brightness: theme.isDark ? Brightness.dark : Brightness.light,
    h1: title,
    h2: title,
    h3: heading,
    h4: minor,
    h5: minor,
    h6: minor,
    hrLineColor: palette.line,
    hrLineThickness: IrisStroke.hairline,
    linkColor: palette.accent,
    linkHoverColor: palette.accent,
    autoAddDividerLineAfterH1: false,
    highlightColor: palette.accentQuiet,
    styleSheet: GptMarkdownStyleSheet(
      blockSpacing: IrisSpace.sm,
      link: LinkStyle(
        color: palette.accent,
        decoration: TextDecoration.underline,
      ),
      inlineCode: InlineCodeStyle(
        fontFamily: type.code.fontFamily,
        fontSizeFactor: .9,
        color: palette.ink,
        backgroundColor: palette.surfaceSunken,
        borderRadius: const Radius.circular(6),
      ),
      blockQuote: BlockQuoteStyle(
        barWidth: IrisStroke.ring,
        barColor: palette.lineStrong,
      ),
      list: ListStyle(
        bulletColor: palette.inkMuted,
        markerTextStyle: body.copyWith(color: palette.inkMuted),
      ),
      checkbox: CheckboxStyle(
        checkedColor: palette.accent,
        uncheckedColor: palette.lineStrong,
        interactive: false,
      ),
      table: TableStyle(
        borderColor: palette.line,
        borderWidth: IrisStroke.hairline,
        headerBackground: palette.surfaceSunken,
        headerTextStyle: body.copyWith(fontWeight: FontWeight.w600),
        cellPadding: const EdgeInsets.symmetric(
          horizontal: IrisSpace.sm,
          vertical: IrisSpace.xs,
        ),
      ),
      sourceTag: SourceTagStyle(
        textStyle: type.codeSmall.copyWith(fontSize: 11, color: palette.accent),
      ),
      image: const ImageStyle(borderRadius: Radius.circular(14)),
      alert: AlertStyle(
        note: alert(AgentState.loading),
        tip: alert(AgentState.done),
        important: alert(AgentState.thinking),
        warning: alert(AgentState.working),
        caution: alert(AgentState.failed),
      ),
    ),
  );
}

/// The longest block worth highlighting. Past this the parse is slow enough
/// to drop frames, and a block that long is read by scrolling, not by colour.
const int maxHighlightLength = 20000;

final Highlight _highlighter = Highlight()
  ..registerLanguages(builtinAllLanguages);

/// The names people write on fences, mapped to the grammar's.
const _aliases = {
  'sh': 'bash',
  'zsh': 'bash',
  'shell': 'bash',
  'console': 'bash',
  'py': 'python',
  'ts': 'typescript',
  'js': 'javascript',
  'yml': 'yaml',
  'md': 'markdown',
  'kt': 'kotlin',
  'rs': 'rust',
  'golang': 'go',
};

/// The grammar for a fence's language, or null when there is none.
String? highlightLanguage(String? fence) {
  final name = fence?.trim().toLowerCase();
  if (name == null || name.isEmpty) return null;
  final resolved = _aliases[name] ?? name;
  return _highlighter.getLanguage(resolved) == null ? null : resolved;
}

/// The languages an unlabelled block may be detected as. A short list is
/// fast and rarely wrong; the full grammar set mislabels prose and logs.
const _detectable = [
  'bash',
  'python',
  'javascript',
  'typescript',
  'json',
  'yaml',
  'sql',
  'go',
  'rust',
  'java',
  'kotlin',
  'swift',
  'dart',
  'dockerfile',
];

final Map<String, String?> _detected = {};

/// The language an unlabelled block is clearly written in, or null. It must
/// score well and clearly beat the runner-up: a wrongly coloured block reads
/// worse than a plain one.
String? detectLanguage(String code) {
  if (code.length < 20 || code.length > maxHighlightLength) return null;
  if (_detected.containsKey(code)) return _detected[code];
  final best = _highlighter.highlightAuto(code, _detectable);
  final runnerUp = best.secondBest?.relevance ?? 0;
  final language =
      best.language != null &&
          best.relevance >= 4 &&
          best.relevance >= runnerUp * 1.5
      ? best.language
      : null;
  if (_detected.length > 200) _detected.clear();
  return _detected[code] = language;
}

/// Highlighted spans, by palette, language and code. A transcript rebuilds
/// often, and the parse is the expensive part.
final Map<(IrisCodeColors, String, String), TextSpan> _spanCache = {};

TextSpan? _highlighted(String code, String? fence, IrisCodeColors colors) {
  final language = highlightLanguage(fence);
  if (language == null || code.length > maxHighlightLength) return null;
  final key = (colors, language, code);
  final cached = _spanCache[key];
  if (cached != null) return cached;
  final renderer = TextSpanRenderer(null, colors.theme);
  _highlighter.highlight(code: code, language: language).render(renderer);
  final span = renderer.span;
  if (span == null) return null;
  // Bounded, so a long session does not hold every block it ever showed.
  if (_spanCache.length > 200) _spanCache.clear();
  return _spanCache[key] = span;
}

/// A fenced code block: its language and a copy button above the code.
///
/// Stateful only for the copy confirmation. "Copied" shows for a moment and
/// then reverts, and the timer is cancelled on dispose so a block that leaves
/// the screen during that moment does not set state on a dead widget.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.code, this.language, this.highlight = true});

  final String code;
  final String? language;
  final bool highlight;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  Timer? _resetCopied;
  bool _copied = false;

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.code)));
    _resetCopied?.cancel();
    setState(() => _copied = true);
    _resetCopied = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// The fence's language, or the detected one for a finished, unlabelled block.
  String? get _language =>
      widget.language ??
      (widget.highlight ? detectLanguage(widget.code) : null);

  Widget _codeText(BuildContext context) {
    final palette = context.palette;
    final style = context.type.code.copyWith(
      fontSize: 12.5,
      height: 1.7,
      color: palette.accent,
    );
    final colors = IrisCodeColors.of(palette);
    final span = widget.highlight
        ? _highlighted(widget.code, _language, colors)
        : null;
    if (span == null) {
      return Text(widget.code, key: const ValueKey('plain'), style: style);
    }
    return Text.rich(
      TextSpan(
        style: style.copyWith(color: colors.plain),
        children: [span],
      ),
      key: const ValueKey('highlighted'),
    );
  }

  @override
  void dispose() {
    _resetCopied?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: palette.line,
                    width: IrisStroke.hairline,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _language ?? 'code',
                            overflow: TextOverflow.ellipsis,
                            style: type.codeSmall.copyWith(
                              fontSize: 11,
                              color: palette.ink,
                            ),
                          ),
                        ),
                        // A guess, and said to be one.
                        if (widget.language == null && _language != null) ...[
                          const SizedBox(width: IrisSpace.sm),
                          Text(
                            'detected',
                            style: type.codeSmall.copyWith(
                              fontSize: 11,
                              color: palette.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IrisPressable(
                    onTap: _copy,
                    child: SizedBox(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy, size: 13, color: palette.accent),
                            const SizedBox(width: 5),
                            Text(
                              _copied ? 'Copied' : 'Copy',
                              style: type.caption.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: palette.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: AnimatedSwitcher(
                // A finished reply's code cross-fades from plain to coloured
                // once, instead of snapping.
                duration: context.reduceMotion
                    ? Duration.zero
                    : IrisDurations.normal,
                switchInCurve: IrisCurves.standard,
                child: _codeText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
