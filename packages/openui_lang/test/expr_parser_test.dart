import 'package:openui_lang/src/expr_parser.dart';
import 'package:openui_lang/src/lexer.dart';
import 'package:test/test.dart';

String ex(String s) => ExprParser(lex(s)).parseExpression().toString();

void main() {
  test('literals and calls', () {
    expect(ex('Text("a", 1, true, null)'), '(Text "a" 1 true null)');
    expect(ex('@Count(x)'), '(@Count x)');
    expect(ex('Action([@Set(\$a, 1)])'), '(Action [(@Set \$a 1)])');
    expect(ex('@Action([a])'), '(Action [a])');
  });
  test('commas are optional and trailing commas ignored', () {
    expect(ex('[1 2, 3,]'), '[1 2 3]');
    expect(ex('Stack([a b],)'), '(Stack [a b])');
  });
  test('precedence and associativity', () {
    expect(ex('1 + 2 * 3 - 4 / 2'), '(- (+ 1 (* 2 3)) (/ 4 2))');
    expect(ex('10 - 2 - 3'), '(- (- 10 2) 3)');
    expect(ex('1 || 2 && 0'), '(|| 1 (&& 2 0))');
    expect(ex('2 > 1 == true'), '(== (> 2 1) true)');
    expect(ex('!!"x" && "ok"'), '(&& (! (! "x")) "ok")');
    expect(ex('-2 * -3'), '(* -2 -3)');
  });
  test('ternary is right-associative', () {
    expect(ex('a ? b : c ? d : e'), '(? a b (? c d e))');
  });
  test('member access and indexing', () {
    expect(ex('m[1][0]'), 'm[1][0]'.replaceAll('m', 'm'));
    expect(ex('o.0'), 'o.0');
    expect(ex('m.0.1'), 'm.0.1');
    expect(ex('a.b.length'), 'a.b.length');
  });
  test('object keys', () {
    expect(ex('{name: "x", "quoted key": 1, 2: "two", \$s: 3, Card: 4}'),
        '{name:"x" quoted key:1 2:"two" s:3 Card:4}');
  });
  test('uppercase bare identifier is a reference', () {
    expect(ex('Foo'), 'Foo');
  });
  test('lowercase name(x) is a reference, arguments lost', () {
    expect(ex('[count(x) 1]'), '[count 1]');
  });
  test('binding assignment', () {
    expect(ex('\$a = 1'), '(= \$a 1)');
  });
  test('implicit closing at end of input', () {
    expect(ex('Stack([a, Text("x'), '(Stack [a (Text "x")])');
  });
  test('statement shape', () {
    final s = ExprParser(lex('root = Stack([a])')).parseStatement()!;
    expect(s.name, 'root');
    expect(s.value.toString(), '(Stack [a])');
    expect(ExprParser(lex('just words')).parseStatement(), isNull);
  });
  test('never throws', () {
    for (var i = 0; i < 300; i++) {
      final s = String.fromCharCodes(List.generate(40, (j) => 32 + (i * 31 + j * 17) % 90));
      expect(() => ExprParser(lex(s)).parseStatement(), returnsNormally);
      expect(() => ExprParser(lex(s)).parseExpression(), returnsNormally);
    }
  });
}
