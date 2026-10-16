import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/prefs/json_list.dart';

void main() {
  test('round-trips a list', () {
    expect(decodeStringList(encodeStringList(['a', 'b'])), ['a', 'b']);
  });

  test('an empty list is stored as no value at all', () {
    expect(encodeStringList(const []), isNull);
  });

  test('damaged or missing values decode to empty, never throw', () {
    expect(decodeStringList(null), isEmpty);
    expect(decodeStringList(''), isEmpty);
    expect(decodeStringList('not json'), isEmpty);
    expect(decodeStringList('{"a":1}'), isEmpty);
  });

  test('non-string and blank entries are dropped, duplicates collapse in order', () {
    expect(decodeStringList('["a", 3, "", "a", "b", null]'), ['a', 'b']);
  });
}
