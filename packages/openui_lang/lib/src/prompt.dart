/// The system prompt for a library: the same text as OpenUI's reference `generateSystemPrompt` for the v1 feature set
/// (no tool calls, no edit or inline mode), byte for byte. Everything is a pure function of its inputs.
library;

import 'library_spec.dart';

/// What the prompt teaches beyond the component list. Only features this client supports exist here.
class PromptOptions {
  const PromptOptions({
    this.bindings = false,
    this.builtinFunctions,
    this.preamble,
    this.examples = const [],
    this.additionalRules = const [],
  });

  /// Teach `$variables`, expressions and the `@Set` / `@Reset` steps.
  final bool bindings;

  /// List the built-in functions (`@Count`, `@Sum`, ...). Defaults to [bindings].
  final bool? builtinFunctions;

  /// Replaces the opening paragraph.
  final String? preamble;

  /// Worked programs, under `## Examples`.
  final List<String> examples;

  /// One bullet each, after the final verification list.
  final List<String> additionalRules;
}

const _defaultPreamble =
    'You are an AI assistant that responds using openui-lang, a declarative UI language. Your ENTIRE response must be valid openui-lang code — no markdown, no explanations, just openui-lang.';

/// `(signature, description)` of the built-in functions, in prompt order.
const _builtinFunctions = <(String, String)>[
  ('Count(array: any[]) → number', 'Returns array length'),
  ('First(array: any[]) → any', 'Returns first element of array'),
  ('Last(array: any[]) → any', 'Returns last element of array'),
  ('Sum(numbers: number[]) → number', 'Sum of numeric array'),
  ('Avg(numbers: number[]) → number', 'Average of numeric array'),
  ('Min(numbers: number[]) → number', 'Minimum value in array'),
  ('Max(numbers: number[]) → number', 'Maximum value in array'),
  (
    'Sort(array: any[], field: string, direction?: "asc" | "desc") → any[]',
    'Sort array by field. Direction: "asc" (default) or "desc"',
  ),
  (
    'Filter(array: any[], field: string, operator: "==" | "!=" | ">" | "<" | ">=" | "<=" | "contains", value: any) → any[]',
    'Filter array by field value',
  ),
  (
    'Round(number: number | number[], decimals?: number) → number | number[]',
    'Round to N decimal places (default 0)',
  ),
  ('Abs(number: number | number[]) → number | number[]', 'Absolute value'),
  (
    'Floor(number: number | number[]) → number | number[]',
    'Round down to nearest integer',
  ),
  (
    'Ceil(number: number | number[]) → number | number[]',
    'Round up to nearest integer',
  ),
  (
    'Each(array: any[], varName: string, template: any)',
    'Evaluate template for each element. varName is the loop variable — use it ONLY inside the template expression (inline). Do NOT create a separate statement for the template.',
  ),
];

/// `(name, signature, description)` of the built-in action steps that exist without tool calls.
const _builtinSteps = <(String, String, String)>[
  (
    'ToAssistant',
    'ToAssistant(message: string, context?: any)',
    'Send a message to the assistant (for conversational buttons like "Tell me more", "Explain this"). The optional context is any value (object, array, string, number) passed to the assistant as hidden data, e.g. @ToAssistant("Show details", {orderId: 42})',
  ),
  ('OpenUrl', 'OpenUrl(url: string)', 'Navigate to a URL'),
  (
    'Set',
    'Set(variable: \$variable, value: any)',
    'Set a \$variable to a specific value',
  ),
  (
    'Reset',
    'Reset(variable: \$variable)',
    'Reset \$variables to their declared defaults; pass several to reset each (e.g. @Reset(\$title, \$priority) restores \$title="" and \$priority="medium")',
  ),
];

bool _needsBindings(String stepName) =>
    stepName == 'Set' || stepName == 'Reset';

const _actionHeader = '## Action — Button Behavior';

// A restricted action slot in a signature, e.g. `share?: @CopyToClipboard | @OpenUrl`.
final _restrictedSlot = RegExp(r'[:|] @[A-Z]');

class _Entry {
  const _Entry(this.signature, this.description);
  final String signature;
  final String? description;

  String get line =>
      (description ?? '').isNotEmpty ? '$signature — $description' : signature;
}

Map<String, _Entry> _entries(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      e.key as String: _Entry(
        ((e.value as Map)['signature'] as String?) ?? '',
        (e.value as Map)['description'] as String?,
      ),
  };
}

/// Builds the system prompt for [library]. The same library and options always give the same bytes.
String generateSystemPrompt(
  LibrarySpec library, {
  PromptOptions options = const PromptOptions(),
}) {
  final json = library.json;
  final root = library.root ?? 'Root';
  final components = _entries(json['components']);
  final functions = _entries(json['functions']);
  final actions = _entries(json['actions']);
  final bindings = options.bindings;
  final expressions =
      bindings; // no tool calls in v1, so expressions exist exactly when bindings do

  final usesActionExpression = components.values.any(
    (c) =>
        c.signature.contains('ActionExpression') ||
        _restrictedSlot.hasMatch(c.signature),
  );

  final parts = <String>[
    options.preamble ?? _defaultPreamble,
    '',
    _syntaxRules(root, expressions: expressions, bindings: bindings),
    '',
    _componentSignatures(
      json['componentGroups'],
      components,
      actions,
      bindings: bindings,
      usesActionExpression: usesActionExpression,
    ),
  ];

  final customFunctions = functions.values.map((f) => '@${f.line}').toList();
  if (options.builtinFunctions ?? expressions) {
    parts
      ..add('')
      ..add(_builtinFunctionsSection(customFunctions));
  } else if (customFunctions.isNotEmpty) {
    parts
      ..add('')
      ..add('## Built-in Functions\n\n${customFunctions.join('\n')}');
  }

  final customActions = actions.values.map((a) => '- @${a.line}').toList();
  if (usesActionExpression) {
    parts
      ..add('')
      ..add(_actionSection(bindings, customActions));
  } else if (customActions.isNotEmpty) {
    parts
      ..add('')
      ..add(
        "$_actionHeader\n\nPass one step, or Action([...]) with several steps, as a button's action.\n\nAvailable steps:\n${customActions.join('\n')}",
      );
  }

  parts
    ..add('')
    ..add(_streamingRules(root, expressions: expressions));

  if (options.examples.isNotEmpty) {
    parts
      ..add('')
      ..add('## Examples')
      ..add('');
    for (final example in options.examples) {
      parts
        ..add(example)
        ..add('');
    }
  }

  parts.add(_importantRules(root, bindings: bindings));

  if (options.additionalRules.isNotEmpty) {
    parts.add('');
    for (final rule in options.additionalRules) {
      parts.add('- $rule');
    }
  }

  return parts.join('\n');
}

String _syntaxRules(
  String root, {
  required bool expressions,
  required bool bindings,
}) {
  final lines = <String>[
    '## Syntax Rules',
    '',
    '1. Each statement is on its own line: `identifier = Expression`',
    '2. `root` is the entry point — every program must define `root = $root(...)`',
    '3. Expressions are: strings ("..."), numbers, booleans (true/false), null, arrays ([...]), objects ({...}), or component calls TypeName(arg1, arg2, ...)',
    '4. Use references for readability: define `name = ...` on one line, then use `name` later',
    "5. EVERY variable (except root) MUST be referenced by at least one other variable. Unreferenced variables are silently dropped and will NOT render. Always include defined variables in their parent's children/items array.",
    '6. Arguments are POSITIONAL (order matters, not names). Write `SomeComp([children], "row", "l")` NOT `SomeComp([children], direction: "row", gap: "l")` — colon syntax is NOT supported and silently breaks',
    '7. Optional arguments can be omitted from the end',
  ];
  var n = 8;
  if (bindings) {
    lines.add(
      '${n++}. Declare mutable state with `\$varName = defaultValue`. Components marked with `\$binding` can read/write these. Undeclared \$variables are auto-created with null default.',
    );
  }
  if (expressions) {
    lines.addAll([
      '${n++}. String concatenation: `"text" + \$var + "more"`',
      '${n++}. Dot member access: `query.field` reads a field; on arrays it extracts that field from every element',
      '${n++}. Index access: `arr[0]`, `data[index]`',
      '${n++}. Arithmetic operators: +, -, *, /, % (work on numbers; + is string concat when either side is a string)',
      '${n++}. Comparison: ==, !=, >, <, >=, <=',
      '${n++}. Logical: &&, ||, ! (prefix)',
      '${n++}. Ternary: `condition ? valueIfTrue : valueIfFalse`',
      '${n++}. Parentheses for grouping: `(a + b) * c`',
    ]);
  }
  lines.add('- Strings use double quotes with backslash escaping');
  return lines.join('\n');
}

String _componentSignatures(
  Object? groupsRaw,
  Map<String, _Entry> components,
  Map<String, _Entry> actions, {
  required bool bindings,
  required bool usesActionExpression,
}) {
  final lines = <String>[
    '## Component Signatures',
    '',
    'Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming.',
  ];
  if (usesActionExpression) {
    final steps = [
      for (final s in _builtinSteps)
        if (bindings || !_needsBindings(s.$1)) '@${s.$1}',
      for (final name in actions.keys) '@$name',
    ];
    lines.add(
      'Props typed `ActionExpression` accept one @step, or Action([@steps...]) for several. See the Action section for available steps (${steps.join(', ')}).',
    );
    if (components.values.any((c) => _restrictedSlot.hasMatch(c.signature))) {
      lines.add(
        'Props typed like `@OpenUrl | @ToAssistant` accept only the steps listed.',
      );
    }
  }
  if (bindings ||
      components.values.any((c) => c.signature.contains('\$binding'))) {
    lines.add(
      'Props marked `\$binding<type>` accept a `\$variable` reference for two-way binding.',
    );
  }

  final groups = groupsRaw is List
      ? groupsRaw.whereType<Map<String, Object?>>().toList()
      : const <Map<String, Object?>>[];
  if (groups.isNotEmpty) {
    final grouped = <String>{};
    for (final group in groups) {
      lines
        ..add('')
        ..add('### ${group['name']}');
      for (final name
          in ((group['components'] as List?) ?? const []).cast<String>()) {
        if (grouped.contains(name)) continue;
        final component = components[name];
        if (component == null) continue;
        grouped.add(name);
        lines.add(component.line);
      }
      for (final note
          in ((group['notes'] as List?) ?? const []).cast<String>()) {
        lines.add(note);
      }
    }
    final ungrouped = components.keys
        .where((n) => !grouped.contains(n))
        .toList();
    if (ungrouped.isNotEmpty) {
      lines
        ..add('')
        ..add('### Other');
      for (final name in ungrouped) {
        lines.add(components[name]!.line);
      }
    }
  } else {
    lines.add('');
    for (final component in components.values) {
      lines.add(component.line);
    }
  }
  return lines.join('\n');
}

String _builtinFunctionsSection(List<String> custom) {
  final lines = [
    for (final f in _builtinFunctions) '@${f.$1} — ${f.$2}',
    ...custom,
  ].join('\n');
  return '''## Built-in Functions

Data functions prefixed with `@` to distinguish from components. These are the ONLY functions available — do NOT invent new ones.
Use @-prefixed built-in functions (@Count, @Sum, @Avg, @Min, @Max, @Round) on data. Do NOT hardcode computed values.

$lines

Builtins compose — output of one is input to the next:
`@Count(@Filter(data.rows, "field", "==", "val"))` for KPIs/chart values, `@Round(@Avg(data.rows.score), 1)`, `@Each(data.rows, "item", Comp(item.field))` for per-item rendering.
Array pluck: `data.rows.field` extracts a field from every row → use with @Sum, @Avg, charts, tables.

IMPORTANT @Each rule: The loop variable (e.g. "item") is ONLY available inside the @Each template expression. Always inline the template — do NOT extract it to a separate statement.
CORRECT: `list = @Each(rows, "t", Comp(t.name))`
WRONG: `item = Comp(t.name)` then `list = @Each(rows, "t", item)`, because t is undefined in item.''';
}

String _actionSection(bool bindings, List<String> customActions) {
  final steps = [
    for (final s in _builtinSteps)
      if (bindings || !_needsBindings(s.$1)) '- @${s.$2} — ${s.$3}',
    ...customActions,
  ];
  return '''$_actionHeader

An action wires a button click to operations. Pass one @-prefixed step bare, e.g. Button("Ask", @ToAssistant("Tell me more")). Put several steps in Action([...]), e.g. Button("Read", Action([@OpenUrl("https://example.com"), @ToAssistant("Summarize this page")])). Steps execute in order.
Buttons without an action automatically send their label to the assistant (equivalent to @ToAssistant(label)).

Available steps:
${steps.join('\n')}

Example — simple nav:
```
viewBtn = Button("View", @OpenUrl("https://example.com"))
```

- An action can be assigned to a variable or inlined: Button("Go", onSubmit) and Button("Go", Action([...])) both work''';
}

String _streamingRules(String root, {required bool expressions}) {
  final steps = <String>[
    '1. `root = $root(...)` — UI shell appears immediately',
  ];
  if (expressions) {
    steps
      ..add('2. \$variable declarations — state ready for bindings')
      ..add('3. Component definitions — fill in with data already available')
      ..add('4. Data values — leaf content last');
  } else {
    steps
      ..add('2. Component definitions — fill in as they stream')
      ..add('3. Data values — leaf content last');
  }
  return '''## Hoisting & Streaming (CRITICAL)

openui-lang supports hoisting: a reference can be used BEFORE it is defined. The parser resolves all references after the full input is parsed.

During streaming, the output is re-parsed on every chunk. Undefined references are temporarily unresolved and appear once their definitions stream in. This creates a progressive top-down reveal — structure first, then data fills in.

**Recommended statement order for optimal streaming:**
${steps.join('\n')}

Always write the root = $root(...) statement first so the UI shell appears immediately, even before child data has streamed in.''';
}

String _importantRules(String root, {required bool bindings}) {
  final verify = <String>[
    '1. root = $root(...) is the FIRST line (for optimal streaming).',
    '2. Every referenced name is defined. Every defined name (other than root) is reachable from root.',
    if (bindings)
      '3. Every \$binding appears in at least one component or expression.',
  ];
  return '''## Important Rules
- Choose components that best represent the content (tables for comparisons, charts for trends, forms for input, etc.)

## Final Verification
Before finishing, walk your output and verify:
${verify.join('\n')}''';
}
