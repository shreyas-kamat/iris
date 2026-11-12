import 'errors.dart';
import 'program.dart';
import 'tree.dart';

/// The outcome of parsing a program.
class ParseResult {
  const ParseResult({
    required this.tree,
    required this.errors,
    required this.unresolved,
    required this.orphans,
    required this.incomplete,
    required this.program,
    this.state,
  });

  /// The validated tree: an [Element], a [Deferred] entry, or null when nothing renders.
  final Object? tree;
  final List<OpenUiError> errors;
  final Set<String> unresolved;
  final Set<String> orphans;

  /// True when the input ended inside an unclosed string or bracket.
  final bool incomplete;
  final Program? program;
  final Map<String, Object?>? state;

  /// Statements in the program after last-wins (language.md §2.4).
  int get statementCount => program?.statements.length ?? 0;

  bool get hasFatalError => errors.any((e) => e.isFatal);

  /// The tree in the canonical form the conformance fixtures compare (fixtures/README.md).
  /// Deferred values go through [evaluate]; without one they show as a marker string.
  Map<String, Object?>? summary({Object? Function(Deferred)? evaluate}) {
    final t = summarizeValue(tree, evaluate);
    return t is Map<String, Object?> ? t : null;
  }
}

const deferredMarker = '<deferred>';

Object? summarizeValue(Object? v, Object? Function(Deferred)? evaluate) {
  switch (v) {
    case Element():
      return {
        'type': v.type,
        'props': {for (final e in v.props.entries) e.key: summarizeValue(e.value, evaluate)},
      };
    case Binding():
      return {r'$binding': v.name};
    case Deferred():
      return evaluate == null ? deferredMarker : summarizeValue(evaluate(v), evaluate);
    case List():
      return [for (final x in v) summarizeValue(x, evaluate)];
    case Map():
      return {for (final e in v.entries) e.key as String: summarizeValue(e.value, evaluate)};
    case double() when v == v.truncateToDouble() && v.abs() < 1e15:
      return v.toInt();
    default:
      return v;
  }
}
