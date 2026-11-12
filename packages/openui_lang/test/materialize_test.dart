import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

Map<String, Object?> _libJson() =>
    (jsonDecode(File('test/fixtures/library.json').readAsStringSync()) as Map).cast<String, Object?>();

final lib = LibrarySpec.fromJson(_libJson());

ParseResult parse(String t, [LibrarySpec? l]) => parseProgram(l ?? lib, t);
List<String> codes(ParseResult r) => r.errors.map((e) => e.code).toList();

void main() {
  group('error codes', () {
    test('unknown-component: dropped, with the available names as hint', () {
      final r = parse('root = Stack([Text("a"), Chart(1)])');
      expect(codes(r), ['unknown-component']);
      expect(r.errors.single.component, 'Chart');
      expect(r.errors.single.statementId, 'root');
      expect(r.errors.single.hint, contains('Stack'));
      expect(r.summary()!['props'], {
        'children': [
          {'type': 'Text', 'props': {'text': 'a'}},
        ],
      });
    });
    test('missing-required: component dropped, with signature hint and path', () {
      final r = parse('root = Stack([Metric("x"), Text("a")])');
      final e = r.errors.single;
      expect([e.code, e.component, e.path], ['missing-required', 'Metric', '/value']);
      expect(e.hint, 'Signature: Metric(label*, value*). * marks required');
    });
    test('missing-required is filled from the schema default', () {
      final j = _libJson();
      final defs = (j['schema']! as Map)[r'$defs'] as Map;
      ((defs['Metric'] as Map)['properties'] as Map)['value'] = {'type': 'number', 'default': 0};
      final r = parse('root = Stack([Metric("x")])', LibrarySpec.fromJson(j));
      expect(r.errors, isEmpty);
      expect(((r.summary()!['props'] as Map)['children'] as List).single, {
        'type': 'Metric',
        'props': {'label': 'x', 'value': 0},
      });
    });
    test('null-required', () {
      expect(codes(parse('root = Stack([Text(null)])')), ['null-required']);
    });
    test('type-mismatch: enum value, optional prop removed, component renders', () {
      final r = parse('root = Stack([Tag("x", "purple")])');
      expect(codes(r), ['type-mismatch']);
      expect(r.errors.single.path, '/color');
      expect(((r.summary()!['props'] as Map)['children'] as List).single, {
        'type': 'Tag',
        'props': {'text': 'x'},
      });
    });
    test('type-mismatch on a required scalar drops the component', () {
      final r = parse('root = Stack([Text(5), Text("ok")])');
      expect(codes(r), ['type-mismatch']);
      expect(((r.summary()!['props'] as Map)['children'] as List).length, 1);
    });
    test('type-mismatch: data in a component slot is left out, one error each', () {
      final r = parse('root = Stack(["plain", {a: 1}, Text("a")])');
      expect(codes(r), ['type-mismatch', 'type-mismatch']);
      expect(r.errors.map((e) => e.path), ['/children/0', '/children/1']);
    });
    test('excess-args: extra arguments dropped, component renders', () {
      final r = parse('root = Stack([Text("a", "body", "x")])');
      expect(codes(r), ['excess-args']);
      expect(((r.summary()!['props'] as Map)['children'] as List).single, {
        'type': 'Text',
        'props': {'text': 'a', 'variant': 'body'},
      });
    });
    test('inline-reserved: Query in a value position', () {
      final r = parse('root = Stack([Query("t", {}, {})])');
      expect(codes(r), ['inline-reserved']);
      expect(r.errors.single.statementId, 'root');
    });
    test('inline-reserved does not fire in a computed expression', () {
      final r = parse('root = Stack([Text("a" + Query("t", {}, {}))])');
      expect(r.errors, isEmpty);
    });
    test('unknown-function: statement kept', () {
      final r = parse('root = Stack([t])\nt = Text(@Nope(1))');
      expect(codes(r), ['unknown-function']);
    });
    test('no-root: fatal when nothing is an entry', () {
      final r = parse('t = Text("a")');
      expect(codes(r), ['no-root']);
      expect(r.errors.single.isFatal, isTrue);
      expect(r.tree, isNull);
    });
    test('no-root: a warning, and the page renders, when the fallback entry is used', () {
      final r = parse('page = Stack([Text("a")])');
      expect(codes(r), ['no-root']);
      expect(r.errors.single.isFatal, isFalse);
      expect(r.errors.single.toJson()['severity'], 'warning');
      expect(r.tree, isNotNull);
    });
    test('parse-failed: text but no statements', () {
      final r = parse('hello there, no program');
      expect(codes(r), ['parse-failed']);
      expect(r.hasFatalError, isTrue);
    });
    test('empty input has no errors', () {
      expect(parse('   ').errors, isEmpty);
    });
    test('error object shape', () {
      final j = parse('root = Stack([Metric("x")])').errors.single.toJson();
      expect(j.keys, containsAll(['source', 'code', 'statementId', 'component', 'path', 'message', 'hint']));
      expect(j['source'], 'parser');
    });
  });

  group('props and references', () {
    test('positional arguments map to named props in order; null skips an optional', () {
      final r = parse('root = Stack([Button("Go", null, "primary")])');
      expect(((r.summary()!['props'] as Map)['children'] as List).single, {
        'type': 'Button',
        'props': {'label': 'Go', 'variant': 'primary'},
      });
    });
    test('a bindable prop given a state variable is a binding', () {
      final r = parse('root = Stack([Input("q", "Search", \$q)])\n\$q = ""');
      expect(((r.summary()!['props'] as Map)['children'] as List).single, {
        'type': 'Input',
        'props': {
          'name': 'q',
          'placeholder': 'Search',
          'value': {r'$binding': r'$q'},
        },
      });
    });
    test('references resolve wherever the statement is (hoisting)', () {
      final r = parse('root = Stack([later])\nlater = Text("x")');
      expect(r.errors, isEmpty);
      expect(((r.summary()!['props'] as Map)['children'] as List).length, 1);
    });
    test('unresolved references are left out of arrays and reported in metadata, not errors', () {
      final r = parse('root = Stack([Text("a"), nope])');
      expect(r.errors, isEmpty);
      expect(r.unresolved, {'nope'});
      expect(((r.summary()!['props'] as Map)['children'] as List).length, 1);
    });
    test('a reference that closes a cycle is unresolved', () {
      final r = parse('root = Stack([a])\na = Stack([b])\nb = Stack([a])');
      expect(r.unresolved, {'a'});
    });
    test('a statement referenced twice is built twice', () {
      final r = parse('root = Stack([t, t])\nt = Text("x")');
      final children = (r.summary()!['props'] as Map)['children'] as List;
      expect(children.length, 2);
    });
    test('incomplete when input ends in an open bracket', () {
      expect(parse('root = Stack([Text("a"').incomplete, isTrue);
      expect(parse('root = Stack([])').incomplete, isFalse);
    });
    test('never throws on arbitrary text', () {
      for (var i = 0; i < 200; i++) {
        final s = String.fromCharCodes(List.generate(60, (j) => 32 + (i * 13 + j * 7) % 90));
        expect(() => parse(s), returnsNormally);
        expect(() => parse('root = Stack([$s])'), returnsNormally);
      }
    });
  });
}
