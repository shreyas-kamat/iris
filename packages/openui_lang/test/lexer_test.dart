import 'package:openui_lang/src/lexer.dart';
import 'package:test/test.dart';

List<String> kinds(String s) => lex(s).map((t) => t.kind.name).toList();
List<Object?> values(String s) => lex(s).where((t) => t.kind != TokenKind.eof).map((t) => t.value ?? t.kind.name).toList();

void main() {
  group('identifiers', () {
    test('component, reference, state, builtin', () {
      expect(kinds('Stack foo _x \$count @Sum'), ['component', 'reference', 'reference', 'stateName', 'builtin', 'eof']);
      expect(values('Stack foo \$count @Sum'), ['Stack', 'foo', r'$count', 'Sum']);
    });
    test('keywords', () {
      expect(kinds('true false null'), ['trueKw', 'falseKw', 'nullKw', 'eof']);
    });
    test('a bare \$ or @ is skipped', () {
      expect(kinds(r'$ @ x'), ['reference', 'eof']);
    });
  });

  group('strings', () {
    test('JSON escapes in double quotes', () {
      expect(values(r'"q\"d\b\ttA"'), ['q"d\b\ttA']);
    });
    test('single-quote escapes; others pass through', () {
      expect(values(r"'it\'s' 'x\ny' 'a\qb'"), ["it's", 'x\ny', 'aqb']);
    });
    test('unterminated strings close implicitly', () {
      expect(values('"abc'), ['abc']);
      expect(values("'abc"), ['abc']);
      expect(values(r'"ab\'), ['ab']);
    });
    test('a malformed unicode escape does not throw', () {
      expect(() => lex(r'"\u00'), returnsNormally);
    });
    test('raw newlines are kept inside strings', () {
      expect(values('"a\nb"'), ['a\nb']);
    });
  });

  group('numbers', () {
    test('forms', () {
      expect(values('1 (-2) 1.5 1e3 2E-2 0.25'), [1, 'lParen', -2, 'rParen', 1.5, 1000, 0.02, 0.25]);
    });
    test('a dot needs a digit after it', () {
      expect(kinds('1.x'), ['number', 'dot', 'reference', 'eof']);
    });
    test('minus after a value is subtraction, after a comma a sign', () {
      expect(kinds('1 -2'), ['number', 'minus', 'number', 'eof']);
      expect(kinds('[1 -2]'), ['lBracket', 'number', 'minus', 'number', 'rBracket', 'eof']);
      expect(kinds(', -5'), ['comma', 'number', 'eof']);
      expect(values(', -5'), ['comma', -5]);
    });
    test('minus after } is a sign', () {
      expect(values('} -5'), ['rBrace', -5]);
    });
    test('minus not followed by a digit is an operator', () {
      expect(kinds('- x'), ['minus', 'reference', 'eof']);
    });
    test('dangling exponent is not a usable number', () {
      final v = lex('1e').first.value as double;
      expect(v.isNaN, isTrue);
    });
  });

  group('operators', () {
    test('all', () {
      expect(
        kinds('= == != > < >= <= + - * / % && || ! ? : . , ( ) [ ] { }'),
        [
          'assign', 'eq', 'neq', 'gt', 'lt', 'gte', 'lte', 'plus', 'minus', 'star', 'slash', 'percent',
          'and', 'or', 'not', 'question', 'colon', 'dot', 'comma', 'lParen', 'rParen', 'lBracket', 'rBracket',
          'lBrace', 'rBrace', 'eof',
        ],
      );
    });
    test('single & and | mean && and ||', () {
      expect(kinds('a & b | c'), ['reference', 'and', 'reference', 'or', 'reference', 'eof']);
    });
  });

  group('whitespace, comments and unknown characters', () {
    test('newline token, \r consumed with it', () {
      expect(kinds('a\r\nb'), ['reference', 'newline', 'reference', 'eof']);
    });
    test('// and # comments run to end of line; markers in strings are kept', () {
      expect(kinds('a // c\nb # d\nc'), ['reference', 'newline', 'reference', 'newline', 'reference', 'eof']);
      expect(values('"a // b # c"'), ['a // b # c']);
    });
    test('slash is division when not a comment', () {
      expect(kinds('a / b'), ['reference', 'slash', 'reference', 'eof']);
    });
    test('unknown characters are skipped', () {
      expect(kinds('a;b'), ['reference', 'reference', 'eof']);
      expect(kinds('a 🙂 b'), ['reference', 'reference', 'eof']);
    });
    test('never throws on arbitrary bytes', () {
      for (var i = 0; i < 300; i++) {
        final s = String.fromCharCodes(List.generate(40, (j) => (i * 31 + j * 17) % 255));
        expect(() => lex(s), returnsNormally);
      }
    });
  });

  test('tokens carry their source offset', () {
    final t = lex('ab = 12');
    expect(t.map((x) => x.start).toList(), [0, 3, 5, 7]);
  });
}
