/// The ECMA-262 coercions the language borrows (language.md §3.1): ToNumber, ToBoolean, IsLooselyEqual, String(),
/// and a root-collation stand-in for `localeCompare`. Numbers are Dart `num`; the evaluator produces doubles, host
/// data may hold ints.
library;

import 'ast.dart';

/// JavaScript white space and line terminators, which `Number("…")` trims.
final _jsSpace = RegExp('^[\\s ﻿  ]+|[\\s ﻿  ]+\$');
final _decimal = RegExp(r'^[+-]?(\d+\.?\d*([eE][+-]?\d+)?|\.\d+([eE][+-]?\d+)?)$');
final _radix = RegExp(r'^0([xXoObB])([0-9a-fA-F]+)$');

/// ECMAScript StringToNumber: NaN for text that is not a number.
double stringToNumber(String s) {
  final t = s.replaceAll(_jsSpace, '');
  if (t.isEmpty) return 0;
  switch (t) {
    case 'Infinity' || '+Infinity':
      return double.infinity;
    case '-Infinity':
      return double.negativeInfinity;
  }
  if (_decimal.hasMatch(t)) return double.parse(t.endsWith('.') ? '${t}0' : t);
  final m = _radix.firstMatch(t);
  if (m != null) {
    final radix = switch (m.group(1)!.toLowerCase()) { 'x' => 16, 'o' => 8, _ => 2 };
    final v = BigInt.tryParse(m.group(2)!, radix: radix);
    if (v != null) return v.toDouble();
  }
  return double.nan;
}

/// ECMAScript ToNumber with the language's rule that NaN never appears: a number is itself, a string is parsed or
/// else 0, `true` is 1, everything else 0.
double toNumber(Object? v) {
  final n = switch (v) {
    num() => v.toDouble(),
    String() => stringToNumber(v),
    true => 1.0,
    _ => 0.0,
  };
  return n.isNaN ? 0 : n;
}

/// ECMAScript ToBoolean. Lists, maps and component instances are truthy.
bool truthy(Object? v) => switch (v) {
      null => false,
      bool() => v,
      num() => v != 0 && !v.isNaN,
      String() => v.isNotEmpty,
      _ => true,
    };

/// ECMAScript Number::toString.
String numberToString(num v) => formatNumber(v.toDouble());

/// ECMAScript `String(v)`. Lists join their elements with commas (null as empty); other objects print as
/// `[object Object]`.
String jsString(Object? v) => switch (v) {
      null => 'null',
      String() => v,
      bool() => '$v',
      num() => numberToString(v),
      List() => v.map((x) => x == null ? '' : jsString(x)).join(','),
      _ => '[object Object]',
    };

bool _isObject(Object? v) => v != null && v is! num && v is! String && v is! bool;

/// ECMAScript IsLooselyEqual (`==`). Lists, maps and components compare by identity; against a primitive they convert
/// with ToPrimitive (a list joins, anything else is `[object Object]`).
bool looseEquals(Object? a, Object? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  if (_isObject(a) && _isObject(b)) return identical(a, b);
  if (a is num && b is String) return a == stringToNumber(b);
  if (a is String && b is num) return stringToNumber(a) == b;
  if (a is bool) return looseEquals(a ? 1.0 : 0.0, b);
  if (b is bool) return looseEquals(a, b ? 1.0 : 0.0);
  if (_isObject(a)) return looseEquals(jsString(a), b);
  if (_isObject(b)) return looseEquals(a, jsString(b));
  return false;
}

// ---- collation ----

/// Base letters for the accented Latin letters a model is likely to write (Latin-1 Supplement, Latin Extended-A).
const _accented = {
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭį',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉ',
  'o': 'òóôõöøōŏő',
  'r': 'ŕŗř',
  's': 'śŝşšß',
  't': 'ţťŧ',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final Map<int, (int, int)> _fold = () {
  final m = <int, (int, int)>{};
  for (final e in _accented.entries) {
    final base = e.key.codeUnitAt(0);
    final marks = e.value.runes.toList();
    for (var i = 0; i < marks.length; i++) {
      m[marks[i]] = (base, i + 1);
      final up = String.fromCharCode(marks[i]).toUpperCase();
      if (up.length == 1 && up.codeUnitAt(0) != marks[i]) m[up.codeUnitAt(0)] = (base - 32, i + 1);
    }
  }
  return m;
}();

/// Collation weights of one character: primary (group, base), secondary (accent), tertiary (case).
(int, int, int, int) _weights(int c) {
  var base = c;
  var accent = 0;
  final f = _fold[c];
  if (f != null) (base, accent) = f;
  final isUpper = base >= 0x41 && base <= 0x5a;
  final lower = isUpper ? base + 32 : base;
  if (lower >= 0x61 && lower <= 0x7a) return (3, lower, accent, isUpper ? 1 : 0);
  if (c >= 0x30 && c <= 0x39) return (2, c, 0, 0);
  if (c < 0x80) return (1, c, 0, 0); // space, punctuation and symbols sort before digits
  return (4, c, 0, 0);
}

/// A stand-in for ECMAScript `localeCompare` with no arguments (the root collation) that agrees with it on Latin text:
/// punctuation, then digits (character by character), then letters, ignoring accents and case until they are the only
/// difference, with lower case first.
int localeCompare(String a, String b) {
  final wa = a.runes.map(_weights).toList();
  final wb = b.runes.map(_weights).toList();
  for (final level in [0, 1, 2]) {
    final n = wa.length < wb.length ? wa.length : wb.length;
    for (var i = 0; i < n; i++) {
      final x = wa[i];
      final y = wb[i];
      final c = switch (level) {
        0 => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2),
        1 => x.$3.compareTo(y.$3),
        _ => x.$4.compareTo(y.$4),
      };
      if (c != 0) return c;
    }
    if (level == 0 && wa.length != wb.length) return wa.length.compareTo(wb.length);
  }
  return a.compareTo(b);
}
