// lib/design/components/markdown_syntax.dart
/// The Markdown Iris reads: GitHub's web flavour (tables, task lists,
/// footnotes, alerts, emoji) plus the few HTML tags agents use for
/// typography. Plain Dart, so it is tested without widgets.
library;

import 'package:markdown/markdown.dart' as md;

/// Inline syntaxes tried before GitHub's own, in order.
final List<md.InlineSyntax> irisInlineSyntaxes = [TypographyHtmlSyntax()];

/// Block syntaxes tried before GitHub's own, in order.
final List<md.BlockSyntax> irisBlockSyntaxes = [];

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
