/// Lists of strings in a preference value.
///
/// A preference is one string, so a list is JSON. Decoding never throws: a
/// damaged value is an empty list, the same rule as the usage selection.
library;

import 'dart:convert';

List<String> decodeStringList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final seen = <String>{};
    return [
      for (final entry in decoded)
        if (entry is String && entry.isNotEmpty && seen.add(entry)) entry,
    ];
  } on FormatException {
    return const [];
  }
}

/// The value to store, or null when there is nothing to store, which removes
/// the key.
String? encodeStringList(List<String> values) =>
    values.isEmpty ? null : jsonEncode(values);
