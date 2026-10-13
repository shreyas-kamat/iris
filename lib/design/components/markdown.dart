/// Markdown, drawn with Iris's own type and colour.
///
/// The agent writes Markdown, and a reply should read as typeset text, not as
/// source. `package:markdown` parses it (GitHub flavour: tables,
/// strikethrough, autolinks, task lists); this file draws the result from
/// design-system tokens rather than a generic Markdown theme, so a reply looks
/// like the rest of the app in every skin. Half-written Markdown — normal
/// while a reply streams — parses as plain text and never throws.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';

class IrisMarkdown extends StatefulWidget {
  const IrisMarkdown(this.data, {this.onTapLink, super.key});

  final String data;

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
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(widget.data);
    final renderer = _Renderer(context.iris, widget.onTapLink, _recognizers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _Renderer.spaced(renderer.blocks(nodes), IrisSpace.sm),
    );
  }
}

final class _Renderer {
  _Renderer(this.theme, this.onTapLink, this.recognizers);

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
    return switch (node.tag) {
      'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => _rich(
        inline(node.children, _heading(node.tag)),
      ),
      'ul' || 'ol' => list(node),
      'blockquote' => quote(node),
      'pre' => code(node),
      'hr' => Divider(
        height: IrisSpace.md,
        thickness: IrisStroke.hairline,
        color: theme.palette.line,
      ),
      'table' => table(node),
      _ => _rich(inline(node.children, body)),
    };
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
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.palette.surfaceSunken,
          borderRadius: const BorderRadius.all(IrisRadius.xs),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(IrisSpace.sm),
          child: Text(
            text,
            style: theme.typography.codeSmall.copyWith(
              color: theme.palette.ink,
            ),
          ),
        ),
      ),
    );
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
                  child: _rich(
                    inline(
                      cell.children,
                      cell.tag == 'th'
                          ? body.copyWith(fontWeight: FontWeight.w600)
                          : body,
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
