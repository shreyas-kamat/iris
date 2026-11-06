/// The program model (language.md §2): hoisted statements, last definition wins, entry, reachability.
library;

import 'ast.dart';
import 'library_spec.dart';
import 'statements.dart';

class Program {
  Program._(this.statements, this.entry, this.entryIsFallback, this.orphans, this.incomplete);

  /// One statement per name; a later definition replaces an earlier one. Insertion order of first appearance.
  final Map<String, Statement> statements;

  /// Name of the entry statement, or null when there is none.
  final String? entry;

  /// True when there is no `root` statement and the first call of the library's root component was used.
  final bool entryIsFallback;

  /// Value statements the entry (and the always-live state, query and mutation statements) cannot reach.
  final Set<String> orphans;

  final bool incomplete;

  /// Builds the model from statements in source order.
  factory Program.build(List<Statement> ordered, LibrarySpec? library, {bool incomplete = false}) {
    final byName = <String, Statement>{};
    for (final s in ordered) {
      byName.remove(s.name); // keeps "last wins" and moves the name to its final position
      byName[s.name] = s;
    }

    String? entry;
    var fallback = false;
    final root = byName['root'];
    if (root != null && root.kind != StatementKind.state) {
      entry = 'root';
    } else if (library?.root != null) {
      for (final s in byName.values) {
        if (s.kind == StatementKind.value && s.expr is CallExpr && (s.expr as CallExpr).name == library!.root) {
          entry = s.name;
          fallback = true;
          break;
        }
      }
    }

    final orphans = <String>{};
    if (entry != null) {
      final live = <String>{};
      void visit(String name) {
        if (!live.add(name)) return;
        final s = byName[name];
        if (s == null) return;
        for (final r in referencedNames(s.expr)) {
          visit(r);
        }
      }

      visit(entry);
      for (final s in byName.values) {
        if (s.kind != StatementKind.value) visit(s.name);
      }
      for (final s in byName.values) {
        if (s.kind == StatementKind.value && !live.contains(s.name)) orphans.add(s.name);
      }
    }

    return Program._(byName, entry, fallback, orphans, incomplete);
  }
}

/// Statement names an expression refers to (not `$` names, not an `@Each` loop variable inside its template).
Set<String> referencedNames(Expr e, [Set<String> shadow = const {}]) {
  final out = <String>{};
  void walk(Expr x, Set<String> sh) {
    switch (x) {
      case RefExpr(:final name):
        if (!x.isState && !sh.contains(name)) out.add(name);
      case ArrayExpr(:final items):
        for (final i in items) {
          walk(i, sh);
        }
      case ObjectExpr(:final entries):
        for (final (_, v) in entries) {
          walk(v, sh);
        }
      case CallExpr(:final args):
        for (final a in args) {
          walk(a, sh);
        }
      case FnExpr(:final name, :final args):
        if (name == 'Each' && args.length >= 3 && args[1] is StrLit) {
          walk(args[0], sh);
          walk(args[2], {...sh, (args[1] as StrLit).value});
        } else {
          for (final a in args) {
            walk(a, sh);
          }
        }
      case MemberExpr(:final object):
        walk(object, sh);
      case IndexExpr(:final object, :final index):
        walk(object, sh);
        walk(index, sh);
      case UnaryExpr(:final operand):
        walk(operand, sh);
      case BinaryExpr(:final left, :final right):
        walk(left, sh);
        walk(right, sh);
      case TernaryExpr(:final cond, :final then, :final otherwise):
        walk(cond, sh);
        walk(then, sh);
        walk(otherwise, sh);
      case AssignExpr(:final value):
        walk(value, sh);
      case StrLit() || NumLit() || BoolLit() || NullLit():
    }
  }

  walk(e, shadow);
  return out;
}
