/// The validated program tree (language.md §9.1). Values are plain Dart (String, double, bool, null, List, Map),
/// [Element]s, [Binding]s, or [Deferred] expressions that the evaluator resolves later.
library;

import 'ast.dart';

class Element {
  Element(this.type, this.statementId, this.props);

  final String type;

  /// The statement this call was written in.
  final String statementId;

  /// Named props in positional order. Absent and null props are not stored.
  final Map<String, Object?> props;

  @override
  String toString() => '$type($props)';
}

/// A prop bound two-way to `$name`.
class Binding {
  const Binding(this.name);
  final String name;
  @override
  String toString() => 'bind($name)';
}

/// An expression the evaluator must run (operators, built-ins, member access, ternaries, state reads, queries).
class Deferred {
  const Deferred(this.expr, this.statementId);
  final Expr expr;
  final String statementId;
  @override
  String toString() => 'deferred($expr)';
}
