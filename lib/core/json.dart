/// Tolerant JSON access.
///
/// The Hermes dashboard evolves quickly and its responses are not versioned
/// per-field. A client that decodes strictly will crash, blank a screen, or drop
/// data every time upstream adds, renames, or retypes something. So every wire
/// value in Iris is read through [Json]: navigation never throws, missing keys
/// are indistinguishable from absent ones, and scalars are coerced across the
/// representations the server has actually been observed to use (epoch seconds
/// as double, epoch millis as int, ISO-8601 strings, "true"/1 for booleans,
/// numeric strings for ints).
///
/// The contract: reading a value never throws. Callers decide the fallback.
library;

import 'dart:convert';

/// An immutable, null-safe view over a decoded JSON value.
///
/// Obtain one with [Json.decode] or [Json.of], then navigate with [operator []]
/// (object keys) and [at] (array indices). Navigating into a value that is not
/// a map or list yields [Json.missing] rather than throwing, so a deep path on
/// an unexpected shape degrades to a fallback instead of an exception.
final class Json {
  const Json._(this._value, this._present);

  /// Wraps an already-decoded value (`Map`, `List`, scalar, or `null`).
  factory Json.of(Object? value) => Json._(value, true);

  /// Decodes [source] as JSON. Returns [missing] if [source] is not valid JSON,
  /// which lets callers treat a truncated or HTML error body as absent data.
  factory Json.decode(String source) {
    try {
      return Json._(jsonDecode(source), true);
    } on FormatException {
      return missing;
    }
  }

  /// A value that was not present at all. Distinct from a present `null`.
  static const Json missing = Json._(null, false);

  final Object? _value;
  final bool _present;

  /// The underlying decoded value, for the rare caller that needs it raw.
  Object? get raw => _value;

  /// Whether this key or index existed in the source document.
  bool get exists => _present;

  /// Whether the value is absent or an explicit JSON `null`.
  bool get isNull => !_present || _value == null;

  /// Whether this holds a value that is neither absent nor `null`.
  bool get hasValue => !isNull;

  bool get isMap => _value is Map;

  bool get isList => _value is List;

  /// Looks up [key]. Yields [missing] if this is not a map or [key] is absent.
  Json operator [](String key) {
    final value = _value;
    // Maps decoded from JSON are Map<String, dynamic>, but maps arriving from a
    // database column or across an isolate boundary may be Map<dynamic, dynamic>.
    if (value is Map && value.containsKey(key)) {
      return Json._(value[key], true);
    }
    return missing;
  }

  /// Looks up index [index]. Yields [missing] if this is not a list or the
  /// index is out of range. Negative indices count from the end.
  Json at(int index) {
    final value = _value;
    if (value is List) {
      final i = index < 0 ? value.length + index : index;
      if (i >= 0 && i < value.length) return Json._(value[i], true);
    }
    return missing;
  }

  /// Returns the first key in [keys] that holds a non-null value.
  ///
  /// Upstream renames fields more often than it changes their meaning, so
  /// readers accept every spelling: `json.any(['tool_name', 'name'])`.
  Json any(List<String> keys) {
    for (final key in keys) {
      final candidate = this[key];
      if (candidate.hasValue) return candidate;
    }
    return missing;
  }

  // --- Scalars -------------------------------------------------------------

  /// The value as a string, coercing numbers and booleans.
  ///
  /// Maps and lists are deliberately not coerced: a caller asking for a string
  /// when the server sent an object wants the fallback, not a stringified map.
  String? get stringOrNull {
    final value = _value;
    return switch (value) {
      String() => value,
      num() || bool() => value.toString(),
      _ => null,
    };
  }

  String string([String fallback = '']) => stringOrNull ?? fallback;

  /// The value as an int, parsing numeric strings and truncating doubles.
  int? get intOrNull {
    final value = _value;
    return switch (value) {
      int() => value,
      double() => value.isFinite ? value.truncate() : null,
      bool() => value ? 1 : 0,
      String() =>
        int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.truncate(),
      _ => null,
    };
  }

  int integer([int fallback = 0]) => intOrNull ?? fallback;

  /// The value as a double, parsing numeric strings.
  double? get doubleOrNull {
    final value = _value;
    return switch (value) {
      double() => value,
      int() => value.toDouble(),
      String() => double.tryParse(value.trim()),
      _ => null,
    };
  }

  double number([double fallback = 0]) => doubleOrNull ?? fallback;

  /// The value as a bool, accepting `1`/`0` and the usual string spellings.
  bool? get boolOrNull {
    final value = _value;
    return switch (value) {
      bool() => value,
      num() => value != 0,
      String() => switch (value.trim().toLowerCase()) {
        'true' || 'yes' || 'y' || '1' || 'on' => true,
        'false' || 'no' || 'n' || '0' || 'off' || '' => false,
        _ => null,
      },
      _ => null,
    };
  }

  /// The reader family — [string], [integer], [number], [boolean] — all take
  /// their fallback as an optional positional, and breaking that symmetry for
  /// this one would make call sites read worse, so the lint is waived here.
  // ignore: avoid_positional_boolean_parameters
  bool boolean([bool fallback = false]) => boolOrNull ?? fallback;

  /// The value as a timestamp, in local time.
  ///
  /// Accepts what the server actually emits: fractional epoch *seconds*
  /// (`1711829408.123`), epoch milliseconds, and ISO-8601 strings. Bare numbers
  /// are disambiguated by magnitude — below [_epochSecondsCeiling] (year 5138
  /// expressed in seconds) is read as seconds, at or above it as milliseconds.
  DateTime? get dateTimeOrNull {
    final value = _value;
    if (value is num) {
      final asDouble = value.toDouble();
      return asDouble.isFinite ? _fromEpoch(asDouble) : null;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed.toLocal();
      final asNumber = double.tryParse(trimmed);
      return asNumber != null && asNumber.isFinite
          ? _fromEpoch(asNumber)
          : null;
    }
    return null;
  }

  static const double _epochSecondsCeiling = 1e11;

  static DateTime _fromEpoch(double value) {
    final millis = value.abs() < _epochSecondsCeiling
        ? (value * 1000).round()
        : value.round();
    return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  }

  // --- Collections ---------------------------------------------------------

  /// The value as a list of [Json] views. Empty if this is not a list.
  ///
  /// A lone object is not wrapped into a one-element list; use [listOrSingle]
  /// where the server is known to collapse single-element arrays.
  List<Json> get list {
    final value = _value;
    if (value is! List) return const [];
    return [for (final element in value) Json._(element, true)];
  }

  /// Like [list], but treats a lone non-null, non-list value as a single entry.
  List<Json> get listOrSingle {
    if (_value is List) return list;
    if (isNull) return const [];
    return [this];
  }

  /// The value as a map of [Json] views, keyed by stringified keys. Empty if
  /// this is not a map.
  Map<String, Json> get map {
    final value = _value;
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        entry.key.toString(): Json._(entry.value, true),
    };
  }

  /// The map's keys in document order, or empty if this is not a map.
  List<String> get keys {
    final value = _value;
    if (value is! Map) return const [];
    return [for (final key in value.keys) key.toString()];
  }

  /// Decodes each element of a list with [decoder], dropping any element that
  /// yields `null`, so one malformed row never discards a whole response.
  List<T> mapList<T>(T? Function(Json element) decoder) {
    final result = <T>[];
    for (final element in list) {
      final decoded = decoder(element);
      if (decoded != null) result.add(decoded);
    }
    return result;
  }

  /// The value re-encoded as JSON, for debug surfaces and pass-through payloads.
  /// Returns an empty string if the value is not encodable.
  String encode({bool pretty = false}) {
    try {
      return pretty
          ? const JsonEncoder.withIndent('  ').convert(_value)
          : jsonEncode(_value);
    } on JsonUnsupportedObjectError {
      return '';
    }
  }

  @override
  String toString() => _present ? 'Json(${encode()})' : 'Json.missing';
}
