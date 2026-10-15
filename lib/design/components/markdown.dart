/// Markdown, drawn with Iris's own type and colour.
///
/// The agent writes Markdown, and a reply should read as typeset text, not as
/// source. `package:markdown` parses it (GitHub flavour: tables,
/// strikethrough, autolinks, task lists); this file draws the result from
/// design-system tokens rather than a generic Markdown theme, so a reply looks
/// like the rest of the app in every skin. Half-written Markdown — normal
/// while a reply streams — parses as plain text and never throws.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../theme/iris_theme.dart';
import '../tokens/code_colors.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import '../tokens/palette.dart';
import 'markdown_image.dart';
import 'markdown_syntax.dart';
import 'math.dart';
import 'primitives.dart';

class IrisMarkdown extends StatefulWidget {
  const IrisMarkdown(
    this.data, {
    this.onTapLink,
    this.highlight = true,
    super.key,
  });

  final String data;

  /// Colour code blocks by language. Off while a reply is still arriving:
  /// re-highlighting on every delta is wasted work, and a block that
  /// recolours as it grows flickers.
  final bool highlight;

  /// Called with a link's target when it is tapped. Without it, links are
  /// drawn but inert.
  final ValueChanged<String>? onTapLink;

  @override
  State<IrisMarkdown> createState() => _IrisMarkdownState();
}

class _IrisMarkdownState extends State<IrisMarkdown> {
  /// Link taps are gesture recognisers held by text spans. They are made
  /// afresh on every build, so the previous build's are disposed first.
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final nodes = irisDocument().parse(widget.data);
    final renderer = _Renderer(
      context.iris,
      widget.onTapLink,
      _recognizers,
      highlight: widget.highlight,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _Renderer.spaced(renderer.blocks(nodes), IrisSpace.sm),
    );
  }
}

final class _Renderer {
  _Renderer(
    this.theme,
    this.onTapLink,
    this.recognizers, {
    required this.highlight,
  });

  final bool highlight;

  final IrisThemeData theme;
  final ValueChanged<String>? onTapLink;
  final List<TapGestureRecognizer> recognizers;

  static const _blockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'hr',
    'table',
    'div',
    'section',
    'math-display',
  };

  TextStyle get body =>
      theme.typography.bodyLarge.copyWith(color: theme.palette.ink);

  TextStyle _heading(String tag) => switch (tag) {
    'h1' || 'h2' => theme.typography.title.copyWith(color: theme.palette.ink),
    'h3' => theme.typography.heading.copyWith(color: theme.palette.ink),
    _ => body.copyWith(fontWeight: FontWeight.w600),
  };

  static List<Widget> spaced(List<Widget> widgets, double gap) => [
    for (var i = 0; i < widgets.length; i++) ...[
      if (i > 0) SizedBox(height: gap),
      widgets[i],
    ],
  ];

  List<Widget> blocks(List<md.Node> nodes) => [
    for (final node in nodes) ?block(node),
  ];

  Widget? block(md.Node node) {
    if (node is md.Text) {
      return node.text.trim().isEmpty ? null : _rich(inline([node], body));
    }
    if (node is! md.Element) return null;
    final image = node.tag == 'p' ? _soleImage(node) : null;
    if (image != null) {
      return MarkdownImage(
        url: image.attributes['src']!,
        alt: image.attributes['alt'],
      );
    }
    return switch (node.tag) {
      'h1' ||
      'h2' ||
      'h3' ||
      'h4' ||
      'h5' ||
      'h6' => _rich(inline(node.children, _heading(node.tag))),
      'ul' || 'ol' => list(node),
      'blockquote' => quote(node),
      'pre' => code(node),
      'hr' => Divider(
        height: IrisSpace.md,
        thickness: IrisStroke.hairline,
        color: theme.palette.line,
      ),
      'table' => table(node),
      'div' => alert(node),
      'section' => footnotes(node),
      mathDisplayTag => IrisMath(node.textContent, display: true, style: body),
      _ => _rich(inline(node.children, body)),
    };
  }

  /// The image a paragraph holds and nothing else, if its source can be shown.
  static md.Element? _soleImage(md.Element p) {
    final children = [
      for (final c in p.children ?? const <md.Node>[])
        if (c is! md.Text || c.text.trim().isNotEmpty) c,
    ];
    if (children.length != 1) return null;
    final only = children.single;
    return only is md.Element &&
            only.tag == 'img' &&
            MarkdownImage.canShow(only.attributes['src'])
        ? only
        : null;
  }

  Widget _rich(List<InlineSpan> spans) => Text.rich(TextSpan(children: spans));

  List<InlineSpan> inline(
    List<md.Node>? nodes,
    TextStyle style, [
    GestureRecognizer? link,
  ]) {
    final spans = <InlineSpan>[];
    for (final node in nodes ?? const <md.Node>[]) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: style, recognizer: link));
      } else if (node is md.Element) {
        spans.addAll(_element(node, style, link));
      }
    }
    return spans;
  }

  List<InlineSpan> _element(
    md.Element node,
    TextStyle style,
    GestureRecognizer? link,
  ) {
    switch (node.tag) {
      case 'strong':
        return inline(
          node.children,
          style.copyWith(fontWeight: FontWeight.w600),
          link,
        );
      case 'em':
        return inline(
          node.children,
          style.copyWith(fontStyle: FontStyle.italic),
          link,
        );
      case 'del':
        return inline(
          node.children,
          style.copyWith(decoration: TextDecoration.lineThrough),
          link,
        );
      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: _inlineCode(style),
            recognizer: link,
          ),
        ];
      case 'a':
        return inline(
          node.children,
          style.copyWith(
            color: theme.palette.accent,
            decoration: TextDecoration.underline,
            decorationColor: theme.palette.accent,
          ),
          _link(node.attributes['href']) ?? link,
        );
      case 'br':
        return const [TextSpan(text: '\n')];
      case 'img':
        return [
          TextSpan(
            text: node.attributes['alt'] ?? 'image',
            style: style.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.palette.inkMuted,
            ),
          ),
        ];
      case 'input':
        // A task-list checkbox.
        return [
          TextSpan(
            text: node.attributes.containsKey('checked') ? '☑ ' : '☐ ',
            style: style,
          ),
        ];
      case 'sup' when node.attributes['class'] == 'footnote-ref':
        return [TextSpan(text: _superscript(node.textContent), style: style)];
      case 'sub' || 'sup':
        return inline(
          node.children,
          style.copyWith(
            fontSize: (style.fontSize ?? 16) * 0.72,
            fontFeatures: [
              node.tag == 'sub'
                  ? const FontFeature.subscripts()
                  : const FontFeature.superscripts(),
            ],
          ),
          link,
        );
      case 'kbd':
        return [
          TextSpan(text: ' ${node.textContent} ', style: _inlineCode(style)),
        ];
      case 'mark':
        return inline(
          node.children,
          style.copyWith(backgroundColor: theme.palette.accentQuiet),
          link,
        );
      case mathInlineTag || mathDisplayTag:
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: IrisMath(
              node.textContent,
              display: node.tag == mathDisplayTag,
              style: style,
            ),
          ),
        ];
      default:
        return inline(node.children, style, link);
    }
  }

  TextStyle _inlineCode(TextStyle around) => theme.typography.code.copyWith(
    fontSize: (around.fontSize ?? 16) * 0.9,
    color: theme.palette.ink,
    backgroundColor: theme.palette.surfaceSunken,
  );

  GestureRecognizer? _link(String? href) {
    final tap = onTapLink;
    if (href == null || href.isEmpty || tap == null) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => tap(href);
    recognizers.add(recognizer);
    return recognizer;
  }

  static const _alerts = {
    'note': ('Note', Icons.info_outline, AgentState.idle),
    'tip': ('Tip', Icons.lightbulb_outline, AgentState.done),
    'important': ('Important', Icons.priority_high, AgentState.thinking),
    'warning': ('Warning', Icons.warning_amber_outlined, AgentState.working),
    'caution': ('Caution', Icons.dangerous_outlined, AgentState.failed),
  };

  /// A GitHub alert: `> [!NOTE]` and its kin. Any other `div` draws its
  /// children as ordinary blocks.
  Widget alert(md.Element node) {
    final kind = RegExp(r'markdown-alert-(\w+)')
        .firstMatch(node.attributes['class'] ?? '')?[1];
    final style = _alerts[kind];
    final children = [
      for (final child in node.children ?? const <md.Node>[])
        if (child is! md.Element ||
            child.attributes['class'] != 'markdown-alert-title')
          child,
    ];
    if (style == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: spaced(blocks(children), IrisSpace.sm),
      );
    }
    final (title, icon, state) = style;
    final color = theme.palette.colorFor(state);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: IrisStroke.ring)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: IrisSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: IrisSize.iconSmall, color: color),
                const SizedBox(width: IrisSpace.xs),
                Text(
                  title,
                  style: body.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: IrisSpace.xs),
            ...spaced(blocks(children), IrisSpace.sm),
          ],
        ),
      ),
    );
  }

  /// The footnotes block GitHub puts at the end: a numbered list, smaller and
  /// muted, under a hairline. The ↩ back-links go nowhere in an app, so they
  /// are dropped.
  Widget footnotes(md.Element node) {
    final small = body.copyWith(
      fontSize: (body.fontSize ?? 16) * 0.85,
      color: theme.palette.inkMuted,
    );
    final items = elementsIn(node).where((e) => e.tag == 'li').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
          height: IrisSpace.md,
          thickness: IrisStroke.hairline,
          color: theme.palette.line,
        ),
        for (final (i, item) in items.indexed)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${i + 1}. ', style: small),
                ...inline(_withoutBackrefs(item.children), small),
              ],
            ),
          ),
      ],
    );
  }

  static Iterable<md.Element> elementsIn(md.Element node) sync* {
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is md.Element) {
        yield child;
        yield* elementsIn(child);
      }
    }
  }

  /// A footnote's content without its ↩ links. Its paragraph is flattened to
  /// inline nodes so the number and the text share a line.
  static List<md.Node> _withoutBackrefs(List<md.Node>? nodes) => [
    for (final node in nodes ?? const <md.Node>[])
      if (node is md.Element && node.attributes['class'] == 'footnote-backref')
        ...const <md.Node>[]
      else if (node is md.Element && node.tag == 'p')
        ..._withoutBackrefs(node.children)
      else
        node,
  ];

  static String _superscript(String digits) => digits
      .split('')
      .map((d) => const {
            '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
            '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
          }[d] ?? d)
      .join();

  Widget list(md.Element node) {
    final ordered = node.tag == 'ol';
    var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final rows = <Widget>[];
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'li') continue;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ordered ? 28 : 18,
              child: Text(
                ordered ? '${number++}.' : '•',
                style: body.copyWith(color: theme.palette.inkMuted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: spaced(_item(child), IrisSpace.xxs),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced(rows, IrisSpace.xs),
    );
  }

  /// A list item's contents. A tight item holds inline nodes directly, a loose
  /// one holds paragraphs, and either can hold a nested list.
  List<Widget> _item(md.Element item) {
    final widgets = <Widget>[];
    final run = <md.Node>[];
    void flush() {
      if (run.isEmpty) return;
      widgets.add(_rich(inline(List.of(run), body)));
      run.clear();
    }

    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && _blockTags.contains(child.tag)) {
        flush();
        if (block(child) case final widget?) widgets.add(widget);
      } else {
        run.add(child);
      }
    }
    flush();
    return widgets;
  }

  Widget quote(md.Element node) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: theme.palette.lineStrong,
          width: IrisStroke.ring,
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: IrisSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: spaced(
          blocks(node.children ?? const <md.Node>[]),
          IrisSpace.sm,
        ),
      ),
    ),
  );

  Widget code(md.Element node) {
    final text = node.textContent.replaceFirst(RegExp(r'\n$'), '');
    final language = _languageOf(node);
    if (language == 'math') {
      return IrisMath(text, display: true, style: body);
    }
    return _CodeBlock(code: text, language: language, highlight: highlight);
  }

  /// The fence's language, from the `language-xxx` class the parser puts on
  /// the inner `code` element. Null for an unlabelled fence.
  static String? _languageOf(md.Element pre) {
    for (final child in pre.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'];
        if (cls != null && cls.startsWith('language-')) {
          return cls.substring('language-'.length);
        }
      }
    }
    return null;
  }

  Widget table(md.Element node) {
    final rows = <List<Widget>>[];
    void collect(md.Element element) {
      for (final child in element.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          rows.add([
            for (final cell in child.children ?? const <md.Node>[])
              if (cell is md.Element)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IrisSpace.sm,
                    vertical: IrisSpace.xs,
                  ),
                  child: Align(
                    alignment: switch (cell.attributes['align']) {
                      'center' => Alignment.center,
                      'right' => Alignment.centerRight,
                      _ => Alignment.centerLeft,
                    },
                    child: _rich(
                      inline(
                        cell.children,
                        cell.tag == 'th'
                            ? body.copyWith(fontWeight: FontWeight.w600)
                            : body,
                      ),
                    ),
                  ),
                ),
          ]);
        } else {
          collect(child);
        }
      }
    }

    collect(node);
    if (rows.isEmpty) return const SizedBox.shrink();
    // A Table needs every row the same length; a ragged table is padded.
    final width = rows.map((row) => row.length).reduce(math.max);
    if (width == 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(
          color: theme.palette.line,
          width: IrisStroke.hairline,
        ),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                ...row,
                for (var i = row.length; i < width; i++)
                  const SizedBox.shrink(),
              ],
            ),
        ],
      ),
    );
  }
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
  'bash', 'python', 'javascript', 'typescript', 'json', 'yaml', 'sql',
  'go', 'rust', 'java', 'kotlin', 'swift', 'dart', 'dockerfile',
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
  final language = best.language != null &&
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
  const _CodeBlock({
    required this.code,
    this.language,
    this.highlight = true,
  });

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
      widget.language ?? (widget.highlight ? detectLanguage(widget.code) : null);

  Widget _codeText(BuildContext context) {
    final palette = context.palette;
    final style = context.type.code.copyWith(
      fontSize: 12.5,
      height: 1.6,
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
      TextSpan(style: style.copyWith(color: colors.plain), children: [span]),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    child: Text(
                      _language ?? 'code',
                      style: type.codeSmall.copyWith(
                        fontSize: 11,
                        color: palette.inkFaint,
                      ),
                    ),
                  ),
                  IrisPressable(
                    onTap: _copy,
                    ensureTapTarget: false,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 13, color: palette.accent),
                        const SizedBox(width: 5),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: type.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: palette.accent,
                          ),
                        ),
                      ],
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
