import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

/// The evaluator (language.md §3, §5, §6.3). Fixture-level behaviour is covered by the conformance runner; these
/// tests pin the parts the fixtures leave out.
void main() {
  final library = LibrarySpec.fromJson(
    (jsonDecode(File('test/fixtures/library.json').readAsStringSync()) as Map).cast<String, Object?>(),
  );
  Object? upper(Map<String, Object?> a) => (a['text']! as String).toUpperCase();

  /// Evaluates [expr] in a program made of [program] plus a root.
  Object? value(String expr, {String program = '', Map<String, OpenUiFunction> functions = const {}}) {
    final r = parseProgram(library, '$program\nroot = Stack([])\n');
    return Evaluator(r, library, functions: {'Upper': upper, ...functions}).evaluateExpression(expr);
  }

  /// Parses and evaluates [program]; returns the summary and the parse plus runtime errors.
  ({Object? root, List<OpenUiError> errors, ParseResult parse, Evaluator ev}) run(String program,
      {Map<String, OpenUiFunction> functions = const {}, StateStore? store, int maxEach = 1000}) {
    final r = parseProgram(library, program);
    final ev = Evaluator(r, library, functions: {'Upper': upper, ...functions}, store: store, maxEach: maxEach);
    final out = ev.evaluateRoot();
    return (root: ev.summarize(out.root), errors: [...r.errors, ...out.errors], parse: r, ev: ev);
  }

  group('operators and precedence', () {
    test('arithmetic and comparison', () {
      expect(value('1 + 2 * 3 - 4 / 2'), 5);
      expect(value('7 % 0'), 0);
      expect(value('"a" + null'), 'a');
      expect(value('null + 1'), 1);
      expect(value('1 + 2 + "x"'), '3x');
      expect(value('"x" + 1 + 2'), 'x12');
      expect(value('"2" > 10'), isFalse);
      expect(value('-"3"'), -3);
    });
    test('&& and || return the deciding operand and short-circuit', () {
      expect(value('0 && @Upper("never")'), 0);
      expect(value('"" || "fallback"'), 'fallback');
      expect(value('1 || 2 && 0'), 1);
    });
    test('ternary', () {
      expect(value(r'$n > 0 ? "some" : "none"', program: r'$n = 0'), 'none');
    });
  });

  group('member access and indexing', () {
    const rows = 'rows = [{name: "a", n: 1, c: {city: "X"}}, {name: "b"}]';
    test('pluck, length, index, null', () {
      expect(value('rows.name', program: rows), ['a', 'b']);
      expect(value('rows.n', program: rows), [1, null]);
      expect(value('rows.length', program: rows), 2);
      expect(value('rows[0].c.city', program: rows), 'X');
      expect(value('rows[5]', program: rows), isNull);
      expect(value('rows[0.5]', program: rows), isNull);
      expect(value('missing.x'), isNull);
      expect(value('"abc".length'), 3);
    });
  });

  group('built-ins', () {
    const rows = 'rows = [{s: "open", n: 3, c: {name: "Zed"}}, {s: "closed", n: "1"}, {s: "open", n: 2}]';
    test('aggregates', () {
      expect(value('@Count(rows)', program: rows), 3);
      expect(value('@Count("x")'), 0);
      expect(value('@First([])'), isNull);
      expect(value('@Last(rows.n)', program: rows), 2);
      expect(value('@Sum(rows.n)', program: rows), 6);
      expect(value('@Avg(rows.n)', program: rows), 2);
      expect(value('@Avg([])'), 0);
      expect(value('@Min(rows.n)', program: rows), 1);
      expect(value('@Max(rows.n)', program: rows), 3);
    });
    test('filter', () {
      expect(value('@Count(@Filter(rows, "s", "==", "open"))', program: rows), 2);
      expect(value('@Count(@Filter(rows, "n", ">=", 2))', program: rows), 2);
      expect(value('@Count(@Filter(rows, "s", "contains", "pe"))', program: rows), 2);
      expect(value('@Count(@Filter(rows, "s", "~", "open"))', program: rows), 0);
      expect(value('@Filter(rows.n, "", "<", 3)', program: rows), ['1', 2]);
      expect(value('@Filter(rows, "c.name", "==", "Zed").length', program: rows), 1);
      expect(value('@Filter("x", "", "==", 1)'), isEmpty);
    });
    test('sort is stable, numeric when both sides are numbers, locale otherwise', () {
      expect(value('@Sort(rows, "n").n', program: rows), ['1', 2, 3]);
      expect(value('@Sort(rows, "s", "desc").n', program: rows), [3, 2, '1']);
      expect(value('@Sort(["b", "B", "a"], "")'), ['a', 'b', 'B']);
    });
    test('round, abs, floor, ceil apply to nested lists', () {
      expect(value('@Round(2.5)'), 3);
      expect(value('@Round(-2.5)'), -2);
      expect(value('@Round(1.005, 2)'), 1);
      expect(value('@Round([1.26, [2.71, null]], 1)'), [1.3, [2.7, 0]]);
      expect(value('@Abs(-3)'), 3);
      expect(value('@Floor([1.5, -1.5])'), [1, -2]);
      expect(value('@Ceil("1.2")'), 2);
    });
  });

  group('@Each', () {
    test('binds the loop variable only inside the template, shadowing a statement', () {
      expect(value('@Each([1, 2], "t", t * 10)', program: 't = 99'), [10, 20]);
      expect(value('t', program: 't = 99'), 99);
    });
    test('a nested @Each with the same name shadows the outer one', () {
      expect(value('@Each([1, 2], "x", @Each([x * 10], "x", x + 1))'), [
        [11],
        [21],
      ]);
    });
    test('the template builds components and captures its element in actions', () {
      final r = run(r'''
root = Stack(@Each(items, "t", Button(t.name, @Set($sel, t.id))))
items = [{id: 1, name: "One"}, {id: 2, name: "Two"}]
''');
      expect(r.errors, isEmpty);
      expect(r.root, {
        'type': 'Stack',
        'props': {
          'children': [
            {
              'type': 'Button',
              'props': {
                'label': 'One',
                'action': {
                  'actions': [
                    {
                      'action': 'Set',
                      'args': [r'$sel', 1],
                    },
                  ],
                },
              },
            },
            {
              'type': 'Button',
              'props': {
                'label': 'Two',
                'action': {
                  'actions': [
                    {
                      'action': 'Set',
                      'args': [r'$sel', 2],
                    },
                  ],
                },
              },
            },
          ],
        },
      });
    });
    test('non-arrays give an empty list; iterations are capped', () {
      expect(value('@Each("x", "t", t)'), isEmpty);
      final r = run('root = Stack([Table([Col("c", @Each(xs, "x", x))])])\nxs = [1, 2, 3, 4]', maxEach: 2);
      expect(r.root.toString(), contains('[1, 2]'));
    });
  });

  group('references', () {
    test('a cycle through computed expressions is null, not a crash', () {
      expect(value('a', program: 'a = b + 1\nb = a + 1'), 2);
    });
    test('unresolved references are left out of arrays, also in computed expressions', () {
      expect(value('@Count([a, b])', program: 'a = 1'), 1);
      expect(value('[a, null]', program: 'a = 1'), [1, null]);
    });
    test('queries read their defaults and mutations are idle before any data', () {
      const p = 'q = Query("t", {}, {rows: [1]})\nm = Mutation("t", {})';
      expect(value('q.rows', program: p), [1]);
      expect(value('m.status', program: p), 'idle');
      expect(value('Query("t", {}, {}) == null'), isTrue);
    });
    test('host data replaces query defaults', () {
      final r = parseProgram(library, 'q = Query("t", {}, {rows: []})\nroot = Stack([])');
      final ev = Evaluator(r, library, resolveData: (id) => id == 'q' ? {'rows': [1, 2]} : null);
      expect(ev.evaluateExpression('@Count(q.rows)'), 2);
    });
    test('runaway depth is a runtime error on the prop, not a crash', () {
      final chain = [for (var i = 0; i < 100; i++) 'v$i = v${i + 1} + 1'].join('\n');
      final r = run('root = Stack([Text("" + v0)])\n$chain\nv100 = 0');
      expect(r.errors.map((e) => e.code), contains(ErrorCode.runtimeError));
      expect(r.root, {
        'type': 'Stack',
        'props': {
          'children': [
            {'type': 'Text', 'props': <String, Object?>{}},
          ],
        },
      });
    });
  });

  group('custom functions', () {
    test('a throwing function is a runtime error and null', () {
      final r = run('root = Stack([Text(@Upper("x"))])', functions: {'Upper': (_) => throw StateError('boom')});
      expect(r.errors.single.code, ErrorCode.runtimeError);
      expect(r.errors.single.statementId, 'root');
    });
    test('a wrong return type is a runtime error and null', () {
      final r = run('root = Stack([Text(@Upper("x"))])', functions: {'Upper': (_) => 5});
      expect(r.errors.single.code, ErrorCode.runtimeError);
    });
    test('a runtime argument of the wrong type is a runtime error', () {
      final r = run('root = Stack([Text(@Upper(n))])\nn = 5');
      expect(r.errors.single.code, ErrorCode.runtimeError);
    });
    test('an unregistered library function evaluates to null', () {
      final r = parseProgram(library, 'root = Stack([])');
      expect(Evaluator(r, library).evaluateExpression('@Upper("x")'), isNull);
    });
    test('an unknown function inside an expression is reported when parsing', () {
      final r = run('root = Stack([Text("a" + @Nope())])');
      expect(r.errors.map((e) => e.code), [ErrorCode.unknownFunction]);
    });
  });

  group('state', () {
    test('expression defaults read earlier defaults and plain statements once', () {
      final r = parseProgram(library, r'''
$price = 100
$tax = $price * 0.18
$late = $later + 1
$later = 5
$total = base + 1
$f = @Upper("x")
$q = data.rows
data = Query("t", {}, {rows: [1]})
base = 10
root = Stack([])
''');
      expect(r.state, {
        r'$price': 100,
        r'$tax': 18,
        r'$late': 1,
        r'$later': 5,
        r'$total': 11,
        r'$f': null,
        r'$q': null,
      });
    });
    test('undeclared names are declared with null, including @Set targets', () {
      final r = parseProgram(library, r'root = Stack([Button("x", @Set($picked, 1)), Text($shown)])');
      expect(r.state, {r'$picked': null, r'$shown': null});
    });
    test(r'a $name still being typed at the end of the stream is not declared yet', () {
      final p = StreamingParser(library);
      expect(p.set(r'root = Stack([Text($na').state, isNot(contains(r'$na')));
      expect(p.end().state, contains(r'$na'));
    });
    test('two-way bindings read and write the store', () {
      final store = StateStore();
      final r = run(r'''
$q = "a"
root = Stack([Input("q", "Q", $q), Text($q)])
''', store: store);
      expect(((r.root! as Map)['props'] as Map)['children'], [
        {
          'type': 'Input',
          'props': {
            'name': 'q',
            'placeholder': 'Q',
            'value': {r'$binding': r'$q'},
          },
        },
        {
          'type': 'Text',
          'props': {'text': 'a'},
        },
      ]);
      store.set(r'$q', 'typed');
      expect(r.ev.summarize(r.ev.evaluateRoot().root).toString(), contains('text: typed'));
    });
    test('re-parsing keeps what the user typed', () {
      final store = StateStore();
      run(r'''
$q = "a"
root = Stack([])
''', store: store);
      store.set(r'$q', 'typed');
      run(r'''
$q = "b"
root = Stack([])
''', store: store);
      expect(store.get(r'$q'), 'typed');
    });
  });

  group('queries', () {
    test('queries that read each other report query-cycle', () {
      final r = parseProgram(library, '''
a = Query("t", {x: b.v}, {})
b = Query("t", {x: mid}, {})
mid = a.v
c = Query("t", {x: a.v}, {})
root = Stack([])
''');
      expect(r.errors.map((e) => e.code), [ErrorCode.queryCycle]);
      expect(r.errors.single.statementId, 'a');
    });
    test('a query that reads itself is a cycle', () {
      final r = parseProgram(library, 'a = Query("t", {x: a.v}, {})\nroot = Stack([])');
      expect(r.errors.map((e) => e.code), [ErrorCode.queryCycle]);
    });
  });

  group('actions', () {
    test('an invalid custom action argument makes an empty action', () {
      final r = run('root = Stack([Button("x", @CopyToClipboard(n))])\nn = 5');
      expect(r.errors.map((e) => e.code), [ErrorCode.runtimeError]);
      expect(r.root.toString(), contains('actions: []'));
    });
    test('a custom action with a null required argument does nothing, with no error', () {
      final r = run(r'root = Stack([Button("x", @CopyToClipboard($none))])');
      expect(r.errors, isEmpty);
      expect(r.root.toString(), contains('actions: []'));
    });
    test('Run needs a query or mutation reference', () {
      final r = run('root = Stack([Button("x", @Run(nope)), Button("y", @Run(m))])\nm = Mutation("t", {})');
      expect(r.root.toString(), contains('actions: []'));
      expect(r.root.toString(), contains('action: Run, args: [m]'));
    });
    test('Set evaluates its value against the current state', () {
      final r = run(r'''
$n = 1
root = Stack([Button("x", @Set($n, $n + 1))])
''');
      final action = (((r.ev.evaluateRoot().root!.props['children']! as List).single as Element).props['action'])!
          as ActionValue;
      final set = action.steps.single as SetStep;
      expect(set.target, r'$n');
      expect(r.ev.evaluateStepValue(set), 2);
    });
  });
}
