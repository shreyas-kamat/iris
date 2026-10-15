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

  group('maths', () {
    List<(String, String)> maths(String source) => [
      for (final e in parse(source))
        if (e.tag == mathInlineTag || e.tag == mathDisplayTag)
          (e.tag, e.textContent),
    ];

    test('inline dollars and parentheses', () {
      expect(maths(r'Area is $\pi r^2$ here'), [(mathInlineTag, r'\pi r^2')]);
      expect(maths(r'Or \(a+b\) too'), [(mathInlineTag, 'a+b')]);
    });

    test('display blocks: dollars, brackets, one line, and a math fence', () {
      expect(maths('\$\$\nE = mc^2\n\$\$'), [(mathDisplayTag, 'E = mc^2')]);
      expect(maths(r'\[x^2\]'), [(mathDisplayTag, 'x^2')]);
      expect(maths(r'$$ \sum_i i $$'), [(mathDisplayTag, r'\sum_i i')]);
    });

    test('prices are not maths', () {
      expect(maths(r'It costs $5 and the plan is $10 a month.'), isEmpty);
      expect(maths(r'Between $ 3 and 4 $'), isEmpty);
      expect(maths(r'$x$5'), isEmpty);
    });

    test('an unclosed display block stays text and keeps what follows', () {
      final nodes = irisDocument().parse('\$\$\n\\frac{a}{\n\nMore text.');
      expect(maths('\$\$\n\\frac{a}{\n\nMore text.'), isEmpty);
      expect(nodes.map((n) => n.textContent).join(), contains('More text.'));
    });

    test('maths inside code stays code', () {
      expect(maths(r'Run `echo $HOME$PATH`'), isEmpty);
    });
  });
}
