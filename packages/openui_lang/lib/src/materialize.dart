/// Turns a [Program] into a validated tree: positional arguments become named props, mistakes remove the smallest
/// unit and are reported (language.md §2.3, §8). Values that need evaluation stay [Deferred].
library;

import 'ast.dart';
import 'errors.dart';
import 'library_spec.dart';
import 'program.dart';
import 'statements.dart';
import 'tree.dart';

const builtinFunctions = {
  'Count', 'First', 'Last', 'Sum', 'Avg', 'Min', 'Max', 'Filter', 'Sort', 'Round', 'Abs', 'Floor', 'Ceil', 'Each', //
};
const builtinActions = {'Set', 'Reset', 'Run', 'ToAssistant', 'OpenUrl'};
const _actionDefs = {'ActionExpression', 'OpenUrl', 'ToAssistant'};

class _Drop {
  const _Drop();
}

class _Missing {
  const _Missing();
}

class _Bad {
  const _Bad();
}

const _drop = _Drop();
const _missing = _Missing();
const _bad = _Bad();

class Materialized {
  Materialized(this.root, this.errors, this.unresolved);

  /// An [Element], a [Deferred] (an entry such as a ternary), or null when nothing renders.
  final Object? root;
  final List<OpenUiError> errors;
  final Set<String> unresolved;
}

Materialized materialize(Program program, LibrarySpec library) => _Materializer(program, library).run();

class _Materializer {
  _Materializer(this.program, this.lib);

  final Program program;
  final LibrarySpec lib;
  final errors = <OpenUiError>[];
  final unresolved = <String>{};
  final _stack = <String>[];

  Materialized run() {
    final entry = program.entry;
    if (entry == null) {
      if (program.statements.isNotEmpty) errors.add(const OpenUiError(code: ErrorCode.noRoot, message: 'no root statement'));
      return Materialized(null, errors, unresolved);
    }
    _stack.add(entry);
    final v = _value(program.statements[entry]!.expr, entry, valuePos: true);
    _stack.removeLast();
    // State, query and mutation statements may reference value statements; walk them for unresolved names.
    for (final s in program.statements.values) {
      if (s.kind != StatementKind.value) _scan(s.expr);
    }
    if (v is Element || v is Deferred) {
      if (program.entryIsFallback) {
        errors.add(const OpenUiError(
            code: ErrorCode.noRoot, message: 'no root statement; rendering the first statement that calls the root component', warning: true));
      }
      return Materialized(v, errors, unresolved);
    }
    errors.add(const OpenUiError(code: ErrorCode.noRoot, message: 'root does not give a component'));
    return Materialized(null, errors, unresolved);
  }

  void _scan(Expr e) {
    for (final n in referencedNames(e)) {
      if (!program.statements.containsKey(n)) unresolved.add(n);
    }
  }

  Deferred _defer(Expr e, String sid) {
    _scan(e);
    return Deferred(e, sid);
  }

  Object? _clean(Object? v) => (v is _Drop || v is _Missing) ? null : v;

  /// [valuePos]: a direct argument of a component call or a direct element of an array.
  Object? _value(Expr e, String sid, {required bool valuePos}) {
    switch (e) {
      case StrLit(:final value):
        return value;
      case NumLit(:final value):
        return value;
      case BoolLit(:final value):
        return value;
      case NullLit():
        return null;
      case ArrayExpr(:final items):
        return [
          for (final i in items)
            ...switch (_value(i, sid, valuePos: true)) {
              _Drop() || _Missing() => const <Object?>[],
              final v => [v],
            },
        ];
      case ObjectExpr(:final entries):
        return {for (final (k, v) in entries) k: _clean(_value(v, sid, valuePos: false))};
      case CallExpr():
        return _call(e, sid, valuePos);
      case RefExpr(:final name):
        return e.isState ? Deferred(e, sid) : _ref(name, sid, valuePos);
      case FnExpr():
        return _fn(e, sid);
      default:
        return _defer(e, sid);
    }
  }

  Object? _ref(String name, String sid, bool valuePos) {
    final s = program.statements[name];
    if (s == null) {
      unresolved.add(name);
      return _missing;
    }
    if (_stack.contains(name)) {
      unresolved.add(name);
      return _missing;
    }
    if (s.kind != StatementKind.value) return Deferred(RefExpr(name), sid);
    _stack.add(name);
    final v = _value(s.expr, name, valuePos: true);
    _stack.removeLast();
    return v;
  }

  Object? _call(CallExpr e, String sid, bool valuePos) {
    switch (e.name) {
      case 'Query' || 'Mutation':
        if (valuePos) {
          errors.add(OpenUiError(
              code: ErrorCode.inlineReserved,
              statementId: sid,
              message: '${e.name} is only valid as a whole statement',
              hint: 'Write name = ${e.name}(...) on its own line and reference name.'));
          return _drop;
        }
        return null;
      case 'Action':
        return _defer(e, sid);
    }
    final spec = lib.components[e.name];
    if (spec == null) {
      errors.add(OpenUiError(
          code: ErrorCode.unknownComponent,
          statementId: sid,
          component: e.name,
          message: 'unknown component "${e.name}"',
          hint: 'Available: ${lib.components.keys.join(', ')}'));
      return valuePos ? _drop : null;
    }
    return _component(e, spec, sid);
  }

  String _signature(ComponentSpec spec) => '${spec.name}(${spec.props.map((p) => p.required ? '${p.name}*' : p.name).join(', ')}). * marks required';

  OpenUiError _err(String code, String sid, ComponentSpec spec, String? path, String message) => OpenUiError(
        code: code,
        statementId: sid,
        component: spec.name,
        path: path,
        message: message,
        hint: 'Signature: ${_signature(spec)}',
      );

  Object? _component(CallExpr e, ComponentSpec spec, String sid) {
    var args = e.args;
    if (args.length > spec.props.length) {
      errors.add(_err(ErrorCode.excessArgs, sid, spec, null, '${spec.name} takes ${spec.props.length} arguments, got ${args.length}'));
      args = args.sublist(0, spec.props.length);
    }
    final props = <String, Object?>{};
    for (var i = 0; i < spec.props.length; i++) {
      final p = spec.props[i];
      Object? v = _absent;
      if (i < args.length) {
        final arg = args[i];
        if (p.bindable && arg is RefExpr && arg.isState) {
          props[p.name] = Binding(arg.name);
          continue;
        }
        v = _clean(_value(arg, sid, valuePos: true));
        if (v == null && arg is NullLit && p.required && !p.hasDefault) {
          errors.add(_err(ErrorCode.nullRequired, sid, spec, '/${p.name}', 'required "${p.name}" is null'));
          return _drop;
        }
        if (v != null) {
          final c = _coerce(p.schema, v, sid, spec, '/${p.name}');
          if (c is _Bad) {
            v = _absent;
          } else {
            v = c;
          }
        } else {
          v = _absent;
        }
      }
      if (identical(v, _absent)) {
        if (p.hasDefault && p.required) {
          props[p.name] = p.defaultValue;
        } else if (p.required) {
          if (i >= args.length || args[i] is! NullLit) {
            // Missing, invalid or unresolved: the component cannot render without it.
            if (i >= args.length) {
              errors.add(_err(ErrorCode.missingRequired, sid, spec, '/${p.name}', 'missing required field "/${p.name}"'));
            }
          }
          return _drop;
        } else if (p.hasDefault && i < args.length) {
          props[p.name] = p.defaultValue;
        }
      } else {
        props[p.name] = v;
      }
    }
    return Element(spec.name, sid, props);
  }

  static const Object _absent = _Absent();

  // ---- schema checks ----

  Json _resolve(Json schema) {
    var s = schema;
    for (var guard = 0; guard < 8; guard++) {
      final ref = s[r'$ref'];
      if (ref is! String) return s;
      final name = ref.split('/').last;
      if (lib.components.containsKey(name) || lib.actions.containsKey(name) || _actionDefs.contains(name)) return s;
      final def = lib.defs[name];
      if (def is! Map) return s;
      s = def.cast<String, Object?>();
    }
    return s;
  }

  bool _accepts(Json raw, Object? v) {
    if (v is Deferred || v is Binding) return true;
    final s = _resolve(raw);
    final ref = s[r'$ref'];
    if (ref is String) {
      final name = ref.split('/').last;
      if (lib.components.containsKey(name)) return v is Element;
      return v is List || v is Deferred; // an action
    }
    final any = s['anyOf'];
    if (any is List) return any.any((a) => a is Map && _accepts(a.cast<String, Object?>(), v));
    final en = s['enum'];
    if (en is List && !en.contains(v)) return false;
    if (s.containsKey('const') && s['const'] != v) return false;
    switch (s['type']) {
      case 'string':
        return v is String;
      case 'number':
        return v is double;
      case 'integer':
        return v is double && v == v.truncateToDouble();
      case 'boolean':
        return v is bool;
      case 'array':
        if (v is! List) return false;
        final items = s['items'];
        return items is! Map || v.every((x) => x == null || _accepts(items.cast<String, Object?>(), x));
      case 'object':
        return v is Map;
      default:
        return true;
    }
  }

  /// Checks [v] against [schema]. Array items are checked one by one; bad items are removed and reported.
  Object? _coerce(Json schema, Object? v, String sid, ComponentSpec spec, String path) {
    final s = _resolve(schema);
    if (s['type'] == 'array' && v is List) {
      final items = s['items'];
      if (items is! Map) return v;
      final item = items.cast<String, Object?>();
      final out = <Object?>[];
      for (var i = 0; i < v.length; i++) {
        final x = v[i];
        if (x == null || _accepts(item, x)) {
          out.add(x);
        } else {
          errors.add(_err(ErrorCode.typeMismatch, sid, spec, '$path/$i', 'item $i of "$path" has the wrong type'));
        }
      }
      return out;
    }
    if (_accepts(s, v)) return v;
    errors.add(_err(ErrorCode.typeMismatch, sid, spec, path, '"$path" has the wrong type'));
    return _bad;
  }

  // ---- functions ----

  Object? _fn(FnExpr e, String sid) {
    if (builtinFunctions.contains(e.name) || builtinActions.contains(e.name) || lib.actions.containsKey(e.name)) {
      return _defer(e, sid);
    }
    final fn = lib.functions[e.name];
    if (fn == null) {
      errors.add(OpenUiError(
          code: ErrorCode.unknownFunction,
          statementId: sid,
          message: 'unknown function @${e.name}',
          hint: 'Available: ${[...builtinFunctions, ...lib.functions.keys].map((n) => '@$n').join(', ')}'));
      _scan(e);
      return null;
    }
    // Literal arguments are checked when parsing (language.md §3.6).
    var args = e.args;
    var invalid = false;
    OpenUiError fe(String code, String? path, String m) => OpenUiError(
        code: code,
        statementId: sid,
        path: path,
        message: m,
        hint: 'Signature: ${fn.name}(${fn.params.map((p) => p.required ? '${p.name}*' : p.name).join(', ')}). * marks required');
    if (args.length > fn.params.length) {
      errors.add(fe(ErrorCode.excessArgs, null, '@${fn.name} takes ${fn.params.length} arguments'));
      args = args.sublist(0, fn.params.length);
    }
    for (var i = 0; i < fn.params.length; i++) {
      final p = fn.params[i];
      if (i >= args.length) {
        if (p.required && !p.hasDefault) {
          errors.add(fe(ErrorCode.missingRequired, '/${p.name}', 'missing required argument "${p.name}"'));
          invalid = true;
        }
        continue;
      }
      final a = args[i];
      final lit = switch (a) {
        StrLit(:final value) => value,
        NumLit(:final value) => value,
        BoolLit(:final value) => value,
        _ => _absent,
      };
      if (identical(lit, _absent)) continue;
      if (!_accepts(p.schema, lit)) {
        errors.add(fe(ErrorCode.typeMismatch, '/${p.name}', 'argument "${p.name}" has the wrong type'));
        if (p.required) invalid = true;
      }
    }
    _scan(e);
    return invalid ? null : Deferred(e, sid);
  }
}

class _Absent {
  const _Absent();
}
