/// Putting the hits of several profiles' searches into one list.
library;

import 'chat_models.dart';

/// Each hit labelled with its profile, all of them newest first. A hit with no
/// time sorts after every dated one, and ties keep the order they came in.
List<SearchHit> mergeProfileHits(Map<String, List<SearchHit>> byProfile) {
  final labelled = <SearchHit>[
    for (final entry in byProfile.entries)
      for (final hit in entry.value) hit.withProfile(entry.key),
  ];
  final indexed = labelled.indexed.toList()
    ..sort((a, b) {
      final x = a.$2.lastActive;
      final y = b.$2.lastActive;
      if (x == null && y == null) return a.$1.compareTo(b.$1);
      if (x == null) return 1;
      if (y == null) return -1;
      final byTime = y.compareTo(x);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, hit) in indexed) hit];
}
