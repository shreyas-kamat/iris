import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/genui/render/iris_functions.dart';
import 'package:iris/features/genui/render/iris_library.dart';
import 'package:openui_lang/openui_lang.dart';

void main() {
  final now = DateTime.utc(2026, 11, 7, 12);

  group('@Percent', () {
    test('rounds', () {
      expect(percent({'done': 1, 'total': 3}), 33);
      expect(percent({'done': 2, 'total': 3}), 67);
    });
    test('a zero total is 0, not a crash', () {
      expect(percent({'done': 5, 'total': 0}), 0);
    });
    test('wrong types give null', () {
      expect(percent({'done': 'a', 'total': 3}), isNull);
    });
  });

  group('@Money', () {
    test('groups thousands and shows two decimals', () {
      expect(money({'value': 1234.5, 'currency': 'GBP'}), '£1,234.50');
      expect(money({'value': 1234567, 'currency': 'usd'}), r'$1,234,567.00');
    });
    test('negative amounts keep the sign in front', () {
      expect(money({'value': -9.99, 'currency': 'EUR'}), '-€9.99');
    });
    test('whole-unit currencies have no decimals', () {
      expect(money({'value': 1500, 'currency': 'JPY'}), '¥1,500');
    });
    test('an unknown code is printed before the amount', () {
      expect(money({'value': 5, 'currency': 'SEK'}), 'SEK 5.00');
    });
    test('rubbish gives null', () {
      expect(money({'value': double.nan, 'currency': 'GBP'}), isNull);
      expect(money({'value': 1, 'currency': ''}), isNull);
      expect(money({'value': '1', 'currency': 'GBP'}), isNull);
    });
  });

  group('@Ago', () {
    String? at(Object? t) => ago(t, now);

    test('recent', () {
      expect(at('2026-11-07T11:59:30Z'), 'just now');
      expect(at('2026-11-07T11:59:00Z'), '1 minute ago');
    });
    test('minutes, hours, days', () {
      expect(at('2026-11-07T11:30:00Z'), '30 minutes ago');
      expect(at('2026-11-07T09:00:00Z'), '3 hours ago');
      expect(at('2026-11-05T12:00:00Z'), '2 days ago');
    });
    test('months and years', () {
      expect(at('2026-08-07T12:00:00Z'), '3 months ago');
      expect(at('2024-11-07T12:00:00Z'), '2 years ago');
    });
    test('the future', () {
      expect(at('2026-11-07T15:00:00Z'), 'in 3 hours');
    });
    test('epoch seconds and milliseconds', () {
      final seconds =
          DateTime.utc(2026, 11, 7, 9).millisecondsSinceEpoch ~/ 1000;
      expect(at(seconds), '3 hours ago');
      expect(at(seconds * 1000), '3 hours ago');
    });
    test('rubbish gives null', () {
      expect(at('yesterday-ish'), isNull);
      expect(at(null), isNull);
      expect(at(double.infinity), isNull);
    });
  });

  test('the evaluator runs them from a program', () {
    final lib = IrisLibrary.toLibrarySpec();
    final result = parseProgram(
      lib,
      'root = Stack([Progress(@Percent(3, 4)), Text(@Money(12.5, "GBP")), Text(@Ago("2026-11-07T09:00:00Z"))])',
    );
    final root = Evaluator(
      result,
      lib,
      functions: irisFunctions(now: () => now),
    ).evaluateRoot();
    expect(root.errors, isEmpty);
    final kids = (root.root!.props['children']! as List).cast<Element>();
    expect(kids[0].props['value'], 75);
    expect(kids[1].props['value'], '£12.50');
    expect(kids[2].props['value'], '3 hours ago');
  });
}
