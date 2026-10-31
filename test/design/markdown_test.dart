/// Markdown as the agent writes it, drawn with Iris's type.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/markdown.dart';
import 'package:iris/design/components/markdown_image.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/code_colors.dart';
import 'package:iris/design/tokens/palette.dart';

import '../support/harness.dart';

List<TextSpan> spansOf(WidgetTester tester, Finder finder) {
  final spans = <TextSpan>[];
  tester.widget<Text>(finder).textSpan!.visitChildren((span) {
    if (span is TextSpan && span.text != null) spans.add(span);
    return true;
  });
  return spans;
}

void main() {
  testWidgets('headings, emphasis and inline code', (tester) async {
    await tester.pumpWidget(
      themed(
        const IrisMarkdown(
          '# Plan\n\nDo **this** & *that* with `flutter test`.',
        ),
      ),
    );
    expect(find.text('Plan', findRichText: true), findsOneWidget);
    expect(
      find.text('Do this & that with flutter test.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('bulleted, numbered and task lists', (tester) async {
    await tester.pumpWidget(
      themed(
        const IrisMarkdown(
          '- one\n- two\n\n1. first\n2. second\n\n- [x] done\n- [ ] todo',
        ),
      ),
    );
    for (final item in ['one', 'two', 'first', 'second', 'done', 'todo']) {
      expect(find.text(item, findRichText: true), findsOneWidget);
    }
  });

  testWidgets('a fenced code block keeps its text', (tester) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown('```dart\nvoid main() {}\n```')),
    );
    // Dart is highlighted, so the line is several spans of one rich text.
    expect(find.text('void main() {}', findRichText: true), findsOneWidget);
  });

  testWidgets('a table becomes a table', (tester) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown('| a | b |\n|---|---|\n| 1 | 2 |')),
    );
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('1', findRichText: true), findsOneWidget);
    expect(find.text('b', findRichText: true), findsOneWidget);
  });

  testWidgets('a quote and a rule render', (tester) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown('> quoted\n\n---\n\nafter')),
    );
    expect(find.text('quoted', findRichText: true), findsOneWidget);
    expect(find.text('after', findRichText: true), findsOneWidget);
  });

  testWidgets('links report their target when tapped', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      themed(
        IrisMarkdown(
          'See [the docs](https://example.com) and https://auto.link',
          onTapLink: (href) => tapped = href,
        ),
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('the docs'));
    expect(tapped, 'https://example.com');
    await tester.tapOnText(find.textRange.ofSubstring('https://auto.link'));
    expect(tapped, 'https://auto.link');
  });

  testWidgets('unfinished markup still renders', (tester) async {
    // Replies stream token by token, so half-written Markdown is normal.
    await tester.pumpWidget(themed(const IrisMarkdown('**unclosed and `open')));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('unclosed', findRichText: true), findsOneWidget);
  });

  testWidgets('a code block names its language and copies on tap', (
    tester,
  ) async {
    // Clipboard is a platform channel. Capture what would have been copied so
    // the test can assert on it rather than on the device's clipboard.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      themed(const IrisMarkdown('```yaml\nheartbeat:\n  interval: 30s\n```')),
    );
    expect(find.text('yaml'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied.single, 'heartbeat:\n  interval: 30s');
    expect(find.text('Copied'), findsOneWidget);

    // The label reverts after 1.4s, and the timer is cancelled on dispose.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Copy'), findsOneWidget);
  });

  group('highlighting', () {
    test('a clear unlabelled block is detected; a vague one is not', () {
      expect(
        detectLanguage(
          'def greet(name):\n    print(f"hi {name}")\n\nfor i in range(3):\n    greet(i)\n',
        ),
        'python',
      );
      expect(
        detectLanguage(
          'SELECT id, name FROM users WHERE active = 1 ORDER BY name;',
        ),
        'sql',
      );
      expect(detectLanguage('hello there'), isNull);
      expect(detectLanguage('x'), isNull);
    });

    testWidgets('a finished unlabelled block is coloured and named', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(
          const IrisMarkdown(
            '```\ndef greet(name):\n    print(f"hi {name}")\n\nfor i in range(3):\n    greet(i)\n```',
          ),
        ),
      );
      expect(find.byKey(const ValueKey('highlighted')), findsOneWidget);
      expect(find.text('python'), findsOneWidget);
    });

    test('fence names resolve through aliases; unknown ones do not', () {
      expect(highlightLanguage('sh'), 'bash');
      expect(highlightLanguage('zsh'), 'bash');
      expect(highlightLanguage('py'), 'python');
      expect(highlightLanguage('ts'), 'typescript');
      expect(highlightLanguage('yml'), 'yaml');
      expect(highlightLanguage('Dart'), 'dart');
      expect(highlightLanguage('nonsense-lang'), isNull);
      expect(highlightLanguage(null), isNull);
    });

    /// The code block's text, as the span it was drawn with.
    TextSpan codeSpan(WidgetTester tester, String code) =>
        tester
                .widget<RichText>(
                  find.byWidgetPredicate(
                    (w) => w is RichText && w.text.toPlainText() == code,
                  ),
                )
                .text
            as TextSpan;

    testWidgets('a known language is coloured in several roles', (
      tester,
    ) async {
      const code = "final x = 'hi'; // note";
      await tester.pumpWidget(
        themed(const IrisMarkdown('```dart\n$code\n```')),
      );
      await tester.pumpAndSettle();
      final colours = <Color?>{};
      codeSpan(tester, code).visitChildren((span) {
        if (span is TextSpan) colours.add(span.style?.color);
        return true;
      });
      expect(colours.whereType<Color>().length, greaterThanOrEqualTo(3));
    });

    testWidgets('no language, or a reply still arriving, stays plain', (
      tester,
    ) async {
      const code = "final x = 'hi';";
      await tester.pumpWidget(themed(const IrisMarkdown('```\n$code\n```')));
      await tester.pumpAndSettle();
      expect(codeSpan(tester, code).children, isNull);
      await tester.pumpWidget(
        themed(const IrisMarkdown('```dart\n$code\n```', highlight: false)),
      );
      await tester.pumpAndSettle();
      expect(codeSpan(tester, code).children, isNull);
    });

    testWidgets('a block past the limit stays plain', (tester) async {
      final code = 'a' * (maxHighlightLength + 1);
      await tester.pumpWidget(themed(IrisMarkdown('```dart\n$code\n```')));
      await tester.pumpAndSettle();
      expect(codeSpan(tester, code).children, isNull);
    });
  });

  testWidgets('an alert shows its title and body', (tester) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown('> [!TIP]\n> Use a cache.')),
    );
    expect(find.textContaining('Tip', findRichText: true), findsOneWidget);
    expect(find.text('Use a cache.', findRichText: true), findsOneWidget);
    expect(find.textContaining('[!TIP]', findRichText: true), findsNothing);
  });

  testWidgets('citations render without throwing', (tester) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown('Revenue grew. [1] [2]')),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Revenue grew.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('an image waits for a tap before loading', (tester) async {
    await tester.pumpWidget(
      themed(
        const SingleChildScrollView(
          child: IrisMarkdown('![chart](https://img.example/c.png)'),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('img.example'), findsOneWidget);
    await tester.tap(find.byType(MarkdownImage));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an image inside a sentence is still gated behind a tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const SingleChildScrollView(
          child: IrisMarkdown('See ![chart](https://img.example/c.png) here'),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('Tap to load'), findsOneWidget);
  });

  testWidgets('a non-web image source is not offered', (tester) async {
    await tester.pumpWidget(
      themed(
        const SingleChildScrollView(
          child: IrisMarkdown('![x](file:///etc/passwd)'),
        ),
      ),
    );
    expect(find.byType(MarkdownImage), findsNothing);
  });

  testWidgets('a generated MEDIA image loads in an assistant reply', (
    tester,
  ) async {
    String? requestedPath;
    await tester.pumpWidget(
      themed(
        IrisMarkdown(
          'Here is your dog.\n\nMEDIA:/root/.hermes/cache/dog.png',
          loadMediaImage: (path) async {
            requestedPath = path;
            return base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/2ZkAAAAASUVORK5CYII=',
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(requestedPath, '/root/.hermes/cache/dog.png');
    expect(find.textContaining('Here is your dog.'), findsOneWidget);
    expect(find.textContaining('MEDIA:'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('maths renders as maths, inline and display', (tester) async {
    await tester.pumpWidget(
      themed(
        const IrisMarkdown(
          r'Area $\pi r^2$.'
          '\n\n'
          r'$$'
          '\nE=mc^2\n'
          r'$$',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining(r'\pi', findRichText: true), findsNothing);
    expect(find.textContaining('E=mc', findRichText: true), findsNothing);
  });

  testWidgets('bracket delimiters are maths too', (tester) async {
    await tester.pumpWidget(
      themed(
        const IrisMarkdown(
          r'Inline \(x^2\) and'
          '\n\n'
          r'\['
          '\nR = 1\n'
          r'\]',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining(r'\(', findRichText: true), findsNothing);
    expect(find.textContaining(r'\[', findRichText: true), findsNothing);
  });

  testWidgets('TeX that does not parse does not throw', (tester) async {
    await tester.pumpWidget(themed(const IrisMarkdown(r'$\frac{a}{$')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('physics, units and chemistry lay out, not fall back', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown(r'$\dv{f}{x}$ and $\ce{H2O}$ and $\SI{3}{m}$')),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining(r'\dv', findRichText: true), findsNothing);
    expect(find.textContaining(r'\ce', findRichText: true), findsNothing);
    expect(find.textContaining(r'\SI', findRichText: true), findsNothing);
  });

  testWidgets('a detected language is labelled detected; a fenced one is not', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const IrisMarkdown(
          '```\ndef greet(name):\n    print(f"hi {name}")\n\nfor i in range(3):\n    greet(i)\n```',
        ),
      ),
    );
    expect(find.text('python'), findsOneWidget);
    expect(find.text('detected'), findsOneWidget);
    await tester.pumpWidget(
      themed(const IrisMarkdown('```python\nx = 1\n```')),
    );
    expect(find.text('python'), findsOneWidget);
    expect(find.text('detected'), findsNothing);
  });

  test(
    'syntax colour is accent for keywords, muted for comments, ink for the rest',
    () {
      final colors = IrisCodeColors.of(
        IrisThemeData(skin: IrisSkin.aperture, isDark: true).palette,
      );
      for (final other in [
        colors.string,
        colors.number,
        colors.title,
        colors.type,
        colors.attr,
        colors.meta,
      ]) {
        expect(other, colors.plain);
      }
      expect(colors.keyword, isNot(colors.plain));
      expect(colors.comment, isNot(colors.plain));
      expect(
        colors.addition,
        isNot(colors.plain),
        reason: 'a diff keeps its meaning',
      );
    },
  );

  testWidgets('an unloaded image is a 4:3 card with the host and the action', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: IrisMarkdown('![panel](https://grafana.local/a.png)'),
          ),
        ),
      ),
    );
    expect(find.text('grafana.local'), findsOneWidget);
    expect(find.text('Tap to load'), findsOneWidget);
    final size = tester.getSize(find.byKey(const ValueKey('image-card')));
    expect(size.width / size.height, closeTo(4 / 3, .01));
  });

  testWidgets('a failed image says so and offers Tap to retry', (tester) async {
    // The test binding answers every HTTP request with a failure.
    await tester.pumpWidget(
      themed(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: IrisMarkdown('![panel](https://grafana.local/a.png)'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tap to load'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('Tap to retry'), findsOneWidget);
  });
}
