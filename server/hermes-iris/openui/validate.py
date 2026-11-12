"""Turns a program into a validated tree and reports mistakes (language.md 2.3, 8), then applies the server's stricter
policy and limits and renders the problems as short lines a model can act on.

Two layers, on purpose:

* :func:`parse_program` is the language: it follows the spec and the Dart implementation, removes the smallest unit
  that is wrong, and reports it. The vendored fixtures test this layer.
* :func:`validate_program` is the plugin's policy for what a *model* may submit through ``iris_ui``: anything the
  language would silently drop (an unknown component, an unreferenced statement, a name nothing defines) is a rejection
  with a reason, so the model fixes it instead of showing the person a quietly smaller display. It also enforces the
  size limits.

Values needing evaluation stay :class:`Deferred`; the server never evaluates (that is the client's job).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from . import lexer as L
from .errors import ErrorCode, OpenUiError
from .library import ComponentSpec, Library
from .nodes import (
    ArrayExpr,
    AssignExpr,
    BinaryExpr,
    Binding,
    BoolLit,
    CallExpr,
    Deferred,
    Element,
    Expr,
    FnExpr,
    IndexExpr,
    MemberExpr,
    NullLit,
    NumLit,
    ObjectExpr,
    RefExpr,
    StrLit,
    TernaryExpr,
    UnaryExpr,
)
from .parser import Program, StatementKind, parse, referenced_names

#: The built-ins in the order the reference prints them (for the "Available:" hint).
_BUILTIN_ORDER = ["Count", "First", "Last", "Sum", "Avg", "Min", "Max", "Filter", "Sort", "Round", "Abs", "Floor", "Ceil", "Each"]
BUILTIN_FUNCTIONS = frozenset(_BUILTIN_ORDER)
BUILTIN_ACTIONS = frozenset({"Set", "Reset", "Run", "ToAssistant", "OpenUrl"})
_ACTION_DEFS = frozenset({"ActionExpression", "OpenUrl", "ToAssistant"})


class _Sentinel:
    __slots__ = ("name",)

    def __init__(self, name: str) -> None:
        self.name = name

    def __repr__(self) -> str:
        return f"<{self.name}>"


_DROP = _Sentinel("drop")
_MISSING = _Sentinel("missing")
_BAD = _Sentinel("bad")
_ABSENT = _Sentinel("absent")


@dataclass
class ParseResult:
    #: The validated tree: an :class:`Element`, a :class:`Deferred` entry, or None when nothing renders.
    tree: Any
    errors: list[OpenUiError]
    unresolved: set[str]
    orphans: set[str]
    #: True when the input ended inside an unclosed string or bracket.
    incomplete: bool
    program: Program | None = None

    @property
    def statement_count(self) -> int:
        return len(self.program.statements) if self.program else 0


def parse_program(library: Library, text: str) -> ParseResult:
    """Parse and validate a finished program (a batch parse is an ended one-chunk stream, spec rule 7)."""
    outcome = parse(library, text)
    if outcome.program is None:
        return ParseResult(None, outcome.errors, set(), set(), outcome.incomplete, None)
    m = _Materializer(outcome.program, library)
    tree, errors, unresolved = m.run()
    return ParseResult(tree, errors, unresolved, outcome.program.orphans, outcome.incomplete, outcome.program)


# ---- schema checks ------------------------------------------------------------------------------------------------


def _json_equal(a: Any, b: Any) -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    return a == b


def _is_num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


class _SchemaCheck:
    def __init__(self, lib: Library) -> None:
        self.lib = lib

    def resolve(self, schema: dict[str, Any]) -> dict[str, Any]:
        s = schema
        for _ in range(8):
            ref = s.get("$ref")
            if not isinstance(ref, str):
                return s
            name = ref.split("/")[-1]
            if name in self.lib.components or name in self.lib.actions or name in _ACTION_DEFS:
                return s
            definition = self.lib.defs.get(name)
            if not isinstance(definition, dict):
                return s
            s = definition
        return s

    def accepts(self, raw: dict[str, Any], v: Any) -> bool:
        if isinstance(v, (Deferred, Binding)):
            return True
        s = self.resolve(raw)
        ref = s.get("$ref")
        if isinstance(ref, str):
            name = ref.split("/")[-1]
            if name in self.lib.components:
                return isinstance(v, Element)
            return isinstance(v, list)  # an action: Dart also accepts its evaluated ActionValue, which never exists here
        any_of = s.get("anyOf")
        if isinstance(any_of, list):
            return any(isinstance(a, dict) and self.accepts(a, v) for a in any_of)
        enum = s.get("enum")
        if isinstance(enum, list) and not any(_json_equal(x, v) for x in enum):
            return False
        if "const" in s and not _json_equal(s["const"], v):
            return False
        t = s.get("type")
        if t == "string":
            return isinstance(v, str)
        if t == "number":
            return _is_num(v)
        if t == "integer":
            return _is_num(v) and float(v).is_integer()
        if t == "boolean":
            return isinstance(v, bool)
        if t == "array":
            if not isinstance(v, list):
                return False
            items = s.get("items")
            return not isinstance(items, dict) or all(x is None or self.accepts(items, x) for x in v)
        if t == "object":
            return isinstance(v, dict)
        if t == "null":
            return v is None
        return True


# ---- the materializer ---------------------------------------------------------------------------------------------


def _signature(spec: ComponentSpec) -> str:
    return f"{spec.name}({', '.join(p.name + '*' if p.required else p.name for p in spec.props)}). * marks required"


class _Materializer:
    def __init__(self, program: Program, lib: Library) -> None:
        self.program = program
        self.lib = lib
        self.errors: list[OpenUiError] = []
        self.unresolved: set[str] = set()
        self._stack: list[str] = []
        self._check = _SchemaCheck(lib)

    def run(self) -> tuple[Any, list[OpenUiError], set[str]]:
        entry = self.program.entry
        if entry is None:
            if self.program.statements:
                self.errors.append(OpenUiError(ErrorCode.NO_ROOT, message="no root statement"))
            return None, self.errors, self.unresolved
        self._stack.append(entry)
        v = self._value(self.program.statements[entry].expr, entry, True)
        self._stack.pop()
        # State, query and mutation statements may reference value statements; walk them for unresolved names.
        for s in self.program.statements.values():
            if s.kind != StatementKind.VALUE:
                self._scan(s.expr)
        if isinstance(v, (Element, Deferred)):
            if self.program.entry_is_fallback:
                self.errors.append(
                    OpenUiError(
                        ErrorCode.NO_ROOT,
                        message="no root statement; rendering the first statement that calls the root component",
                        warning=True,
                    )
                )
            return v, self.errors, self.unresolved
        self.errors.append(OpenUiError(ErrorCode.NO_ROOT, message="root does not give a component"))
        return None, self.errors, self.unresolved

    def _scan(self, e: Expr) -> None:
        for n in referenced_names(e):
            if n not in self.program.statements:
                self.unresolved.add(n)

    def _defer(self, e: Expr, sid: str) -> Deferred:
        self._check_calls(e, sid)
        self._scan(e)
        return Deferred(e, sid)

    def _check_calls(self, e: Expr, sid: str) -> None:
        """Reports unknown functions and bad literal arguments of custom functions anywhere inside ``e``."""

        def walk(x: Expr) -> None:
            if isinstance(x, FnExpr):
                self._check_fn(x, sid)
                for a in x.args:
                    walk(a)
            elif isinstance(x, CallExpr):
                for a in x.args:
                    walk(a)
            elif isinstance(x, ArrayExpr):
                for a in x.items:
                    walk(a)
            elif isinstance(x, ObjectExpr):
                for _, v in x.entries:
                    walk(v)
            elif isinstance(x, MemberExpr):
                walk(x.object)
            elif isinstance(x, IndexExpr):
                walk(x.object)
                walk(x.index)
            elif isinstance(x, UnaryExpr):
                walk(x.operand)
            elif isinstance(x, BinaryExpr):
                walk(x.left)
                walk(x.right)
            elif isinstance(x, TernaryExpr):
                walk(x.cond)
                walk(x.then)
                walk(x.otherwise)
            elif isinstance(x, AssignExpr):
                walk(x.value)

        walk(e)

    @staticmethod
    def _clean(v: Any) -> Any:
        return None if v is _DROP or v is _MISSING else v

    def _value(self, e: Expr, sid: str, value_pos: bool) -> Any:
        """``value_pos``: a direct argument of a component call or a direct element of an array."""
        if isinstance(e, (StrLit, NumLit, BoolLit)):
            return e.value
        if isinstance(e, NullLit):
            return None
        if isinstance(e, ArrayExpr):
            out = []
            for i in e.items:
                v = self._value(i, sid, True)
                if v is _DROP or v is _MISSING:
                    continue
                out.append(v)
            return out
        if isinstance(e, ObjectExpr):
            return {k: self._clean(self._value(v, sid, False)) for k, v in e.entries}
        if isinstance(e, CallExpr):
            return self._call(e, sid, value_pos)
        if isinstance(e, RefExpr):
            return Deferred(e, sid) if e.is_state else self._ref(e.name, sid, value_pos)
        if isinstance(e, FnExpr):
            return self._fn(e, sid)
        return self._defer(e, sid)

    def _ref(self, name: str, sid: str, value_pos: bool) -> Any:
        s = self.program.statements.get(name)
        if s is None:
            self.unresolved.add(name)
            return _MISSING
        if name in self._stack:
            self.unresolved.add(name)
            return _MISSING
        if s.kind != StatementKind.VALUE:
            return Deferred(RefExpr(name), sid)
        self._stack.append(name)
        v = self._value(s.expr, name, True)
        self._stack.pop()
        return v

    def _call(self, e: CallExpr, sid: str, value_pos: bool) -> Any:
        if e.name in ("Query", "Mutation"):
            if value_pos:
                self.errors.append(
                    OpenUiError(
                        ErrorCode.INLINE_RESERVED,
                        statement_id=sid,
                        message=f"{e.name} is only valid as a whole statement",
                        hint=f"Write name = {e.name}(...) on its own line and reference name.",
                    )
                )
                return _DROP
            return None
        if e.name == "Action":
            return self._defer(e, sid)
        spec = self.lib.components.get(e.name)
        if spec is None:
            self.errors.append(
                OpenUiError(
                    ErrorCode.UNKNOWN_COMPONENT,
                    statement_id=sid,
                    component=e.name,
                    message=f'unknown component "{e.name}"',
                    hint=f"Available: {', '.join(self.lib.components)}",
                )
            )
            return _DROP if value_pos else None
        return self._component(e, spec, sid)

    def _err(self, code: str, sid: str, spec: ComponentSpec, path: str | None, message: str) -> OpenUiError:
        return OpenUiError(
            code, statement_id=sid, component=spec.name, path=path, message=message, hint=f"Signature: {_signature(spec)}"
        )

    def _component(self, e: CallExpr, spec: ComponentSpec, sid: str) -> Any:
        args = list(e.args)
        if len(args) > len(spec.props):
            self.errors.append(
                self._err(
                    ErrorCode.EXCESS_ARGS, sid, spec, None, f"{spec.name} takes {len(spec.props)} arguments, got {len(args)}"
                )
            )
            args = args[: len(spec.props)]
        props: dict[str, Any] = {}
        for i, p in enumerate(spec.props):
            v: Any = _ABSENT
            if i < len(args):
                arg = args[i]
                if p.bindable and isinstance(arg, RefExpr) and arg.is_state:
                    props[p.name] = Binding(arg.name)
                    continue
                v = self._clean(self._value(arg, sid, True))
                if v is None and isinstance(arg, NullLit) and p.required and not p.has_default:
                    self.errors.append(
                        self._err(ErrorCode.NULL_REQUIRED, sid, spec, f"/{p.name}", f'required "{p.name}" is null')
                    )
                    return _DROP
                if v is not None:
                    c = self._coerce(p.schema, v, sid, spec, f"/{p.name}")
                    v = _ABSENT if c is _BAD else c
                else:
                    v = _ABSENT
            if v is _ABSENT:
                if p.has_default and p.required:
                    props[p.name] = p.default_value
                elif p.required:
                    if i >= len(args):
                        self.errors.append(
                            self._err(
                                ErrorCode.MISSING_REQUIRED, sid, spec, f"/{p.name}", f'missing required field "/{p.name}"'
                            )
                        )
                    return _DROP  # missing, invalid or unresolved: the component cannot render without it
                elif p.has_default and i < len(args):
                    props[p.name] = p.default_value
            else:
                props[p.name] = v
        return Element(spec.name, sid, props)

    def _coerce(self, schema: dict[str, Any], v: Any, sid: str, spec: ComponentSpec, path: str) -> Any:
        """Checks ``v`` against ``schema``. Array items are checked one by one; bad items are removed and reported."""
        s = self._check.resolve(schema)
        if s.get("type") == "array" and isinstance(v, list):
            items = s.get("items")
            if not isinstance(items, dict):
                return v
            out = []
            for i, x in enumerate(v):
                if x is None or self._check.accepts(items, x):
                    out.append(x)
                else:
                    self.errors.append(
                        self._err(ErrorCode.TYPE_MISMATCH, sid, spec, f"{path}/{i}", f'item {i} of "{path}" has the wrong type')
                    )
            return out
        if self._check.accepts(s, v):
            return v
        self.errors.append(self._err(ErrorCode.TYPE_MISMATCH, sid, spec, path, f'"{path}" has the wrong type'))
        return _BAD

    def _fn(self, e: FnExpr, sid: str) -> Any:
        invalid = self._check_fn(e, sid)
        for a in e.args:
            self._check_calls(a, sid)
        self._scan(e)
        if e.name in BUILTIN_FUNCTIONS or e.name in BUILTIN_ACTIONS or e.name in self.lib.actions:
            return Deferred(e, sid)
        return None if invalid else Deferred(e, sid)

    def _check_fn(self, e: FnExpr, sid: str) -> bool:
        """Reports an unknown function, and bad literal arguments of a custom function or action (language.md 3.6,
        6.3). Returns True when the call cannot run: unknown, or a required argument is invalid."""
        if e.name in BUILTIN_FUNCTIONS or e.name in BUILTIN_ACTIONS:
            return False
        fn = self.lib.functions.get(e.name) or self.lib.actions.get(e.name)
        if fn is None:
            names = ", ".join(f"@{n}" for n in [*_BUILTIN_ORDER, *self.lib.functions])
            self.errors.append(
                OpenUiError(
                    ErrorCode.UNKNOWN_FUNCTION,
                    statement_id=sid,
                    message=f"unknown function @{e.name}",
                    hint=f"Available: {names}",
                )
            )
            return True
        args = list(e.args)
        invalid = False

        def fe(code: str, path: str | None, message: str) -> OpenUiError:
            params = ", ".join(p.name + "*" if p.required else p.name for p in fn.params)
            return OpenUiError(
                code, statement_id=sid, path=path, message=message, hint=f"Signature: {fn.name}({params}). * marks required"
            )

        if len(args) > len(fn.params):
            self.errors.append(fe(ErrorCode.EXCESS_ARGS, None, f"@{fn.name} takes {len(fn.params)} arguments"))
            args = args[: len(fn.params)]
        for i, p in enumerate(fn.params):
            if i >= len(args):
                if p.required and not p.has_default:
                    self.errors.append(
                        fe(ErrorCode.MISSING_REQUIRED, f"/{p.name}", f'missing required argument "{p.name}"')
                    )
                    invalid = True
                continue
            a = args[i]
            if not isinstance(a, (StrLit, NumLit, BoolLit)):
                continue
            if not self._check.accepts(p.schema, a.value):
                self.errors.append(fe(ErrorCode.TYPE_MISMATCH, f"/{p.name}", f'argument "{p.name}" has the wrong type'))
                if p.required:
                    invalid = True
        return invalid


# ---- the server's policy ------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Limits:
    """Both sides enforce these (spec, "Limits"): the plugin when a model submits, the app when it renders."""

    max_statements: int = 60
    max_source_bytes: int = 12 * 1024
    #: Nesting of components in the validated tree.
    max_depth: int = 8
    max_string_bytes: int = 2 * 1024
    #: Nesting of brackets in the source, a guard for the recursive parser (not a spec limit).
    max_nesting: int = 64


class ProblemCode:
    EMPTY = "empty"
    ROOT_NOT_COMPONENT = "root-not-component"
    TOO_LARGE = "too-large"
    TOO_MANY_STATEMENTS = "too-many-statements"
    TOO_DEEP = "too-deep"
    STRING_TOO_LONG = "string-too-long"
    UNRESOLVED = "unresolved-reference"
    ORPHAN = "unreferenced-statement"
    UNSUPPORTED = "unsupported"
    UNTERMINATED = "unterminated"


@dataclass
class Validation:
    ok: bool
    problems: list[OpenUiError]
    result: ParseResult | None
    #: One short line per problem, ready for a tool result.
    lines: list[str] = field(default_factory=list)


def _problem(code: str, message: str, statement_id: str | None = None, hint: str | None = None) -> OpenUiError:
    return OpenUiError(code, source="validate", statement_id=statement_id, message=message, hint=hint)


def validate_program(library: Library, code: str, limits: Limits = Limits()) -> Validation:
    """Parse ``code`` and judge it as a model's submission: any problem rejects it, each with a reason."""
    problems: list[OpenUiError] = []

    size = len(code.encode("utf-8", "replace"))
    if size > limits.max_source_bytes:
        problems.append(
            _problem(
                ProblemCode.TOO_LARGE,
                f"the program is {size} bytes; the limit is {limits.max_source_bytes}",
                hint="Show less, or split the idea into a second surface.",
            )
        )
        return _finish(problems, None)

    tokens = L.lex_all(code).tokens
    depth = peak = 0
    for t in tokens:
        if t.kind in (L.LPAREN, L.LBRACKET, L.LBRACE):
            depth += 1
            peak = max(peak, depth)
        elif t.kind in (L.RPAREN, L.RBRACKET, L.RBRACE) and depth > 0:
            depth -= 1
    if peak > limits.max_nesting:
        problems.append(_problem(ProblemCode.TOO_DEEP, f"brackets nest {peak} deep; the limit is {limits.max_nesting}"))
        return _finish(problems, None)
    for t in tokens:
        if t.kind == L.STRING and len(t.value.encode("utf-8", "replace")) > limits.max_string_bytes:
            problems.append(
                _problem(
                    ProblemCode.STRING_TOO_LONG,
                    f"a string is longer than {limits.max_string_bytes} bytes",
                    hint="Put long text in the fallback or split it across components.",
                )
            )
            break

    result = parse_program(library, code)
    problems.extend(result.errors)  # warnings count too: a missing root is a mistake for a model
    if isinstance(result.tree, Deferred):
        problems.append(
            _problem(
                ProblemCode.ROOT_NOT_COMPONENT,
                "root must be a component call, not a computed value",
                statement_id=result.program.entry if result.program else None,
                hint="Write root = Stack([...]) and put any ternary or arithmetic inside it.",
            )
        )
    if result.program is None and not result.errors:
        problems.append(_problem(ProblemCode.EMPTY, "the program is empty", hint="Write root = Stack([...]) first."))
    for name in sorted(result.unresolved):
        problems.append(
            _problem(ProblemCode.UNRESOLVED, f'"{name}" is used but never defined', hint=f"Define {name} = ... on its own line.")
        )
    for name in sorted(result.orphans):
        problems.append(
            _problem(
                ProblemCode.ORPHAN,
                f'"{name}" is defined but nothing uses it, so it will not render',
                statement_id=name,
                hint="Reference it from its parent or delete it.",
            )
        )
    if result.incomplete:
        problems.append(
            _problem(
                ProblemCode.UNTERMINATED,
                "the program ends inside an unclosed string or bracket",
                hint="Close every quote, ( [ and {.",
            )
        )
    if result.program is not None:
        for s in result.program.statements.values():
            if s.kind in (StatementKind.QUERY, StatementKind.MUTATION):
                problems.append(
                    _problem(
                        ProblemCode.UNSUPPORTED,
                        f"{s.kind.value} statements are not available here",
                        statement_id=s.name,
                        hint="Put the data in the program with literals or `data`.",
                    )
                )
        if result.program.statements and len(result.program.statements) > limits.max_statements:
            problems.append(
                _problem(
                    ProblemCode.TOO_MANY_STATEMENTS,
                    f"{len(result.program.statements)} statements; the limit is {limits.max_statements}",
                    hint="Show less, or split the idea into a second surface.",
                )
            )
    deepest = _element_depth(result.tree)
    if deepest > limits.max_depth:
        problems.append(
            _problem(ProblemCode.TOO_DEEP, f"components nest {deepest} deep; the limit is {limits.max_depth}", hint="Flatten it.")
        )
    return _finish(problems, result)


def _element_depth(v: Any, seen: int = 0) -> int:
    """Depth of nested components in a validated tree (an element inside an element counts one level)."""
    if isinstance(v, Element):
        return max([seen + 1, *(_element_depth(x, seen + 1) for x in v.props.values())])
    if isinstance(v, list):
        return max([seen, *(_element_depth(x, seen) for x in v)])
    if isinstance(v, dict):
        return max([seen, *(_element_depth(x, seen) for x in v.values())])
    return seen


def _finish(problems: list[OpenUiError], result: ParseResult | None) -> Validation:
    return Validation(not problems, problems, result, render_problems(problems))


_HINT_MAX = 240
_LINES_MAX = 10


def render_problems(problems: list[OpenUiError]) -> list[str]:
    """Short lines for a model: ``where: what. hint``. At most ten, then a count of the rest."""
    lines = []
    for e in problems[:_LINES_MAX]:
        where = f"{e.statement_id}: " if e.statement_id else ""
        line = f"{where}{e.message}"
        if e.hint:
            hint = e.hint if len(e.hint) <= _HINT_MAX else e.hint[: _HINT_MAX - 1] + "…"
            line += f". {hint}"
        lines.append(line)
    if len(problems) > _LINES_MAX:
        lines.append(f"(and {len(problems) - _LINES_MAX} more)")
    return lines


def summarize(v: Any) -> Any:
    """The tree in the canonical form the conformance fixtures compare (fixtures/README.md). Raises
    :class:`HasDeferred` when the tree holds an expression only the client can evaluate."""
    if isinstance(v, Element):
        return {"type": v.type, "props": {k: summarize(x) for k, x in v.props.items()}}
    if isinstance(v, Binding):
        return {"$binding": v.name}
    if isinstance(v, Deferred):
        raise HasDeferred
    if isinstance(v, list):
        return [summarize(x) for x in v]
    if isinstance(v, dict):
        return {k: summarize(x) for k, x in v.items()}
    if isinstance(v, float) and v.is_integer() and abs(v) < 1e15:
        return int(v)
    return v


class HasDeferred(Exception):
    """The tree has a value that needs evaluation, so the server cannot compare it."""

