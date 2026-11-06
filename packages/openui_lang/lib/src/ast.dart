/// Expression syntax tree (language.md §1.5). Nodes are immutable; `toString` prints an s-expression for tests.
library;

sealed class Expr {
  const Expr();
}

class StrLit extends Expr {
  const StrLit(this.value);
  final String value;
  @override
  String toString() => '"$value"';
}

class NumLit extends Expr {
  const NumLit(this.value);
  final double value;
  @override
  String toString() => formatNumber(value);
}

class BoolLit extends Expr {
  const BoolLit(this.value);
  final bool value;
  @override
  String toString() => '$value';
}

class NullLit extends Expr {
  const NullLit();
  @override
  String toString() => 'null';
}

class ArrayExpr extends Expr {
  const ArrayExpr(this.items);
  final List<Expr> items;
  @override
  String toString() => '[${items.join(' ')}]';
}

class ObjectExpr extends Expr {
  const ObjectExpr(this.entries);

  /// Keys keep source order; duplicates are kept, the later one wins when read.
  final List<(String, Expr)> entries;
  @override
  String toString() => '{${entries.map((e) => '${e.$1}:${e.$2}').join(' ')}}';
}

/// A bare identifier, whatever its case, or a `$state` name (the `$` is part of [name]).
class RefExpr extends Expr {
  const RefExpr(this.name);
  final String name;
  bool get isState => name.startsWith(r'$');
  @override
  String toString() => name;
}

/// `Name(args)` where the head is a component, or `Query`/`Mutation`/`Action`.
class CallExpr extends Expr {
  const CallExpr(this.name, this.args);
  final String name;
  final List<Expr> args;
  @override
  String toString() => '($name${args.map((a) => ' $a').join()})';
}

/// `@Name(args)`: a built-in, a custom function or an action.
class FnExpr extends Expr {
  const FnExpr(this.name, this.args);
  final String name;
  final List<Expr> args;
  @override
  String toString() => '(@$name${args.map((a) => ' $a').join()})';
}

class MemberExpr extends Expr {
  const MemberExpr(this.object, this.field);
  final Expr object;
  final String field;
  @override
  String toString() => '$object.$field';
}

class IndexExpr extends Expr {
  const IndexExpr(this.object, this.index);
  final Expr object;
  final Expr index;
  @override
  String toString() => '$object[$index]';
}

class UnaryExpr extends Expr {
  const UnaryExpr(this.op, this.operand);

  /// `!` or `-`.
  final String op;
  final Expr operand;
  @override
  String toString() => '($op $operand)';
}

class BinaryExpr extends Expr {
  const BinaryExpr(this.op, this.left, this.right);
  final String op;
  final Expr left;
  final Expr right;
  @override
  String toString() => '($op $left $right)';
}

class TernaryExpr extends Expr {
  const TernaryExpr(this.cond, this.then, this.otherwise);
  final Expr cond;
  final Expr then;
  final Expr otherwise;
  @override
  String toString() => '(? $cond $then $otherwise)';
}

/// `$name = expression` inside an expression: a two-way binding assignment.
class AssignExpr extends Expr {
  const AssignExpr(this.target, this.value);
  final String target;
  final Expr value;
  @override
  String toString() => '(= $target $value)';
}

/// ECMAScript Number::toString for the values the language produces.
String formatNumber(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v < 0 ? '-Infinity' : 'Infinity';
  if (v == v.truncateToDouble() && v.abs() < 1e21) {
    return v == 0 ? '0' : v.toInt().toString();
  }
  return v.toString();
}
