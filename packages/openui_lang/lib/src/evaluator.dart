/// The evaluator (language.md §3, §5, §6.3): resolves the [Deferred] parts of a parsed tree against the state store,
/// query data and custom functions, and builds actions. Pure and synchronous; it never throws.
library;

import 'dart:math' as math;

import 'ast.dart';
import 'errors.dart';
import 'expr_parser.dart';
import 'lexer.dart';
import 'library_spec.dart';
import 'materialize.dart';
import 'parse_result.dart';
import 'program.dart';
import 'statements.dart';
import 'store.dart';
import 'tree.dart';
import 'values.dart';

/// A library function's implementation. [args] are keyed by the function's parameter names, already checked against
/// its `params` schema. It must be pure and synchronous.
typedef OpenUiFunction = Object? Function(Map<String, Object?> args);

/// The evaluated tree (every prop concrete, null props left out) and the runtime errors found on the way.
typedef EvaluatedRoot = ({Element? root, List<OpenUiError> errors});

class _EvalError implements Exception {
  _EvalError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Evaluator {
  /// [store] is initialized with the result's state defaults (and [persisted] values), keeping what the user changed.
  /// [resolveData] gives a query's latest result or a mutation's `{status, data, error}` by statement name; without
  /// one, or when it returns null, a query reads its defaults and a mutation is idle. [maxDepth] caps nested
  /// references; [maxEach] caps the elements one `@Each` visits.
  Evaluator(
    this.result,
    this.library, {
    StateStore? store,
    this.functions = const {},
    this.resolveData,
    Map<String, Object?> persisted = const {},
    this.maxDepth = 64,
    this.maxEach = 1000,
  })  : store = store ?? StateStore(),
        program = result.program ?? Program.build(const [], library),
        _declared = null {
    this.store.initialize(result.state ?? const {}, persisted: persisted);
  }

  /// Evaluates state defaults while parsing (language.md §5.1): states read the defaults declared so far, queries read
  /// as null, and library functions and actions give null.
  Evaluator._defaults(this.program, this.library, Map<String, Object?> declared)
      : result = ParseResult(
            tree: null, errors: const [], unresolved: const {}, orphans: const {}, incomplete: false, program: program),
        store = StateStore(),
        functions = const {},
        resolveData = null,
        maxDepth = 64,
        maxEach = 1000,
        _declared = declared;

  final ParseResult result;
  final LibrarySpec library;
  final StateStore store;
  final Map<String, OpenUiFunction> functions;
  final Object? Function(String statementId)? resolveData;
  final int maxDepth;
  final int maxEach;
  final Program program;
  final Map<String, Object?>? _declared;

  bool get _defaultsMode => _declared != null;

  final _resolving = <String>[];
  var _errors = <OpenUiError>[];
  final _seen = <String>{};
  String? _sid;
  String? _component;

  /// Evaluates the entry. A `root` expression that gives no component reports a runtime `no-root`.
  EvaluatedRoot evaluateRoot() {
    _errors = [];
    _seen
      ..clear()
      ..addAll(result.errors.map(_key));
    final t = result.tree;
    Element? root;
    if (t is Element) {
      root = _element(t);
    } else if (t is Deferred) {
      _sid = t.statementId;
      final v = _guard(() => _eval(t.expr));
      if (v is Element) {
        root = v;
      } else {
        _errors.add(const OpenUiError(
            source: 'runtime', code: ErrorCode.noRoot, statementId: 'root', message: 'root does not evaluate to a component'));
      }
    }
    return (root: root, errors: List.unmodifiable(_errors));
  }

  /// Evaluates an expression written in OpenUI Lang against this program (for hosts and tests).
  Object? evaluateExpression(String source) {
    final tokens = lex(source).where((t) => t.kind != TokenKind.newline).toList();
    return _guard(() => _eval(ExprParser(tokens).parseExpression()));
  }

  /// The value a `@Set` writes, evaluated now, with the current state.
  Object? evaluateStepValue(SetStep step) => _guard(() => _eval(step.value));

  Object? _guard(Object? Function() f) {
    try {
      return f();
    } on _EvalError catch (e) {
      _runtimeError(e.message);
      return null;
    }
  }

  // ---- tree ----

  Element _element(Element el) {
    final (sid, comp) = (_sid, _component);
    _sid = el.statementId;
    _component = el.type;
    final props = <String, Object?>{};
    for (final e in el.props.entries) {
      Object? v;
      try {
        v = _tree(e.value);
      } on _EvalError catch (x) {
        _runtimeError('Evaluating prop "${e.key}" on ${el.type} failed: ${x.message}');
      }
      if (v != null) props[e.key] = v;
    }
    _sid = sid;
    _component = comp;
    return Element(el.type, el.statementId, props);
  }

  Object? _tree(Object? v) => switch (v) {
        Element() => _element(v),
        Deferred() => _eval(v.expr),
        List() => [for (final x in v) _tree(x)],
        Map() => {for (final e in v.entries) e.key: _tree(e.value)},
        _ => v,
      };

  // ---- expressions ----

  Object? _state(String name) => _defaultsMode ? _declared![name] : store.get(name);

  Object? _eval(Expr e) {
    switch (e) {
      case StrLit(:final value):
        return value;
      case NumLit(:final value):
        return value;
      case BoolLit(:final value):
        return value;
      case NullLit():
        return null;
      case ValueLit(:final value):
        return value;
      case RefExpr(:final name):
        return e.isState ? _state(name) : _ref(name);
      case ArrayExpr(:final items):
        return [
          for (final i in items)
            if (!_unresolved(i)) _eval(i),
        ];
      case ObjectExpr(:final entries):
        return {for (final (k, v) in entries) k: _eval(v)};
      case CallExpr():
        return _call(e);
      case FnExpr():
        return _fn(e);
      case MemberExpr(:final object, :final field):
        return _member(_eval(object), field);
      case IndexExpr(:final object, :final index):
        return _index(_eval(object), _eval(index));
      case UnaryExpr(:final op, :final operand):
        final v = _eval(operand);
        return op == '!' ? !truthy(v) : -toNumber(v);
      case BinaryExpr():
        return _binary(e);
      case TernaryExpr(:final cond, :final then, :final otherwise):
        return truthy(_eval(cond)) ? _eval(then) : _eval(otherwise);
      case AssignExpr(:final target):
        return _state(target);
    }
  }

  /// An unresolved reference (missing, or closing a cycle) is left out of an array (language.md §2.3).
  bool _unresolved(Expr e) =>
      e is RefExpr && !e.isState && (!program.statements.containsKey(e.name) || _resolving.contains(e.name));

  Object? _ref(String name) {
    final s = program.statements[name];
    if (s == null || _resolving.contains(name)) return null;
    switch (s.kind) {
      case StatementKind.query:
        if (_defaultsMode) return null;
        final data = resolveData?.call(name);
        if (data != null) return data;
        final args = (s.expr as CallExpr).args;
        return args.length > 2 ? _within(name, () => _eval(args[2])) : null;
      case StatementKind.mutation:
        if (_defaultsMode) return null;
        return resolveData?.call(name) ?? {'status': 'idle', 'data': null, 'error': null};
      case StatementKind.state:
        return null;
      case StatementKind.value:
        return _within(name, () {
          final m = materializeExpression(program, library, s.expr, name);
          _merge(m.errors);
          return _tree(m.root);
        });
    }
  }

  T _within<T>(String name, T Function() f) {
    if (_resolving.length >= maxDepth) throw _EvalError('references nest deeper than $maxDepth');
    _resolving.add(name);
    try {
      return f();
    } finally {
      _resolving.removeLast();
    }
  }

  Object? _call(CallExpr e) {
    switch (e.name) {
      case 'Query' || 'Mutation':
        return null;
      case 'Action':
        if (_defaultsMode) return null;
        final list = e.args.isEmpty ? null : _eval(e.args.first);
        return ActionValue([
          if (list is List)
            for (final v in list)
              if (v is ActionValue) ...v.steps,
        ]);
    }
    final m = materializeExpression(program, library, e, _sid ?? 'root', valuePos: false);
    _merge(m.errors);
    return _tree(m.root);
  }

  Object? _member(Object? obj, String field) {
    if (obj == null) return null;
    if (obj is List) {
      if (field == 'length') return obj.length.toDouble();
      return [for (final item in obj) _field(item, field)];
    }
    return _field(obj, field);
  }

  /// `obj[field]` as JavaScript reads it for the values the language has.
  static Object? _field(Object? obj, String field) {
    switch (obj) {
      case Map():
        return obj[field];
      case List():
        if (field == 'length') return obj.length.toDouble();
        final i = int.tryParse(field);
        return i != null && i >= 0 && i < obj.length && '$i' == field ? obj[i] : null;
      case String():
        if (field == 'length') return obj.length.toDouble();
        final i = int.tryParse(field);
        return i != null && i >= 0 && i < obj.length && '$i' == field ? obj[i] : null;
      default:
        return null;
    }
  }

  Object? _index(Object? obj, Object? idx) {
    if (obj == null || idx == null) return null;
    if (obj is List || obj is String) {
      final n = toNumber(idx);
      if (n != n.truncateToDouble() || n < 0) return null;
      return _field(obj, '${n.toInt()}');
    }
    return _field(obj, jsString(idx));
  }

  Object? _binary(BinaryExpr e) {
    switch (e.op) {
      case '&&':
        final l = _eval(e.left);
        return truthy(l) ? _eval(e.right) : l;
      case '||':
        final l = _eval(e.left);
        return truthy(l) ? l : _eval(e.right);
    }
    final l = _eval(e.left);
    final r = _eval(e.right);
    switch (e.op) {
      case '+':
        if (l is String || r is String) return (l == null ? '' : jsString(l)) + (r == null ? '' : jsString(r));
        return toNumber(l) + toNumber(r);
      case '-':
        return toNumber(l) - toNumber(r);
      case '*':
        return toNumber(l) * toNumber(r);
      case '/':
        final d = toNumber(r);
        return d == 0 ? 0.0 : toNumber(l) / d;
      case '%':
        final d = toNumber(r);
        return d == 0 ? 0.0 : toNumber(l).remainder(d);
      case '==':
        return looseEquals(l, r);
      case '!=':
        return !looseEquals(l, r);
      case '>':
        return toNumber(l) > toNumber(r);
      case '<':
        return toNumber(l) < toNumber(r);
      case '>=':
        return toNumber(l) >= toNumber(r);
      case '<=':
        return toNumber(l) <= toNumber(r);
      default:
        return null;
    }
  }

  // ---- @ calls ----

  Object? _fn(FnExpr e) {
    final name = e.name;
    if (name == 'Each') return _each(e.args);
    if (builtinFunctions.contains(name)) return _builtin(name, [for (final a in e.args) _eval(a)]);
    if (builtinActions.contains(name)) return _defaultsMode ? null : _builtinAction(name, e.args);
    final action = library.actions[name];
    if (action != null) return _defaultsMode ? null : _customAction(action, e);
    final fn = library.functions[name];
    if (fn != null) return _defaultsMode ? null : _callFunction(fn, e);
    return null; // unknown-function was reported when parsing
  }

  ActionValue _builtinAction(String name, List<Expr> args) {
    const none = ActionValue([]);
    switch (name) {
      case 'Set':
        final t = args.isEmpty ? null : args.first;
        if (args.length < 2 || t is! RefExpr || !t.isState) return none;
        return ActionValue([SetStep(t.name, args[1])]);
      case 'Reset':
        final targets = [
          for (final a in args)
            if (a is RefExpr && a.isState) a.name,
        ];
        return targets.isEmpty ? none : ActionValue([ResetStep(targets)]);
      case 'Run':
        final t = args.isEmpty ? null : args.first;
        if (t is! RefExpr || t.isState) return none;
        final kind = program.statements[t.name]?.kind;
        if (kind != StatementKind.query && kind != StatementKind.mutation) return none;
        return ActionValue([RunStep(t.name)]);
      case 'ToAssistant':
        final message = args.isEmpty ? null : _eval(args[0]);
        final context = args.length > 1 ? _eval(args[1]) : null;
        return ActionValue([ToAssistantStep(message == null ? '' : jsString(message), context)]);
      default: // OpenUrl
        final url = args.isEmpty ? null : _eval(args[0]);
        return ActionValue([OpenUrlStep(url == null ? '' : jsString(url))]);
    }
  }

  /// Arguments keyed by parameter name; extra ones are dropped, an explicit null for an optional one is left out so
  /// its default applies.
  Map<String, Object?> _callArgs(FunctionSpec spec, FnExpr e) {
    final out = <String, Object?>{};
    for (var i = 0; i < spec.params.length && i < e.args.length; i++) {
      final p = spec.params[i];
      final v = _eval(e.args[i]);
      if (v == null && !p.required) continue;
      out[p.name] = v;
    }
    return out;
  }

  bool _missesRequired(FunctionSpec spec, Map<String, Object?> args) =>
      spec.params.any((p) => p.required && args[p.name] == null && !p.hasDefault);

  ActionValue _customAction(FunctionSpec spec, FnExpr e) {
    const none = ActionValue([]);
    final args = _callArgs(spec, e);
    if (_missesRequired(spec, args)) return none;
    final params = <String, Object?>{};
    for (final p in spec.params) {
      if (!args.containsKey(p.name) || args[p.name] == null) {
        if (p.hasDefault) params[p.name] = p.defaultValue;
        continue;
      }
      final v = args[p.name];
      if (!schemaAccepts(library, p.schema, v)) {
        _runtimeError('@${spec.name}: argument "${p.name}" has the wrong type');
        return none;
      }
      params[p.name] = v;
    }
    return ActionValue([CustomStep(spec.name, params)]);
  }

  Object? _callFunction(FunctionSpec spec, FnExpr e) {
    final impl = functions[spec.name];
    if (impl == null) return null;
    final args = _callArgs(spec, e);
    if (_missesRequired(spec, args)) return null;
    final checked = <String, Object?>{};
    for (final p in spec.params) {
      if (!args.containsKey(p.name) || args[p.name] == null) {
        if (p.hasDefault) checked[p.name] = p.defaultValue;
        continue;
      }
      final v = args[p.name];
      if (schemaAccepts(library, p.schema, v)) {
        checked[p.name] = v;
        continue;
      }
      _runtimeError('@${spec.name}: argument "${p.name}" has the wrong type');
      if (p.hasDefault) {
        checked[p.name] = p.defaultValue;
      } else if (p.required) {
        return null;
      }
    }
    final Object? out;
    try {
      out = impl(checked);
    } on Object catch (x) {
      _runtimeError('@${spec.name} threw: $x');
      return null;
    }
    final returns = spec.returns;
    if (returns != null && !schemaAccepts(library, returns, out)) {
      _runtimeError('@${spec.name} returned a value of the wrong type');
      return null;
    }
    return out;
  }

  // ---- @Each ----

  Object? _each(List<Expr> args) {
    if (args.length < 3) return const <Object?>[];
    final arr = _eval(args[0]);
    if (arr is! List) return const <Object?>[];
    final name = switch (args[1]) {
      StrLit(:final value) => value,
      RefExpr(:final name) => name,
      _ => null,
    };
    if (name == null) return const <Object?>[];
    return [for (final item in arr.take(maxEach)) _eval(substitute(args[2], name, item))];
  }

  // ---- built-ins (language.md §3.4) ----

  Object? _builtin(String name, List<Object?> a) {
    Object? arg(int i) => i < a.length ? a[i] : null;
    final first = arg(0);
    switch (name) {
      case 'Count':
        return first is List ? first.length.toDouble() : 0.0;
      case 'First':
        return first is List && first.isNotEmpty ? first.first : null;
      case 'Last':
        return first is List && first.isNotEmpty ? first.last : null;
      case 'Sum':
        return first is List ? first.fold<double>(0, (s, x) => s + toNumber(x)) : 0.0;
      case 'Avg':
        return first is List && first.isNotEmpty ? first.fold<double>(0, (s, x) => s + toNumber(x)) / first.length : 0.0;
      case 'Min' || 'Max':
        if (first is! List || first.isEmpty) return 0.0;
        final ns = first.map(toNumber);
        return name == 'Min' ? ns.reduce(math.min) : ns.reduce(math.max);
      case 'Sort':
        return _sort(first, arg(1), arg(2));
      case 'Filter':
        return _filter(first, arg(1), arg(2), arg(3));
      case 'Round':
        final d = arg(1) == null ? 0.0 : toNumber(arg(1));
        final factor = math.pow(10, d).toDouble();
        return _elementwise(first, (n) => _jsRound(n * factor) / factor);
      case 'Abs':
        return _elementwise(first, (n) => n.abs());
      case 'Floor':
        return _elementwise(first, (n) => n.floorToDouble());
      default: // Ceil
        return _elementwise(first, (n) => n.ceilToDouble());
    }
  }

  static Object? _elementwise(Object? v, double Function(double) f) =>
      v is List ? [for (final x in v) _elementwise(x, f)] : f(toNumber(v));

  /// JavaScript `Math.round`: a half rounds up.
  static double _jsRound(double x) {
    if (x.isNaN || x.isInfinite) return x;
    final f = x.floorToDouble();
    return x - f >= 0.5 ? f + 1 : f;
  }

  static Object? _path(Object? obj, String path) {
    var cur = obj;
    for (final p in path.split('.')) {
      if (cur == null) return null;
      cur = _field(cur, p);
    }
    return cur;
  }

  static bool _numeric(Object? v) => v is num || (v is String && v.isNotEmpty && !stringToNumber(v).isNaN);

  static String _text(Object? v) => v == null ? '' : jsString(v);

  static Object? _sort(Object? array, Object? field, Object? direction) {
    if (array is! List) return array;
    final f = _text(field);
    final desc = _text(direction) == 'desc';
    final indexed = [for (var i = 0; i < array.length; i++) (i, array[i])];
    indexed.sort((x, y) {
      final av = f.isEmpty ? x.$2 : _path(x.$2, f);
      final bv = f.isEmpty ? y.$2 : _path(y.$2, f);
      int c;
      if (_numeric(av) && _numeric(bv)) {
        final d = toNumber(av) - toNumber(bv);
        c = d < 0 ? -1 : (d > 0 ? 1 : 0);
      } else {
        c = localeCompare(_text(av), _text(bv));
      }
      if (desc) c = -c;
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    return [for (final p in indexed) p.$2];
  }

  static List<Object?> _filter(Object? array, Object? field, Object? op, Object? value) {
    if (array is! List) return const [];
    final f = _text(field);
    final o = op == null ? '==' : jsString(op);
    return [
      for (final item in array)
        if (_matches(f.isEmpty ? item : _path(item, f), o, value)) item,
    ];
  }

  static bool _matches(Object? v, String op, Object? value) => switch (op) {
        '==' => looseEquals(v, value),
        '!=' => !looseEquals(v, value),
        '>' => toNumber(v) > toNumber(value),
        '<' => toNumber(v) < toNumber(value),
        '>=' => toNumber(v) >= toNumber(value),
        '<=' => toNumber(v) <= toNumber(value),
        'contains' => _text(v).contains(_text(value)),
        _ => false,
      };

  // ---- errors ----

  static String _key(OpenUiError e) => '${e.code}|${e.statementId}|${e.component}|${e.path}';

  void _merge(List<OpenUiError> errors) {
    if (_defaultsMode) return;
    for (final e in errors) {
      if (_seen.add(_key(e))) _errors.add(e);
    }
  }

  void _runtimeError(String message) {
    if (_defaultsMode) return;
    _errors.add(OpenUiError(
      source: 'runtime',
      code: ErrorCode.runtimeError,
      statementId: _sid,
      component: _component,
      message: message,
    ));
  }

  // ---- summary ----

  /// The canonical summary the conformance fixtures compare (fixtures/README.md): null props are left out, actions
  /// are `{actions: [{action, args}]}` with `@Set` values evaluated now.
  Object? summarize(Object? v) {
    switch (v) {
      case Element():
        return {
          'type': v.type,
          'props': {
            for (final e in v.props.entries) e.key: ?summarize(e.value),
          },
        };
      case ActionValue():
        return {
          'actions': [for (final s in v.steps) _summarizeStep(s)],
        };
      case Binding():
        return {r'$binding': v.name};
      case List():
        return [for (final x in v) summarize(x)];
      case Map():
        return {for (final e in v.entries) '${e.key}': summarize(e.value)};
      case double() when v == v.truncateToDouble() && v.abs() < 1e15:
        return v.toInt();
      default:
        return v;
    }
  }

  Map<String, Object?> _summarizeStep(ActionStep s) => switch (s) {
        SetStep() => {
            'action': 'Set',
            'args': [s.target, summarize(evaluateStepValue(s))],
          },
        ResetStep() => {'action': 'Reset', 'args': s.targets},
        RunStep() => {
            'action': 'Run',
            'args': [s.statementId],
          },
        ToAssistantStep() => {
            'action': 'ToAssistant',
            'args': [s.message, ?summarize(s.context)],
          },
        OpenUrlStep() => {
            'action': 'OpenUrl',
            'args': [s.url],
          },
        CustomStep() => {
            'action': s.name,
            'args': [
              for (final k in library.actions[s.name]?.params.map((p) => p.name) ?? s.params.keys) summarize(s.params[k]),
            ],
          },
      };
}

/// Replaces the loop variable [name] in [e] with [value], so deferred parts (actions) capture their own element
/// (language.md §3.5). A nested `@Each` over the same name shadows it in its template.
Expr substitute(Expr e, String name, Object? value) {
  Expr s(Expr x) => substitute(x, name, value);
  return switch (e) {
    RefExpr() when !e.isState && e.name == name => ValueLit(value),
    ArrayExpr(:final items) => ArrayExpr([for (final i in items) s(i)]),
    ObjectExpr(:final entries) => ObjectExpr([for (final (k, v) in entries) (k, s(v))]),
    CallExpr(:final name, :final args) => CallExpr(name, [for (final a in args) s(a)]),
    FnExpr(name: 'Each', :final args) when args.length >= 3 && _loopName(args[1]) == name =>
      FnExpr('Each', [s(args[0]), ...args.skip(1)]),
    FnExpr(:final name, :final args) => FnExpr(name, [for (final a in args) s(a)]),
    MemberExpr(:final object, :final field) => MemberExpr(s(object), field),
    IndexExpr(:final object, :final index) => IndexExpr(s(object), s(index)),
    UnaryExpr(:final op, :final operand) => UnaryExpr(op, s(operand)),
    BinaryExpr(:final op, :final left, :final right) => BinaryExpr(op, s(left), s(right)),
    TernaryExpr(:final cond, :final then, :final otherwise) => TernaryExpr(s(cond), s(then), s(otherwise)),
    AssignExpr(:final target, value: final v) => AssignExpr(target, s(v)),
    _ => e,
  };
}

String? _loopName(Expr e) => switch (e) {
      StrLit(:final value) => value,
      RefExpr(:final name) => name,
      _ => null,
    };

/// State defaults and auto-declared names for a parsed program (language.md §5.1). While streaming, a `$name` at the
/// very end of [partial] (the last pending statement) may still be growing and is not declared from there.
Map<String, Object?> declareState(Program program, LibrarySpec library, {Statement? partial, String? partialName}) {
  final declared = <String, Object?>{};
  final ev = Evaluator._defaults(program, library, declared);
  for (final s in program.statements.values) {
    if (s.kind == StatementKind.state) declared[s.name] = ev._guard(() => ev._eval(s.expr));
  }
  for (final s in program.statements.values) {
    for (final n in stateNames(s.expr)) {
      if (identical(s, partial) && n == partialName) continue;
      declared.putIfAbsent(n, () => null);
    }
  }
  return declared;
}

/// The `$names` an expression reads or writes.
Set<String> stateNames(Expr e) {
  final out = <String>{};
  void walk(Expr x) {
    switch (x) {
      case RefExpr(:final name) when x.isState:
        out.add(name);
      case AssignExpr(:final target, :final value):
        out.add(target);
        walk(value);
      case ArrayExpr(:final items):
        items.forEach(walk);
      case ObjectExpr(:final entries):
        for (final (_, v) in entries) {
          walk(v);
        }
      case CallExpr(:final args) || FnExpr(:final args):
        args.forEach(walk);
      case MemberExpr(:final object):
        walk(object);
      case IndexExpr(:final object, :final index):
        walk(object);
        walk(index);
      case UnaryExpr(:final operand):
        walk(operand);
      case BinaryExpr(:final left, :final right):
        walk(left);
        walk(right);
      case TernaryExpr(:final cond, :final then, :final otherwise):
        walk(cond);
        walk(then);
        walk(otherwise);
      default:
    }
  }

  walk(e);
  return out;
}

/// `query-cycle` (language.md §6.1): queries whose tool name or args read each other's results, directly or through
/// value statements. One error per cycle, on its first query in source order.
List<OpenUiError> queryCycles(Program program) {
  final queries = [
    for (final s in program.statements.values)
      if (s.kind == StatementKind.query) s.name,
  ];
  if (queries.isEmpty) return const [];
  final reads = <String, Set<String>>{};
  for (final q in queries) {
    final out = <String>{};
    final seen = <String>{};
    void visit(Expr e) {
      for (final n in referencedNames(e)) {
        final s = program.statements[n];
        if (s == null) continue;
        if (s.kind == StatementKind.query) {
          out.add(n);
        } else if (s.kind == StatementKind.value && seen.add(n)) {
          visit(s.expr);
        }
      }
    }

    final args = (program.statements[q]!.expr as CallExpr).args;
    for (final a in args.take(2)) {
      visit(a);
    }
    reads[q] = out;
  }

  // Tarjan's strongly connected components.
  var index = 0;
  final idx = <String, int>{};
  final low = <String, int>{};
  final stack = <String>[];
  final on = <String>{};
  final cycles = <List<String>>[];
  void connect(String v) {
    idx[v] = low[v] = index++;
    stack.add(v);
    on.add(v);
    for (final w in reads[v]!) {
      if (!idx.containsKey(w)) {
        connect(w);
        low[v] = math.min(low[v]!, low[w]!);
      } else if (on.contains(w)) {
        low[v] = math.min(low[v]!, idx[w]!);
      }
    }
    if (low[v] == idx[v]) {
      final comp = <String>[];
      String w;
      do {
        w = stack.removeLast();
        on.remove(w);
        comp.add(w);
      } while (w != v);
      if (comp.length > 1 || reads[v]!.contains(v)) cycles.add(comp);
    }
  }

  for (final q in queries) {
    if (!idx.containsKey(q)) connect(q);
  }
  return [
    for (final c in cycles)
      () {
        final ordered = queries.where(c.contains).toList();
        return OpenUiError(
          code: ErrorCode.queryCycle,
          statementId: ordered.first,
          component: 'Query',
          message: 'queries ${ordered.join(', ')} read each other\'s results, so none of them can run first',
          hint: 'Give one of them literal args, or read a \$variable instead of another query\'s result.',
        );
      }(),
  ];
}
