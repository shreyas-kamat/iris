import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/search_merge.dart';

void main() {
  SearchHit hit(String id, DateTime? at) =>
      SearchHit(storedId: id, title: id, lastActive: at);

  test('every hit is labelled with the profile it came from', () {
    final merged = mergeProfileHits({
      'default': [hit('a', DateTime(2026, 1, 5))],
      'research': [hit('b', DateTime(2026, 1, 6))],
    });
    expect({for (final h in merged) h.storedId: h.profile}, {
      'a': 'default',
      'b': 'research',
    });
  });

  test('newest first across profiles, undated last', () {
    final merged = mergeProfileHits({
      'default': [hit('old', DateTime(2026, 1, 5)), hit('none', null)],
      'research': [
        hit('new', DateTime(2026, 3, 5)),
        hit('mid', DateTime(2026, 2, 5)),
      ],
    });
    expect(merged.map((h) => h.storedId), ['new', 'mid', 'old', 'none']);
  });

  test(
    'an empty profile adds nothing and a repeated id is kept per profile',
    () {
      final merged = mergeProfileHits({
        'default': const [],
        'a': [hit('x', DateTime(2026, 1, 5))],
        'b': [hit('x', DateTime(2026, 1, 5))],
      });
      expect(merged, hasLength(2));
      expect(merged.map((h) => h.profile).toSet(), {'a', 'b'});
    },
  );

  test('no profiles is no hits', () {
    expect(mergeProfileHits(const {}), isEmpty);
  });
}
