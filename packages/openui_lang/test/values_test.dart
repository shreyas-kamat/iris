import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

/// ECMA-262 coercions the language borrows (language.md §3.1).
void main() {
  group('toNumber', () {
    test('numbers, booleans and null', () {
      expect(toNumber(3.5), 3.5);
      expect(toNumber(true), 1);
      expect(toNumber(false), 0);
      expect(toNumber(null), 0);
      expect(toNumber(const [1]), 0);
    });
    test('strings follow StringToNumber, and NaN becomes 0', () {
      expect(toNumber(' 12 '), 12);
      expect(toNumber(''), 0);
      expect(toNumber('1e3'), 1000);
      expect(toNumber('.5'), 0.5);
      expect(toNumber('5.'), 5);
      expect(toNumber('-3'), -3);
      expect(toNumber('0x1F'), 31);
      expect(toNumber('0b101'), 5);
      expect(toNumber('Infinity'), double.infinity);
      expect(toNumber('12abc'), 0);
      expect(toNumber('abc'), 0);
      expect(toNumber('-0x1'), 0, reason: 'a sign is not allowed before a hex literal');
    });
  });

  group('looseEquals', () {
    test('IsLooselyEqual', () {
      expect(looseEquals(5.0, '5'), isTrue);
      expect(looseEquals('', 0.0), isTrue);
      expect(looseEquals(null, 0.0), isFalse);
      expect(looseEquals(null, null), isTrue);
      expect(looseEquals(true, 1.0), isTrue);
      expect(looseEquals(true, '1'), isTrue);
      expect(looseEquals('abc', 0.0), isFalse);
      expect(looseEquals(const [1.0], 1.0), isTrue);
      expect(looseEquals(const <Object?>[], ''), isTrue);
      expect(looseEquals(double.nan, double.nan), isFalse);
      final m = <String, Object?>{};
      expect(looseEquals(m, m), isTrue);
      expect(looseEquals(m, <String, Object?>{}), isFalse);
      expect(looseEquals(5, 5.0), isTrue, reason: 'ints from host data equal doubles');
    });
  });

  group('jsString and truthy', () {
    test('Number::toString and String()', () {
      expect(jsString(2.0), '2');
      expect(jsString(-0.0), '0');
      expect(jsString(0.1 + 0.2), '0.30000000000000004');
      expect(jsString(1e21), '1e+21');
      expect(jsString(123456789012345680000.0), '123456789012345680000');
      expect(jsString(null), 'null');
      expect(jsString(true), 'true');
      expect(jsString(const [1.0, null, 'a']), '1,,a');
      expect(jsString(const {'a': 1}), '[object Object]');
    });
    test('ToBoolean', () {
      for (final v in [null, false, 0.0, -0.0, double.nan, '']) {
        expect(truthy(v), isFalse, reason: '$v');
      }
      for (final v in [true, 1.0, 'x', const <Object?>[], const <String, Object?>{}]) {
        expect(truthy(v), isTrue, reason: '$v');
      }
    });
  });

  group('localeCompare', () {
    test('sorts like the root collation for Latin text', () {
      final xs = ['b', 'B', 'a', 'é', 'Z', 'e', 'E', '10', '9', ' x', 'ä', 'a b'];
      xs.sort(localeCompare);
      expect(xs, [' x', '10', '9', 'a', 'ä', 'a b', 'b', 'B', 'e', 'E', 'é', 'Z']);
    });
  });
}
