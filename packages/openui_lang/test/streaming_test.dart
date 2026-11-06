import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

/// Streaming parser (language.md §4). The property tests feed every fixture program a character at a time and at
/// every two-chunk split; the result at stream end must equal a batch parse.
void main() {
  final root = Directory('test/fixtures');
  final library = LibrarySpec.fromJson(
    (jsonDecode(File('${root.path}/library.json').readAsStringSync()) as Map).cast<String, Object?>(),
  );

  group('closeImplicitly', () {
    test('closes brackets in reverse order', () {
      expect(closeImplicitly('x = A([1, (2'), (text: 'x = A([1, (2)])', closed: true));
    });
    test('closes a string, then brackets', () {
      expect(closeImplicitly('x = A("ab'), (text: 'x = A("ab")', closed: true));
      expect(closeImplicitly("x = A('ab"), (text: "x = A('ab')", closed: true));
    });
    test('adds a backslash when the text ends mid-escape', () {
      expect(closeImplicitly(r'x = A("a\'), (text: r'x = A("a\\")', closed: true));
      expect(closeImplicitly(r'x = A("a\\'), (text: r'x = A("a\\")', closed: true));
    });
    test('skips a closer that does not match', () {
      expect(closeImplicitly('x = A(]'), (text: 'x = A(])', closed: true));
    });
    test('ignores brackets and quotes in comments, and closes on a new line after one', () {
      expect(closeImplicitly('x = A( // ("['), (text: 'x = A( // ("[\n)', closed: true));
      expect(closeImplicitly('x = A( # ['), (text: 'x = A( # [\n)', closed: true));
    });
    test('leaves complete text alone', () {
      expect(closeImplicitly('x = A("(", [1])'), (text: 'x = A("(", [1])', closed: false));
    });
  });

  group('frames', () {
    List<String> chunks(String fixture) =>
        (jsonDecode(File('${root.path}/streaming/$fixture/chunks.json').readAsStringSync()) as List).cast<String>();

    test('the worked example renders a valid page after every chunk (Appendix A)', () {
      final c = chunks('001-worked-example');
      final p = StreamingParser(library);
      var text = '';

      text += c[0];
      var r = p.set(text);
      expect(r.summary(), {
        'type': 'Stack',
        'props': {'children': <Object?>[]},
      });
      expect(r.errors, isEmpty);

      text += c[1];
      r = p.set(text);
      expect(r.summary(), {
        'type': 'Stack',
        'props': {
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Tickets', 'variant': 'heading'},
            },
            {
              'type': 'Stack',
              'props': {'children': <Object?>[]},
            },
          ],
        },
      });
      expect(r.errors, isEmpty);
      expect(r.unresolved, contains('open'));

      text += c[2];
      r = p.set(text);
      final kids = ((r.summary()!['props'] as Map)['children'] as List);
      expect((kids[1] as Map)['props'], {
        'children': [
          {
            'type': 'Metric',
            'props': {'label': 'Open', 'value': deferredMarker},
          },
        ],
      });
      expect(r.errors, isEmpty);
      expect(r.unresolved, containsAll(['closed', 'tickets']));

      text += c[3];
      p.set(text);
      final end = p.end();
      final batch = parseProgram(library, text);
      _expectSame(end, batch);
      expect(end.errors, isEmpty);
      expect(end.unresolved, isEmpty);
    });

    test('a multi-line ternary does not complete early', () {
      final p = StreamingParser(library);
      var text = '';
      for (final c in chunks('003-multiline-ternary-across-chunks')) {
        text += c;
        p.set(text);
        expect(p.completedNames, isNot(contains('s')));
      }
      expect(p.end().statementCount, 3);
    });

    test('a late fence makes the client parse again from the start', () {
      final p = StreamingParser(library);
      var text = '';
      final c = chunks('005-fence-arrives-late');
      text += c[0];
      expect(p.set(text).tree, isNull);
      expect(p.set(text).errors, isEmpty, reason: 'parse-failed waits for the stream end');
      text += c[1];
      expect(p.set(text).summary(), isNotNull);
      text += c[2];
      p.set(text);
      _expectSame(p.end(), parseProgram(library, text));
    });

    test('a pending statement that needed closing does not replace a completed one', () {
      final p = StreamingParser(library);
      const done = 'root = Stack([a])\na = Text("x")\n';
      var r = p.set('${done}a = Text("y');
      expect(_firstText(r), 'x');
      r = p.set('${done}a = Text("y")');
      expect(_firstText(r), 'y', reason: 'a pending statement that needed no closing is a later definition');
      p.set('${done}a = Text("y');
      expect(_firstText(p.end()), 'y', reason: 'the stream end completes the redefinition');
    });

    test('a missing entry is not an error while streaming, and is at the end', () {
      final p = StreamingParser(library);
      expect(p.set('a = Text("x")\n').errors, isEmpty);
      expect(p.end().errors.map((e) => e.code), [ErrorCode.noRoot]);
    });

    test('enum checks wait for the stream end', () {
      final p = StreamingParser(library);
      final r = p.set('root = Stack([Text("x", "hea');
      expect(r.errors, isEmpty);
      expect(r.incomplete, isTrue);
      final e = p.end();
      expect(e.errors.map((x) => x.code), [ErrorCode.typeMismatch]);
    });

    test('completed statements are parsed once', () {
      final p = StreamingParser(library);
      p.set('root = Stack([a])\na = Text("x")\nb = T');
      expect(p.completedNames, ['root', 'a']);
      p.set('root = Stack([a])\na = Text("x")\nb = Text("y")\nc = T');
      expect(p.completedNames, ['root', 'a', 'b']);
    });

    test('a slash that may still become a comment does not complete the line before it', () {
      final p = StreamingParser(library);
      p.set('root = Stack([])\n/');
      expect(p.completedNames, isEmpty);
    });

    test('chunks after the end are a new stream', () {
      final p = StreamingParser(library);
      p.set('root = Stack([Text("a")])\n');
      p.end();
      final r = p.set('root = Stack([Text("b")])\nx');
      expect(_firstText(r), 'b');
    });
  });

  group('streaming equals parsing', () {
    final programs = <String, String>{};
    for (final area in root.listSync().whereType<Directory>()) {
      if (area.path.endsWith('editing')) continue;
      for (final dir in area.listSync().whereType<Directory>()) {
        final name = dir.path.replaceAll(r'\', '/').replaceFirst('test/fixtures/', '');
        final input = File('${dir.path}/input.oui');
        final chunks = File('${dir.path}/chunks.json');
        if (input.existsSync()) programs[name] = input.readAsStringSync();
        if (chunks.existsSync()) {
          programs[name] = (jsonDecode(chunks.readAsStringSync()) as List).cast<String>().join();
        }
      }
    }

    test('there are fixture programs to stream', () => expect(programs.length, greaterThan(40)));

    for (final MapEntry(key: name, value: text) in programs.entries) {
      test('$name, a character at a time', () {
        final batch = parseProgram(library, text);
        final p = StreamingParser(library);
        for (var k = 0; k <= text.length; k++) {
          final r = p.set(text.substring(0, k));
          expect(r.errors.where((e) => e.code == ErrorCode.parseException), isEmpty, reason: 'prefix $k');
        }
        _expectSame(p.end(), batch);
      });

      test('$name, split in two at every boundary', () {
        final batch = parseProgram(library, text);
        for (var k = 0; k <= text.length; k++) {
          final p = StreamingParser(library)..set(text.substring(0, k));
          p.set(text);
          _expectSame(p.end(), batch, at: k);
        }
      });
    }
  });
}

String? _firstText(ParseResult r) {
  final kids = (r.summary()?['props'] as Map?)?['children'] as List?;
  if (kids == null || kids.isEmpty) return null;
  return ((kids.first as Map)['props'] as Map)['text'] as String?;
}

void _expectSame(ParseResult a, ParseResult b, {int? at}) {
  final why = at == null ? '' : ' (split at $at)';
  expect(a.summary(), equals(b.summary()), reason: 'tree$why');
  expect(a.errors.map(_key).toList()..sort(), equals(b.errors.map(_key).toList()..sort()), reason: 'errors$why');
  expect(a.unresolved, equals(b.unresolved), reason: 'unresolved$why');
  expect(a.orphans, equals(b.orphans), reason: 'orphans$why');
  expect(a.incomplete, equals(b.incomplete), reason: 'incomplete$why');
  expect(a.statementCount, equals(b.statementCount), reason: 'statementCount$why');
  expect(a.program?.entry, equals(b.program?.entry), reason: 'entry$why');
}

String _key(OpenUiError e) => '${e.code}|${e.statementId}|${e.path}|${e.component}|${e.warning}';
