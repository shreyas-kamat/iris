import 'package:openui_lang/src/source.dart';
import 'package:openui_lang/src/statements.dart';
import 'package:test/test.dart';

List<String> names(String s) => splitStatements(prepareSource(s)).statements.map((x) => x.name).toList();

void main() {
  group('statements', () {
    test('one per line, blank and junk lines skipped', () {
      expect(names('a = 1\n\njunk words\nb = 2'), ['a', 'b']);
    });
    test('continues inside brackets and strings', () {
      expect(names('a = Stack([\n  b,\n  c\n])\nd = "x\ny"\ne = 1'), ['a', 'd', 'e']);
    });
    test('multi-line ternary', () {
      final r = splitStatements('s = \$c > 0\n  ? "a"\n  : "b"\nt = 1');
      expect(r.statements.map((x) => x.name), ['s', 't']);
      expect(r.statements.first.expr.toString(), '(? (> \$c 0) "a" "b")');
    });
    test('next line starting with ? continues', () {
      expect(names('s = x\n? 1 : 2\nt = 3'), ['s', 't']);
    });
    test('kinds', () {
      final k = splitStatements('q = Query("t", {}, {})\nm = Mutation("t", {})\n\$s = 1\nv = Text("a")')
          .statements
          .map((s) => s.kind)
          .toList();
      expect(k, [StatementKind.query, StatementKind.mutation, StatementKind.state, StatementKind.value]);
    });
    test('incomplete flag', () {
      expect(splitStatements('a = Stack([b').incomplete, isTrue);
      expect(splitStatements('a = "ab').incomplete, isTrue);
      expect(splitStatements('a = Stack([b])').incomplete, isFalse);
    });
    test('comments are ignored', () {
      expect(names('a = 1 // x\n# note\nb = "// not a comment"'), ['a', 'b']);
    });
  });

  group('fences', () {
    test('plain text passes through', () {
      expect(prepareSource('  a = 1  '), 'a = 1');
    });
    test('program inside a fence', () {
      expect(prepareSource('Here:\n```openui\nroot = A()\n```\nDone'), 'root = A()');
    });
    test('several fences are joined; the last may be unterminated', () {
      expect(prepareSource('```\na = 1\n```\ntext\n```\nb = 2'), 'a = 1\nb = 2');
    });
    test('a fence line inside a string belongs to the string', () {
      expect(prepareSource('```\na = "x\n```\ny"\n```'), 'a = "x\n```\ny"');
    });
    test('openui-js blocks are skipped', () {
      expect(prepareSource('```openui-js\nvar x = 1\n```\n```\nroot = A()\n```'), 'root = A()');
    });
    test('code may follow the tag', () {
      expect(prepareSource('```openui root = A()\n```'), 'root = A()');
    });
    test('inline code is not a fence', () {
      expect(prepareSource('use ```x``` here\nroot = A()'), 'use ```x``` here\nroot = A()');
    });
    test('marker lines are dropped', () {
      expect(prepareSource(']]>openui:begin\nroot = A()\n]]>openui:end'), 'root = A()');
    });
  });
}
