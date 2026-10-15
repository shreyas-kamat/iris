// lib/design/components/markdown_syntax.dart
/// The Markdown Iris reads: GitHub's web flavour (tables, task lists,
/// footnotes, alerts, emoji) plus the few HTML tags agents use for
/// typography. Plain Dart, so it is tested without widgets.
library;

import 'package:markdown/markdown.dart' as md;

/// Inline syntaxes tried before GitHub's own, in order.
final List<md.InlineSyntax> irisInlineSyntaxes = [
  MathInlineSyntax(),
  TypographyHtmlSyntax(),
];

/// Block syntaxes tried before GitHub's own, in order.
final List<md.BlockSyntax> irisBlockSyntaxes = [const MathBlockSyntax()];

/// The parser for a reply. HTML is left unescaped: the renderer draws text,
/// never HTML, so there is nothing to inject into.
md.Document irisDocument() => md.Document(
  extensionSet: md.ExtensionSet.gitHubWeb,
  blockSyntaxes: irisBlockSyntaxes,
  inlineSyntaxes: irisInlineSyntaxes,
  encodeHtml: false,
);

/// `<sub>`, `<sup>`, `<kbd>` and `<mark>` around plain text, and `<br>`.
/// Anything else that looks like HTML stays as typed.
class TypographyHtmlSyntax extends md.InlineSyntax {
  TypographyHtmlSyntax()
    : super(
        r'<(sub|sup|kbd|mark)>([^<]*)</\1>|<br\s*/?>',
        startCharacter: 0x3C, // <
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tag = match[1];
    parser.addNode(
      tag == null
          ? md.Element.empty('br')
          : md.Element.text(tag.toLowerCase(), match[2]!),
    );
    return true;
  }
}

/// Elements the renderer draws as maths. Their only text is the TeX source.
const mathInlineTag = 'math-inline';
const mathDisplayTag = 'math-display';

/// Inline maths: `\(…\)`, `\[…\]` and `$$…$$` within a line, and `$…$` by
/// Pandoc's rule. The opening `$` is not followed by a space, the closing
/// one is not preceded by one and not followed by a digit, so prices stay
/// text.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax()
    : super(
        r'\$\$([^$]+?)\$\$'
        r'|\\\((.+?)\\\)'
        r'|\\\[(.+?)\\\]'
        r'|\$(?![\s$])((?:\\\$|[^$\n])+?)(?<![\s\\])\$(?!\d)',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] ?? match[3];
    final tex = (display ?? match[2] ?? match[4]!).trim();
    parser.addNode(
      md.Element.text(display == null ? mathInlineTag : mathDisplayTag, tex),
    );
    return true;
  }
}

/// A display block: a line opening with `$$` or `\[`, through the line that
/// closes it. A block whose close hasn't arrived (normal while a reply
/// streams) isn't claimed, so it shows as text instead of swallowing the
/// rest of the reply.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  static final _open = RegExp(r'^ {0,3}(\$\$|\\\[)(.*)$');

  /// How far ahead a close is looked for.
  static const _maxLines = 200;

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) => _span(parser) != null;

  @override
  md.Node? parse(md.BlockParser parser) {
    final (tex, lines) = _span(parser)!;
    for (var i = 0; i < lines; i++) {
      parser.advance();
    }
    return md.Element.text(mathDisplayTag, tex);
  }

  /// The TeX and the number of lines it covers, or null when unclosed.
  static (String, int)? _span(md.BlockParser parser) {
    final match = _open.firstMatch(parser.current.content);
    if (match == null) return null;
    final close = match[1] == r'$$' ? r'$$' : r'\]';
    final first = match[2]!.trimRight();
    if (first.endsWith(close)) {
      final tex = first.substring(0, first.length - close.length).trim();
      return tex.isEmpty ? null : (tex, 1);
    }
    final body = <String>[first];
    for (var ahead = 1; ahead <= _maxLines; ahead++) {
      final line = parser.peek(ahead);
      if (line == null) return null;
      final text = line.content.trimRight();
      if (text.endsWith(close)) {
        body.add(text.substring(0, text.length - close.length));
        final tex = body.join('\n').trim();
        return tex.isEmpty ? null : (tex, ahead + 1);
      }
      body.add(text);
    }
    return null;
  }
}
