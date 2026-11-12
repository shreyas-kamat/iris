/// Input validation rules (language.md §5.4).
library;

import 'values.dart';

const ruleNames = ['required', 'email', 'url', 'numeric', 'minLength', 'maxLength', 'min', 'max', 'pattern'];

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _parseFloat = RegExp(r'^[+-]?(Infinity|\d+\.?\d*([eE][+-]?\d+)?|\.\d+([eE][+-]?\d+)?)');

bool _empty(Object? v) {
  if (v == null || v == '') return true;
  if (v is List) return v.isEmpty;
  if (v is Map) return v.containsKey('value') ? _empty(v['value']) : v.isEmpty;
  return false;
}

/// ECMAScript `parseFloat`: the longest numeric prefix after leading white space, else NaN.
double parseFloatJs(String s) {
  final m = _parseFloat.firstMatch(s.trimLeft());
  if (m == null) return double.nan;
  final t = m.group(0)!;
  if (t.endsWith('Infinity')) return t.startsWith('-') ? double.negativeInfinity : double.infinity;
  return double.parse(t.endsWith('.') ? '${t}0' : t);
}

double _num(Object? v) => v is num ? v.toDouble() : parseFloatJs(jsString(v));

bool _isUrl(String s) {
  final u = Uri.tryParse(s);
  return u != null && u.hasScheme && u.host.isNotEmpty;
}

/// Checks [value] against [rules] (`{required: true, maxLength: 80, ...}`) in their key order. Returns the name of the
/// first failing rule, or null when every rule passes. Rules set to false or null, and unknown rules, are skipped.
String? validateRules(Object? value, Map<String, Object?> rules) {
  for (final MapEntry(key: rule, value: arg) in rules.entries) {
    if (arg == null || arg == false) continue;
    if (!_passes(rule, value, arg)) return rule;
  }
  return null;
}

bool _passes(String rule, Object? v, Object arg) {
  if (rule == 'required') {
    if (_empty(v)) return false;
    if (v is Map && v.isNotEmpty && v.values.every((x) => x is bool)) return v.values.any((x) => x == true);
    return true;
  }
  if (_empty(v)) return true;
  switch (rule) {
    case 'email':
      return v is String && _email.hasMatch(v);
    case 'url':
      return v is String && _isUrl(v);
    case 'numeric':
      if (v is num) return !v.isNaN;
      return v is String && v.trim().isNotEmpty && !parseFloatJs(v).isNaN;
    case 'min' || 'max':
      final n = _num(v);
      if (n.isNaN) return true;
      return rule == 'min' ? n >= toNumber(arg) : n <= toNumber(arg);
    case 'minLength' || 'maxLength':
      if (v is! String) return true;
      return rule == 'minLength' ? v.length >= toNumber(arg) : v.length <= toNumber(arg);
    case 'pattern':
      if (v is! String || arg is! String) return true;
      try {
        return RegExp(arg).hasMatch(v);
      } on FormatException {
        return true;
      }
    default:
      return true;
  }
}
