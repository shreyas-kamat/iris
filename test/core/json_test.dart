import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';

void main() {
  group('navigation never throws', () {
    test('missing keys yield Json.missing rather than an error', () {
      final json = Json.of({'a': 1});
      expect(json['nope'].exists, isFalse);
      expect(json['nope'].isNull, isTrue);
      expect(json['nope'].string('fallback'), 'fallback');
    });

    test('a deep path over the wrong shape degrades to a fallback', () {
      final json = Json.of({'session': 'not-an-object'});
      expect(json['session']['messages'].at(3)['role'].string('?'), '?');
    });

    test('indexing a list out of range yields missing', () {
      final json = Json.of([1, 2, 3]);
      expect(json.at(9).exists, isFalse);
      expect(json.at(-1).integer(), 3, reason: 'negative counts from the end');
      expect(json.at(-4).exists, isFalse);
    });

    test('invalid JSON decodes to missing instead of throwing', () {
      expect(Json.decode('<html>502 Bad Gateway</html>').exists, isFalse);
      expect(Json.decode('').exists, isFalse);
    });

    test('a present null is distinguishable from an absent key', () {
      final json = Json.of({'title': null});
      expect(json['title'].exists, isTrue);
      expect(json['title'].isNull, isTrue);
      expect(json['absent'].exists, isFalse);
    });
  });

  group('scalar coercion', () {
    test('strings coerce from numbers and bools but not collections', () {
      expect(Json.of(42).string(), '42');
      expect(Json.of(1.5).string(), '1.5');
      expect(Json.of(true).string(), 'true');
      expect(Json.of({'a': 1}).string('fb'), 'fb');
      expect(Json.of([1]).string('fb'), 'fb');
    });

    test('ints parse from strings and truncate doubles', () {
      expect(Json.of('42').integer(), 42);
      expect(Json.of('42.9').integer(), 42);
      expect(Json.of(42.9).integer(), 42);
      expect(Json.of(true).integer(), 1);
      expect(Json.of('not a number').integer(-1), -1);
      expect(Json.of(double.nan).intOrNull, isNull);
    });

    test('bools accept the spellings servers actually send', () {
      for (final truthy in <Object>[
        true,
        1,
        'true',
        'TRUE',
        'yes',
        'on',
        '1',
      ]) {
        expect(Json.of(truthy).boolean(), isTrue, reason: '$truthy');
      }
      for (final falsy in <Object>[false, 0, 'false', 'no', 'off', '0', '']) {
        expect(Json.of(falsy).boolean(true), isFalse, reason: '$falsy');
      }
      expect(Json.of('maybe').boolOrNull, isNull);
    });
  });

  group('timestamps', () {
    // The session list sends fractional epoch seconds; other payloads have been
    // seen using milliseconds and ISO-8601. All three must land on the same
    // instant so sorting a mixed list is stable.
    final expected = DateTime.fromMillisecondsSinceEpoch(1711829408123);

    test('fractional epoch seconds', () {
      expect(Json.of(1711829408.123).dateTimeOrNull, expected);
    });

    test('epoch milliseconds', () {
      expect(Json.of(1711829408123).dateTimeOrNull, expected);
    });

    test('ISO-8601 strings', () {
      final iso = expected.toUtc().toIso8601String();
      expect(Json.of(iso).dateTimeOrNull, expected);
    });

    test('numeric strings', () {
      expect(Json.of('1711829408.123').dateTimeOrNull, expected);
    });

    test('unparseable values yield null, not an epoch-zero date', () {
      expect(Json.of('tomorrow').dateTimeOrNull, isNull);
      expect(Json.of('').dateTimeOrNull, isNull);
      expect(Json.of(null).dateTimeOrNull, isNull);
      expect(Json.of(double.infinity).dateTimeOrNull, isNull);
    });
  });

  group('field aliasing', () {
    test('any() takes the first key that holds a value', () {
      final renamed = Json.of({'tool_name': 'terminal'});
      final original = Json.of({'name': 'terminal'});
      const keys = ['name', 'tool_name'];
      expect(renamed.any(keys).string(), 'terminal');
      expect(original.any(keys).string(), 'terminal');
    });

    test('any() skips keys present but null', () {
      final json = Json.of({'name': null, 'tool_name': 'grep'});
      expect(json.any(['name', 'tool_name']).string(), 'grep');
    });
  });

  group('collections', () {
    test('list over a non-list is empty rather than throwing', () {
      expect(Json.of({'a': 1}).list, isEmpty);
      expect(Json.of('text').list, isEmpty);
    });

    test('listOrSingle wraps a lone value but not a null', () {
      expect(Json.of('one').listOrSingle, hasLength(1));
      expect(Json.of(null).listOrSingle, isEmpty);
      expect(Json.of([1, 2]).listOrSingle, hasLength(2));
    });

    test('mapList drops malformed elements instead of the whole response', () {
      final json = Json.of([
        {'id': 'a'},
        'garbage',
        {'id': 'b'},
        {'nope': 1},
      ]);
      final ids = json.mapList((element) => element['id'].stringOrNull);
      expect(ids, ['a', 'b']);
    });

    test('map keys survive non-string keys', () {
      final json = Json.of(<dynamic, dynamic>{1: 'a', 'b': 2});
      expect(json.keys, ['1', 'b']);
      expect(json.map['1']!.string(), 'a');
    });
  });

  test('unknown fields are preserved for pass-through and debug surfaces', () {
    // The core promise: a payload with fields this build has never heard of
    // still decodes, and the raw form remains available to show the user.
    final json = Json.decode('{"text":"hi","future_field":{"deep":[1,2]}}');
    expect(json['text'].string(), 'hi');
    expect(json['future_field']['deep'].at(1).integer(), 2);
    expect(json.encode(), contains('future_field'));
  });
}
