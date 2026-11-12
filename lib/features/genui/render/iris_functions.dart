/// The library's custom functions (`@Percent`, `@Money`, `@Ago`) as the evaluator runs them. Pure Dart, no Flutter.
///
/// They never throw: a value they cannot make sense of gives null, and the evaluator leaves that prop out.
library;

import 'package:openui_lang/openui_lang.dart';

/// The implementations, keyed by function name. [now] is the clock `@Ago` measures from.
Map<String, OpenUiFunction> irisFunctions({DateTime Function()? now}) {
  final clock = now ?? DateTime.now;
  return {
    'Percent': percent,
    'Money': money,
    'Ago': (args) => ago(args['timestamp'], clock()),
  };
}

/// `done` as a percentage of `total`, rounded. A zero or negative total gives 0.
Object? percent(Map<String, Object?> args) {
  final done = args['done'];
  final total = args['total'];
  if (done is! num || total is! num) return null;
  if (total <= 0) return 0;
  return (done / total * 100).round();
}

const _symbols = {
  'GBP': '£',
  'USD': r'$',
  'EUR': '€',
  'INR': '₹',
  'JPY': '¥',
  'CNY': '¥',
  'KRW': '₩',
  'AUD': r'A$',
  'CAD': r'C$',
  'CHF': 'CHF ',
};

const _wholeCurrencies = {'JPY', 'KRW'};

/// `value` as money in the ISO code `currency`: `£1,234.50`. An unknown code is printed before the amount.
Object? money(Map<String, Object?> args) {
  final value = args['value'];
  final currency = args['currency'];
  if (value is! num || value.isNaN || value.isInfinite || currency is! String) {
    return null;
  }
  final code = currency.trim().toUpperCase();
  if (code.isEmpty) return null;
  final digits = _wholeCurrencies.contains(code) ? 0 : 2;
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(digits);
  final parts = fixed.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final amount = digits == 0 ? grouped : '$grouped.${parts.last}';
  final symbol = _symbols[code] ?? '$code ';
  return '${negative ? '-' : ''}$symbol$amount';
}

/// A timestamp as relative time: `just now`, `5 minutes ago`, `in 3 hours`. [timestamp] is ISO 8601 text, or epoch
/// seconds or milliseconds.
String? ago(Object? timestamp, DateTime now) {
  final at = _parseTime(timestamp);
  if (at == null) return null;
  final seconds = now.difference(at).inSeconds;
  final future = seconds < 0;
  final s = seconds.abs();
  if (s < 45) return 'just now';

  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  final String span;
  if (s < 90) {
    span = '1 minute';
  } else if (s < 45 * 60) {
    span = unit((s / 60).round(), 'minute');
  } else if (s < 22 * 3600) {
    span = unit((s / 3600).round(), 'hour');
  } else if (s < 36 * 3600) {
    span = '1 day';
  } else if (s < 26 * 86400) {
    span = unit((s / 86400).round(), 'day');
  } else if (s < 320 * 86400) {
    span = unit((s / (30.4375 * 86400)).round().clamp(1, 11), 'month');
  } else {
    span = unit((s / (365.25 * 86400)).round().clamp(1, 1000), 'year');
  }
  return future ? 'in $span' : '$span ago';
}

DateTime? _parseTime(Object? v) {
  if (v is num) {
    if (v.isNaN || v.isInfinite) return null;
    // Seconds until about 2286, milliseconds after.
    final ms = v.abs() < 1e11 ? v * 1000 : v;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }
  if (v is String) return DateTime.tryParse(v.trim())?.toUtc();
  return null;
}
