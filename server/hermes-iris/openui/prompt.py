"""The system prompt for a library: byte-identical to ``packages/openui_lang/lib/src/prompt.dart`` (and so to OpenUI's
reference generator for the v1 feature set: no tool calls, no edit or inline mode). The goldens in
``packages/openui_lang/test/golden/prompt/`` are the shared test. A pure function of its inputs."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from .library import Library

_DEFAULT_PREAMBLE = (
    "You are an AI assistant that responds using openui-lang, a declarative UI language. "
    "Your ENTIRE response must be valid openui-lang code — no markdown, no explanations, just openui-lang."
)


@dataclass(frozen=True)
class PromptOptions:
    #: Teach ``$variables``, expressions and the ``@Set`` / ``@Reset`` steps.
    bindings: bool = False
    #: List the built-in functions (``@Count``, ``@Sum``, ...). Defaults to ``bindings``.
    builtin_functions: bool | None = None
    #: Replaces the opening paragraph.
    preamble: str | None = None
    #: Worked programs, under ``## Examples``.
    examples: tuple[str, ...] | list[str] = field(default_factory=tuple)
    #: One bullet each, after the final verification list.
    additional_rules: tuple[str, ...] | list[str] = field(default_factory=tuple)


#: (signature, description) of the built-in functions, in prompt order.
_BUILTIN_FUNCTIONS = [
    ("Count(array: any[]) → number", "Returns array length"),
    ("First(array: any[]) → any", "Returns first element of array"),
    ("Last(array: any[]) → any", "Returns last element of array"),
    ("Sum(numbers: number[]) → number", "Sum of numeric array"),
    ("Avg(numbers: number[]) → number", "Average of numeric array"),
    ("Min(numbers: number[]) → number", "Minimum value in array"),
    ("Max(numbers: number[]) → number", "Maximum value in array"),
    (
        'Sort(array: any[], field: string, direction?: "asc" | "desc") → any[]',
        'Sort array by field. Direction: "asc" (default) or "desc"',
    ),
    (
        'Filter(array: any[], field: string, operator: "==" | "!=" | ">" | "<" | ">=" | "<=" | "contains", value: any) → any[]',
        "Filter array by field value",
    ),
    ("Round(number: number | number[], decimals?: number) → number | number[]", "Round to N decimal places (default 0)"),
    ("Abs(number: number | number[]) → number | number[]", "Absolute value"),
    ("Floor(number: number | number[]) → number | number[]", "Round down to nearest integer"),
    ("Ceil(number: number | number[]) → number | number[]", "Round up to nearest integer"),
    (
        "Each(array: any[], varName: string, template: any)",
        "Evaluate template for each element. varName is the loop variable — use it ONLY inside the template expression "
        "(inline). Do NOT create a separate statement for the template.",
    ),
]

#: (name, signature, description) of the built-in action steps that exist without tool calls.
_BUILTIN_STEPS = [
    (
        "ToAssistant",
        "ToAssistant(message: string, context?: any)",
        'Send a message to the assistant (for conversational buttons like "Tell me more", "Explain this"). '
        "The optional context is any value (object, array, string, number) passed to the assistant as hidden data, "
        'e.g. @ToAssistant("Show details", {orderId: 42})',
    ),
    ("OpenUrl", "OpenUrl(url: string)", "Navigate to a URL"),
    ("Set", "Set(variable: $variable, value: any)", "Set a $variable to a specific value"),
    (
        "Reset",
        "Reset(variable: $variable)",
        "Reset $variables to their declared defaults; pass several to reset each "
        '(e.g. @Reset($title, $priority) restores $title="" and $priority="medium")',
    ),
]

_ACTION_HEADER = "## Action — Button Behavior"

# A restricted action slot in a signature, e.g. ``share?: @CopyToClipboard | @OpenUrl``.
_RESTRICTED_SLOT = re.compile(r"[:|] @[A-Z]")


def _needs_bindings(step_name: str) -> bool:
    return step_name in ("Set", "Reset")


@dataclass(frozen=True)
class _Entry:
    signature: str
    description: str | None

    @property
    def line(self) -> str:
        return f"{self.signature} — {self.description}" if self.description else self.signature


def _entries(raw: Any) -> dict[str, _Entry]:
    if not isinstance(raw, dict):
        return {}
    return {k: _Entry(v.get("signature") or "", v.get("description")) for k, v in raw.items() if isinstance(v, dict)}


def generate_system_prompt(library: Library, options: PromptOptions | None = None) -> str:
    """Builds the system prompt for ``library``. The same library and options always give the same bytes."""
    options = options or PromptOptions()
    data = library.json
    root = library.root or "Root"
    components = _entries(data.get("components"))
    functions = _entries(data.get("functions"))
    actions = _entries(data.get("actions"))
    bindings = options.bindings
    expressions = bindings  # no tool calls in v1, so expressions exist exactly when bindings do

    uses_action_expression = any(
        "ActionExpression" in c.signature or _RESTRICTED_SLOT.search(c.signature) for c in components.values()
    )

    parts: list[str] = [
        options.preamble if options.preamble is not None else _DEFAULT_PREAMBLE,
        "",
        _syntax_rules(root, expressions, bindings),
        "",
        _component_signatures(
            data.get("componentGroups"), components, actions, bindings=bindings, uses_action_expression=uses_action_expression
        ),
    ]

    custom_functions = [f"@{f.line}" for f in functions.values()]
    builtins = options.builtin_functions if options.builtin_functions is not None else expressions
    if builtins:
        parts += ["", _builtin_functions_section(custom_functions)]
    elif custom_functions:
        parts += ["", "## Built-in Functions\n\n" + "\n".join(custom_functions)]

    custom_actions = [f"- @{a.line}" for a in actions.values()]
    if uses_action_expression:
        parts += ["", _action_section(bindings, custom_actions)]
    elif custom_actions:
        parts += [
            "",
            f"{_ACTION_HEADER}\n\nPass one step, or Action([...]) with several steps, as a button's action."
            "\n\nAvailable steps:\n" + "\n".join(custom_actions),
        ]

    parts += ["", _streaming_rules(root, expressions)]

    if options.examples:
        parts += ["", "## Examples", ""]
        for example in options.examples:
            parts += [example, ""]

    parts.append(_important_rules(root, bindings))

    if options.additional_rules:
        parts.append("")
        parts += [f"- {rule}" for rule in options.additional_rules]

    return "\n".join(parts)


def _syntax_rules(root: str, expressions: bool, bindings: bool) -> str:
    lines = [
        "## Syntax Rules",
        "",
        "1. Each statement is on its own line: `identifier = Expression`",
        f"2. `root` is the entry point — every program must define `root = {root}(...)`",
        '3. Expressions are: strings ("..."), numbers, booleans (true/false), null, arrays ([...]), objects ({...}), '
        "or component calls TypeName(arg1, arg2, ...)",
        "4. Use references for readability: define `name = ...` on one line, then use `name` later",
        "5. EVERY variable (except root) MUST be referenced by at least one other variable. Unreferenced variables are "
        "silently dropped and will NOT render. Always include defined variables in their parent's children/items array.",
        '6. Arguments are POSITIONAL (order matters, not names). Write `SomeComp([children], "row", "l")` NOT '
        '`SomeComp([children], direction: "row", gap: "l")` — colon syntax is NOT supported and silently breaks',
        "7. Optional arguments can be omitted from the end",
    ]
    n = 8
    if bindings:
        lines.append(
            f"{n}. Declare mutable state with `$varName = defaultValue`. Components marked with `$binding` can read/write "
            "these. Undeclared $variables are auto-created with null default."
        )
        n += 1
    if expressions:
        for text in (
            'String concatenation: `"text" + $var + "more"`',
            "Dot member access: `query.field` reads a field; on arrays it extracts that field from every element",
            "Index access: `arr[0]`, `data[index]`",
            "Arithmetic operators: +, -, *, /, % (work on numbers; + is string concat when either side is a string)",
            "Comparison: ==, !=, >, <, >=, <=",
            "Logical: &&, ||, ! (prefix)",
            "Ternary: `condition ? valueIfTrue : valueIfFalse`",
            "Parentheses for grouping: `(a + b) * c`",
        ):
            lines.append(f"{n}. {text}")
            n += 1
    lines.append("- Strings use double quotes with backslash escaping")
    return "\n".join(lines)


def _component_signatures(
    groups_raw: Any,
    components: dict[str, _Entry],
    actions: dict[str, _Entry],
    *,
    bindings: bool,
    uses_action_expression: bool,
) -> str:
    lines = [
        "## Component Signatures",
        "",
        "Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming.",
    ]
    if uses_action_expression:
        steps = [f"@{s[0]}" for s in _BUILTIN_STEPS if bindings or not _needs_bindings(s[0])] + [f"@{n}" for n in actions]
        lines.append(
            "Props typed `ActionExpression` accept one @step, or Action([@steps...]) for several. "
            f"See the Action section for available steps ({', '.join(steps)})."
        )
        if any(_RESTRICTED_SLOT.search(c.signature) for c in components.values()):
            lines.append("Props typed like `@OpenUrl | @ToAssistant` accept only the steps listed.")
    if bindings or any("$binding" in c.signature for c in components.values()):
        lines.append("Props marked `$binding<type>` accept a `$variable` reference for two-way binding.")

    groups = [g for g in groups_raw if isinstance(g, dict)] if isinstance(groups_raw, list) else []
    if groups:
        grouped: set[str] = set()
        for group in groups:
            lines += ["", f"### {group.get('name')}"]
            for name in group.get("components") or []:
                if name in grouped:
                    continue
                component = components.get(name)
                if component is None:
                    continue
                grouped.add(name)
                lines.append(component.line)
            lines += list(group.get("notes") or [])
        ungrouped = [n for n in components if n not in grouped]
        if ungrouped:
            lines += ["", "### Other"]
            lines += [components[n].line for n in ungrouped]
    else:
        lines.append("")
        lines += [c.line for c in components.values()]
    return "\n".join(lines)


def _builtin_functions_section(custom: list[str]) -> str:
    lines = "\n".join([*(f"@{sig} — {desc}" for sig, desc in _BUILTIN_FUNCTIONS), *custom])
    return f"""## Built-in Functions

Data functions prefixed with `@` to distinguish from components. These are the ONLY functions available — do NOT invent new ones.
Use @-prefixed built-in functions (@Count, @Sum, @Avg, @Min, @Max, @Round) on data. Do NOT hardcode computed values.

{lines}

Builtins compose — output of one is input to the next:
`@Count(@Filter(data.rows, "field", "==", "val"))` for KPIs/chart values, `@Round(@Avg(data.rows.score), 1)`, `@Each(data.rows, "item", Comp(item.field))` for per-item rendering.
Array pluck: `data.rows.field` extracts a field from every row → use with @Sum, @Avg, charts, tables.

IMPORTANT @Each rule: The loop variable (e.g. "item") is ONLY available inside the @Each template expression. Always inline the template — do NOT extract it to a separate statement.
CORRECT: `list = @Each(rows, "t", Comp(t.name))`
WRONG: `item = Comp(t.name)` then `list = @Each(rows, "t", item)`, because t is undefined in item."""


def _action_section(bindings: bool, custom_actions: list[str]) -> str:
    steps = [f"- @{sig} — {desc}" for name, sig, desc in _BUILTIN_STEPS if bindings or not _needs_bindings(name)]
    steps += custom_actions
    steps_text = "\n".join(steps)
    return f"""{_ACTION_HEADER}

An action wires a button click to operations. Pass one @-prefixed step bare, e.g. Button("Ask", @ToAssistant("Tell me more")). Put several steps in Action([...]), e.g. Button("Read", Action([@OpenUrl("https://example.com"), @ToAssistant("Summarize this page")])). Steps execute in order.
Buttons without an action automatically send their label to the assistant (equivalent to @ToAssistant(label)).

Available steps:
{steps_text}

Example — simple nav:
```
viewBtn = Button("View", @OpenUrl("https://example.com"))
```

- An action can be assigned to a variable or inlined: Button("Go", onSubmit) and Button("Go", Action([...])) both work"""


def _streaming_rules(root: str, expressions: bool) -> str:
    steps = [f"1. `root = {root}(...)` — UI shell appears immediately"]
    if expressions:
        steps += [
            "2. $variable declarations — state ready for bindings",
            "3. Component definitions — fill in with data already available",
            "4. Data values — leaf content last",
        ]
    else:
        steps += ["2. Component definitions — fill in as they stream", "3. Data values — leaf content last"]
    steps_text = "\n".join(steps)
    return f"""## Hoisting & Streaming (CRITICAL)

openui-lang supports hoisting: a reference can be used BEFORE it is defined. The parser resolves all references after the full input is parsed.

During streaming, the output is re-parsed on every chunk. Undefined references are temporarily unresolved and appear once their definitions stream in. This creates a progressive top-down reveal — structure first, then data fills in.

**Recommended statement order for optimal streaming:**
{steps_text}

Always write the root = {root}(...) statement first so the UI shell appears immediately, even before child data has streamed in."""


def _important_rules(root: str, bindings: bool) -> str:
    verify = [
        f"1. root = {root}(...) is the FIRST line (for optimal streaming).",
        "2. Every referenced name is defined. Every defined name (other than root) is reachable from root.",
    ]
    if bindings:
        verify.append("3. Every $binding appears in at least one component or expression.")
    verify_text = "\n".join(verify)
    return f"""## Important Rules
- Choose components that best represent the content (tables for comparisons, charts for trends, forms for input, etc.)

## Final Verification
Before finishing, walk your output and verify:
{verify_text}"""
