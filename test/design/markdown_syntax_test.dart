/// The syntaxes Iris adds to GitHub's Markdown.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/markdown_syntax.dart';
import 'package:markdown/markdown.dart' as md;

/// Every element under [nodes], depth first.
Iterable<md.Element> elements(List<md.Node> nodes) sync* {
  for (final node in nodes) {
    if (node is md.Element) {
      yield node;
      yield* elements(node.children ?? const []);
    }
  }
}

List<md.Element> parse(String source) =>
    elements(irisDocument().parse(source)).toList();

void main() {
  test('typography HTML becomes elements, other HTML stays text', () {
    final tags = parse('H<sub>2</sub>O, x<sup>2</sup>, <kbd>Ctrl</kbd>, '
            '<mark>this</mark><br>next <span>raw</span>')
        .map((e) => e.tag)
        .toList();
    expect(tags, containsAll(['sub', 'sup', 'kbd', 'mark', 'br']));
    expect(tags, isNot(contains('span')));
  });

  test('alerts, footnotes and emoji parse', () {
    final alert = parse('> [!WARNING]\n> Mind the gap.')
        .firstWhere((e) => e.tag == 'div');
    expect(alert.attributes['class'], contains('markdown-alert-warning'));
    final notes = parse('Fact.[^1]\n\n[^1]: Source.');
    expect(notes.any((e) => e.attributes['class'] == 'footnote-ref'), isTrue);
    expect(notes.any((e) => e.tag == 'section'), isTrue);
    expect(irisDocument().parse(':tada:').single.textContent, '🎉');
  });
}
