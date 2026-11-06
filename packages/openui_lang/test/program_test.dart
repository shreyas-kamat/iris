import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:openui_lang/src/ast.dart';
import 'package:openui_lang/src/expr_parser.dart';
import 'package:openui_lang/src/lexer.dart';
import 'package:openui_lang/src/program.dart';
import 'package:openui_lang/src/source.dart';
import 'package:openui_lang/src/statements.dart';
import 'package:test/test.dart';

final lib = LibrarySpec.fromJson((jsonDecode(File('test/fixtures/library.json').readAsStringSync()) as Map).cast());

Program build(String text) {
  final r = splitStatements(prepareSource(text));
  return Program.build(r.statements, lib, incomplete: r.incomplete);
}

void main() {
  test('root statement is the entry', () {
    final p = build('root = Stack([t])\nt = Text("a")');
    expect(p.entry, 'root');
    expect(p.entryIsFallback, isFalse);
    expect(p.orphans, isEmpty);
  });
  test('no root: first value statement calling the library root, wherever it is', () {
    final p = build('t = Text("a")\npage = Stack([t])');
    expect(p.entry, 'page');
    expect(p.entryIsFallback, isTrue);
  });
  test('state declarations are never the entry', () {
    final p = build('\$tab = Stack([])\npage = Stack([])');
    expect(p.entry, 'page');
  });
  test('no entry when nothing calls the root component', () {
    final p = build('t = Text("a")');
    expect(p.entry, isNull);
    expect(p.orphans, isEmpty);
  });
  test('later duplicate wins', () {
    final p = build('root = Stack([t])\nt = Text("first")\nt = Text("second")');
    expect(p.statements['t']!.expr.toString(), '(Text "second")');
  });
  test('orphans: unreachable value statements only', () {
    final p = build('root = Stack([a])\na = Text("a")\nb = Text("b")\n\$s = 1\nq = Query("t", {}, {rows: []})');
    expect(p.orphans, {'b'});
  });
  test('a statement referenced from a query is not an orphan', () {
    final p = build('root = Stack([])\nargs = {x: 1}\nq = Query("t", args, {})');
    expect(p.orphans, isEmpty);
  });
  test('referencedNames skips state names and @Each loop variables', () {
    final e = ExprParser(lex('@Each(rows, "t", Text(t.title, label))')).parseExpression();
    expect(referencedNames(e), {'rows', 'label'});
    expect(referencedNames(const RefExpr(r'$x')), isEmpty);
  });
}
