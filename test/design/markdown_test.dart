/// Markdown as the agent writes it, drawn with Iris's type.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/markdown.dart';

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
    expect(find.text('Plan'), findsOneWidget);
    const paragraph = 'Do this & that with flutter test.';
    expect(find.text(paragraph), findsOneWidget);
    final spans = spansOf(tester, find.text(paragraph));
    expect(
      spans.firstWhere((s) => s.text == 'this').style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      spans.firstWhere((s) => s.text == 'that').style?.fontStyle,
      FontStyle.italic,
    );
    expect(
      spans.firstWhere((s) => s.text == 'flutter test').style?.backgroundColor,
      isNotNull,
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
    expect(find.text('one'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(4));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.textContaining('☑'), findsOneWidget);
    expect(find.textContaining('☐'), findsOneWidget);
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
    expect(find.text('1'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('a quote and a rule render', (tester) async {
    await tester.pumpWidget(
      themed(const IrisMarkdown('> quoted\n\n---\n\nafter')),
    );
    expect(find.text('quoted'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('after'), findsOneWidget);
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
    final spans = spansOf(tester, find.textContaining('See'));
    final docs = spans.firstWhere((s) => s.text == 'the docs');
    (docs.recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped, 'https://example.com');
    final auto = spans.firstWhere((s) => s.text == 'https://auto.link');
    (auto.recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped, 'https://auto.link');
  });

  testWidgets('unfinished markup still renders', (tester) async {
    // Replies stream token by token, so half-written Markdown is normal.
    await tester.pumpWidget(themed(const IrisMarkdown('**unclosed and `open')));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('unclosed'), findsOneWidget);
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

    testWidgets('a known language is coloured in several roles', (tester) async {
      const code = "final x = 'hi'; // note";
      await tester.pumpWidget(themed(const IrisMarkdown('```dart\n$code\n```')));
      await tester.pumpAndSettle();
      final colours = <Color?>{};
      codeSpan(tester, code).visitChildren((span) {
        if (span is TextSpan) colours.add(span.style?.color);
        return true;
      });
      expect(colours.whereType<Color>().length, greaterThanOrEqualTo(3));
    });

    testWidgets('no language, or a reply still arriving, stays plain', (tester) async {
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
}
