"""Source preparation, statement splitting, the expression parser and the program model (language.md 1.2-1.6, 2).

This is the batch half of the Dart parser: a program is parsed as one chunk of a stream that has ended (spec rule 7),
so the pending text is closed implicitly (an unterminated string, unclosed brackets) and then split. There is no
prefix cache because the server only ever sees finished tool arguments.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum

from . import lexer as L
from .errors import ErrorCode, OpenUiError
from .lexer import Token, lex, lex_all
from .library import Library
from .nodes import (
    ArrayExpr,
    AssignExpr,
    BinaryExpr,
    BoolLit,
    CallExpr,
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

# ---- source preparation (language.md 1.2) -------------------------------------------------------------------------

_STMT_START = re.compile(r"^\s*[A-Za-z_$][A-Za-z0-9_]*\s*=(?!=)")
_MARKER = "]]>openui:"


def _starts_statement(line: str) -> bool:
    return _STMT_START.match(line) is not None


def _is_comment(line: str) -> bool:
    t = line.lstrip()
    return t.startswith("//") or t.startswith("#")


def _scan_string(line: str, in_string: bool) -> bool:
    """Toggles the "inside a double-quoted string" state across ``line``."""
    i = 0
    while i < len(line):
        c = line[i]
        if in_string and c == "\\":
            i += 1
        elif c == '"':
            in_string = not in_string
        i += 1
    return in_string


def _closes_on_same_line(trimmed: str) -> bool:
    """Three backticks that close again on the same line are inline code, not a fence."""
    return trimmed.find("```", 3) != -1


def prepare_source(text: str) -> str:
    unified = text.replace("\r\n", "\n")
    lines = [ln for ln in unified.split("\n") if not ln.lstrip().startswith(_MARKER)]

    blocks: list[list[str]] = []
    outside: list[str] = []
    block: list[str] | None = None
    skipping = False
    in_string = False
    saw_fence = False

    for line in lines:
        t = line.lstrip()
        is_fence_line = t.startswith("```") and not in_string and not _closes_on_same_line(t)
        if block is None:
            if is_fence_line:
                saw_fence = True
                rest = t[3:].strip()
                tag = re.split(r"\s+", rest)[0]
                skipping = tag == "openui-js"
                block = []
                code = rest[len(tag) :].strip() if len(rest) > len(tag) else ""
                if code and not skipping:
                    block.append(code)
                    in_string = _scan_string(code, False)
                blocks.append(block)
                if skipping:
                    blocks.pop()
            else:
                outside.append(line)
                # Outside blocks a string opens only on a statement line.
                if in_string or _starts_statement(line):
                    in_string = _scan_string(line, in_string)
        else:
            if is_fence_line:
                block = None
                skipping = False
                in_string = False
            elif not skipping:
                block.append(line)
                in_string = _scan_string(line, in_string)

    if not saw_fence:
        return "\n".join(lines).strip()

    block_text = [b for b in ("\n".join(b) for b in blocks) if b]
    first_code = None
    if block_text:
        first_code = next((ln for ln in block_text[0].split("\n") if ln.strip() and not _is_comment(ln)), "")
    if first_code is not None and _starts_statement(first_code):
        return "\n".join(block_text).strip()
    out = "\n".join(outside)
    if any(_starts_statement(ln) for ln in out.split("\n")):
        return out.strip()
    return "\n".join(block_text).strip()


def close_implicitly(text: str) -> tuple[str, bool]:
    """Closes an unterminated string (adding a ``\\`` first when the text ends mid-escape), then unclosed brackets in
    reverse order. A closer that does not match is skipped and leaves the stack alone. Returns the text and whether
    anything had to be closed."""
    stack: list[str] = []
    quote: str | None = None
    in_comment = False
    mid_escape = False
    n = len(text)
    i = 0
    while i < n:
        c = text[i]
        if in_comment:
            if c == "\n":
                in_comment = False
        elif quote is not None:
            if c == "\\":
                if i + 1 >= n:
                    mid_escape = True
                else:
                    i += 1
            elif c == quote:
                quote = None
        elif c in ('"', "'"):
            quote = c
        elif c == "#":
            in_comment = True
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            in_comment = True
        elif c == "(":
            stack.append(")")
        elif c == "[":
            stack.append("]")
        elif c == "{":
            stack.append("}")
        elif c in (")", "]", "}"):
            if stack and stack[-1] == c:
                stack.pop()
        i += 1
    if quote is None and not stack:
        return text, False
    out = [text]
    if quote is not None:
        if mid_escape:
            out.append("\\")
        out.append(quote)
    if in_comment and stack:
        out.append("\n")
    out.extend(reversed(stack))
    return "".join(out), True


# ---- the expression parser (language.md 1.5, 1.6) -----------------------------------------------------------------

_CMP = {L.GT: ">", L.LT: "<", L.GTE: ">=", L.LTE: "<="}
_MUL = {L.STAR: "*", L.SLASH: "/", L.PERCENT: "%"}


def format_number(v: float) -> str:
    """ECMAScript Number::toString for the cases member keys need."""
    if v != v:
        return "NaN"
    if v in (float("inf"), float("-inf")):
        return "Infinity" if v > 0 else "-Infinity"
    if v == 0:
        return "0"
    if v == int(v) and abs(v) < 1e21:
        return str(int(v))
    return repr(v)


class ExprParser:
    """Parses one statement's tokens. Newline tokens are ignored: the statement splitter already decided the extent."""

    def __init__(self, tokens: list[Token]) -> None:
        self._t = [t for t in tokens if t.kind != L.NEWLINE]
        if not self._t or self._t[-1].kind != L.EOF:
            end = self._t[-1].end if self._t else 0
            self._t.append(Token(L.EOF, end, end))
        self._i = 0

    @property
    def _k(self) -> str:
        return self._t[self._i].kind

    @property
    def _cur(self) -> Token:
        return self._t[self._i]

    def _peek_kind(self, n: int) -> str:
        return self._t[min(self._i + n, len(self._t) - 1)].kind

    @property
    def at_end(self) -> bool:
        return self._k == L.EOF

    def _next(self) -> Token:
        t = self._t[self._i]
        if t.kind != L.EOF:
            self._i += 1
        return t

    def _accept(self, kind: str) -> bool:
        if self._k != kind:
            return False
        self._next()
        return True

    def parse_statement(self) -> tuple[str, Expr] | None:
        """Parses ``name = expression``. Returns None if the tokens do not have that shape."""
        if self._k not in (L.REFERENCE, L.COMPONENT, L.STATE_NAME) or self._peek_kind(1) != L.ASSIGN:
            return None
        name = self._next().value
        self._next()
        return name, self.parse_expression()

    def parse_expression(self) -> Expr:
        return self._ternary()

    def _ternary(self) -> Expr:
        cond = self._or()
        if self._k != L.QUESTION:
            return cond
        self._next()
        a = self._ternary()
        self._accept(L.COLON)
        b = self._ternary()
        return TernaryExpr(cond, a, b)

    def _or(self) -> Expr:
        left = self._and()
        while self._k == L.OR:
            self._next()
            left = BinaryExpr("||", left, self._and())
        return left

    def _and(self) -> Expr:
        left = self._equality()
        while self._k == L.AND:
            self._next()
            left = BinaryExpr("&&", left, self._equality())
        return left

    def _equality(self) -> Expr:
        left = self._comparison()
        while self._k in (L.EQ, L.NEQ):
            op = "==" if self._next().kind == L.EQ else "!="
            left = BinaryExpr(op, left, self._comparison())
        return left

    def _comparison(self) -> Expr:
        left = self._additive()
        while self._k in _CMP:
            op = _CMP[self._next().kind]
            left = BinaryExpr(op, left, self._additive())
        return left

    def _additive(self) -> Expr:
        left = self._multiplicative()
        while self._k in (L.PLUS, L.MINUS):
            op = "+" if self._next().kind == L.PLUS else "-"
            left = BinaryExpr(op, left, self._multiplicative())
        return left

    def _multiplicative(self) -> Expr:
        left = self._unary()
        while self._k in _MUL:
            op = _MUL[self._next().kind]
            left = BinaryExpr(op, left, self._unary())
        return left

    def _unary(self) -> Expr:
        if self._k == L.NOT:
            self._next()
            return UnaryExpr("!", self._unary())
        if self._k == L.MINUS:
            self._next()
            return UnaryExpr("-", self._unary())
        return self._postfix()

    def _postfix(self) -> Expr:
        e = self._primary()
        while True:
            if self._k == L.DOT:
                self._next()
                e = MemberExpr(e, self._key_text(allow_state_drop=False))
            elif self._k == L.LBRACKET:
                self._next()
                idx = self.parse_expression()
                self._accept(L.RBRACKET)
                e = IndexExpr(e, idx)
            else:
                return e

    def _key_text(self, allow_state_drop: bool = True) -> str:
        """A key or field: a name, string, number, component name or ``$`` name. Anything else reads as ``?``."""
        t = self._cur
        if t.kind in (L.REFERENCE, L.COMPONENT, L.STRING):
            self._next()
            return t.value
        if t.kind == L.NUMBER:
            self._next()
            return format_number(t.value)
        if t.kind == L.STATE_NAME:
            self._next()
            return t.value[1:] if allow_state_drop else t.value
        if t.kind in (L.EOF, L.RPAREN, L.RBRACKET, L.RBRACE):
            return "?"
        self._next()
        return "?"

    def _primary(self) -> Expr:
        t = self._cur
        k = t.kind
        if k == L.STRING:
            self._next()
            return StrLit(t.value)
        if k == L.NUMBER:
            self._next()
            return NumLit(t.value)
        if k == L.TRUE:
            self._next()
            return BoolLit(True)
        if k == L.FALSE:
            self._next()
            return BoolLit(False)
        if k == L.NULL:
            self._next()
            return NullLit()
        if k == L.LBRACKET:
            self._next()
            return ArrayExpr(tuple(self._arguments(L.RBRACKET)))
        if k == L.LBRACE:
            self._next()
            return self._object()
        if k == L.LPAREN:
            self._next()
            e = self.parse_expression()
            self._accept(L.RPAREN)
            return e
        if k == L.COMPONENT:
            self._next()
            if self._k == L.LPAREN:
                self._next()
                return CallExpr(t.value, tuple(self._arguments(L.RPAREN)))
            return RefExpr(t.value)
        if k == L.BUILTIN:
            self._next()
            name = t.value
            if self._k == L.LPAREN:
                self._next()
                args = tuple(self._arguments(L.RPAREN))
                return CallExpr("Action", args) if name == "Action" else FnExpr(name, args)
            return FnExpr(name, ())
        if k == L.STATE_NAME:
            self._next()
            if self._k == L.ASSIGN:
                self._next()
                return AssignExpr(t.value, self.parse_expression())
            return RefExpr(t.value)
        if k == L.REFERENCE:
            self._next()
            if self._k == L.LPAREN:
                # ``Count(x)`` without ``@`` is the reference ``Count``; the arguments are lost (language.md 1.5).
                self._skip_balanced()
            return RefExpr(t.value)
        # A stray operator or closer where an operand belongs. Consume operators, leave closers for the caller.
        if k not in (L.EOF, L.RPAREN, L.RBRACKET, L.RBRACE):
            self._next()
        return NullLit()

    def _skip_balanced(self) -> None:
        depth = 0
        while not self.at_end:
            k = self._next().kind
            if k == L.LPAREN:
                depth += 1
            if k == L.RPAREN:
                depth -= 1
                if depth <= 0:
                    return

    @staticmethod
    def _is_closer(k: str) -> bool:
        return k in (L.RPAREN, L.RBRACKET, L.RBRACE)

    def _arguments(self, close: str) -> list[Expr]:
        out: list[Expr] = []
        while True:
            while self._accept(L.COMMA):
                pass
            if self.at_end:
                break
            if self._k == close:
                self._next()
                break
            if self._is_closer(self._k):
                self._next()  # a closer that does not match is skipped
                continue
            before = self._i
            out.append(self.parse_expression())
            if self._i == before:
                self._next()
        return out

    def _object(self) -> Expr:
        entries: list[tuple[str, Expr]] = []
        while True:
            while self._accept(L.COMMA):
                pass
            if self.at_end:
                break
            if self._k == L.RBRACE:
                self._next()
                break
            if self._k in (L.RPAREN, L.RBRACKET):
                self._next()
                continue
            key = self._key_text()
            self._accept(L.COLON)
            entries.append((key, self.parse_expression()))
        return ObjectExpr(tuple(entries))


# ---- statements (language.md 1.4) ---------------------------------------------------------------------------------


class StatementKind(Enum):
    VALUE = "value"
    STATE = "state"
    QUERY = "query"
    MUTATION = "mutation"


@dataclass(frozen=True)
class Statement:
    name: str
    kind: StatementKind
    expr: Expr
    #: Source span of the statement text.
    start: int
    end: int


def _classify(name: str, e: Expr) -> StatementKind:
    if isinstance(e, CallExpr) and e.name == "Query":
        return StatementKind.QUERY
    if isinstance(e, CallExpr) and e.name == "Mutation":
        return StatementKind.MUTATION
    if name.startswith("$"):
        return StatementKind.STATE
    return StatementKind.VALUE


def statement_ranges(tokens: list[Token]) -> list[tuple[int, int]]:
    """Groups token indexes into statements. Returns the half-open token ranges; every range but the last ends at the
    newline token that ended it, the last at ``eof``."""
    out: list[tuple[int, int]] = []
    begin = 0
    depth = 0
    open_ternary = 0  # unmatched ``?``
    need_operand = False  # after a ternary ``:`` until the first operand token
    for i, tok in enumerate(tokens):
        k = tok.kind
        if k == L.EOF:
            break
        if k in (L.LPAREN, L.LBRACKET, L.LBRACE):
            depth += 1
            need_operand = False
        elif k in (L.RPAREN, L.RBRACKET, L.RBRACE):
            if depth > 0:
                depth -= 1
            need_operand = False
        elif k == L.QUESTION and depth == 0:
            open_ternary += 1
        elif k == L.COLON and depth == 0 and open_ternary > 0:
            open_ternary -= 1
            need_operand = True
        elif k == L.NEWLINE:
            if depth > 0 or open_ternary > 0 or need_operand:
                continue
            j = i + 1
            while j < len(tokens) and tokens[j].kind == L.NEWLINE:
                j += 1
            if j < len(tokens) and tokens[j].kind == L.QUESTION:
                continue
            out.append((begin, i))
            begin = i + 1
        else:
            need_operand = False
    out.append((begin, len(tokens) - 1))
    return out


def statement_from_tokens(slice_: list[Token]) -> Statement | None:
    """Parses one statement's tokens, or None when they do not form ``name = expression``."""
    if all(t.kind == L.NEWLINE for t in slice_):
        return None
    parsed = ExprParser(slice_).parse_statement()
    if parsed is None:
        return None
    name, value = parsed
    return Statement(name, _classify(name, value), value, slice_[0].start, slice_[-1].end)


def split_statements(prepared: str) -> list[Statement]:
    tokens = lex_all(prepared).tokens
    out: list[Statement] = []
    for a, b in statement_ranges(tokens):
        s = statement_from_tokens(tokens[a:b])
        if s is not None:
            out.append(s)
    return out


# ---- the program model (language.md 2) ----------------------------------------------------------------------------


def referenced_names(e: Expr, shadow: frozenset[str] = frozenset()) -> set[str]:
    """Statement names an expression refers to (not ``$`` names, not an ``@Each`` loop variable inside its template)."""
    out: set[str] = set()

    def walk(x: Expr, sh: frozenset[str]) -> None:
        if isinstance(x, RefExpr):
            if not x.is_state and x.name not in sh:
                out.add(x.name)
        elif isinstance(x, ArrayExpr):
            for i in x.items:
                walk(i, sh)
        elif isinstance(x, ObjectExpr):
            for _, v in x.entries:
                walk(v, sh)
        elif isinstance(x, CallExpr):
            for a in x.args:
                walk(a, sh)
        elif isinstance(x, FnExpr):
            if x.name == "Each" and len(x.args) >= 3 and isinstance(x.args[1], StrLit):
                walk(x.args[0], sh)
                walk(x.args[2], sh | {x.args[1].value})
            else:
                for a in x.args:
                    walk(a, sh)
        elif isinstance(x, MemberExpr):
            walk(x.object, sh)
        elif isinstance(x, IndexExpr):
            walk(x.object, sh)
            walk(x.index, sh)
        elif isinstance(x, UnaryExpr):
            walk(x.operand, sh)
        elif isinstance(x, BinaryExpr):
            walk(x.left, sh)
            walk(x.right, sh)
        elif isinstance(x, TernaryExpr):
            walk(x.cond, sh)
            walk(x.then, sh)
            walk(x.otherwise, sh)
        elif isinstance(x, AssignExpr):
            walk(x.value, sh)

    walk(e, shadow)
    return out


@dataclass
class Program:
    #: One statement per name; a later definition replaces an earlier one. Insertion order of first appearance.
    statements: dict[str, Statement]
    #: Name of the entry statement, or None when there is none.
    entry: str | None
    #: True when there is no ``root`` statement and the first call of the library's root component was used.
    entry_is_fallback: bool
    #: Value statements the entry (and the always-live state, query and mutation statements) cannot reach.
    orphans: set[str] = field(default_factory=set)
    incomplete: bool = False

    @staticmethod
    def build(ordered: list[Statement], library: Library | None, incomplete: bool = False) -> Program:
        by_name: dict[str, Statement] = {}
        for s in ordered:
            by_name.pop(s.name, None)  # keeps "last wins" and moves the name to its final position
            by_name[s.name] = s

        entry: str | None = None
        fallback = False
        root = by_name.get("root")
        if root is not None and root.kind != StatementKind.STATE:
            entry = "root"
        elif library is not None and library.root is not None:
            for s in by_name.values():
                if s.kind == StatementKind.VALUE and isinstance(s.expr, CallExpr) and s.expr.name == library.root:
                    entry = s.name
                    fallback = True
                    break

        orphans: set[str] = set()
        if entry is not None:
            live: set[str] = set()

            def visit(name: str) -> None:
                if name in live:
                    return
                live.add(name)
                s = by_name.get(name)
                if s is None:
                    return
                for r in referenced_names(s.expr):
                    visit(r)

            visit(entry)
            for s in by_name.values():
                if s.kind != StatementKind.VALUE:
                    visit(s.name)
            for s in by_name.values():
                if s.kind == StatementKind.VALUE and s.name not in live:
                    orphans.add(s.name)
        return Program(by_name, entry, fallback, orphans, incomplete)


# ---- parse_program ------------------------------------------------------------------------------------------------


@dataclass
class ParseOutcome:
    """What parsing alone gives: the program model, before validation."""

    program: Program | None
    errors: list[OpenUiError]
    incomplete: bool
    prepared: str


def parse(library: Library, text: str) -> ParseOutcome:
    """Prepares, closes and splits ``text`` and builds the program. Never raises."""
    try:
        prepared = prepare_source(text)
        closed, was_closed = close_implicitly(prepared)
        statements = split_statements(closed)
        if not statements:
            errors = (
                []
                if not prepared.strip()
                else [OpenUiError(ErrorCode.PARSE_FAILED, message="the response has text but yields no statements")]
            )
            return ParseOutcome(None, errors, was_closed, prepared)
        return ParseOutcome(Program.build(statements, library, was_closed), [], was_closed, prepared)
    except Exception as e:  # noqa: BLE001 - the parser's contract is never to raise
        return ParseOutcome(None, [OpenUiError(ErrorCode.PARSE_EXCEPTION, message=str(e))], False, "")


# Re-exported for the lexer-only callers.
__all__ = [
    "ExprParser",
    "ParseOutcome",
    "Program",
    "Statement",
    "StatementKind",
    "close_implicitly",
    "lex",
    "parse",
    "prepare_source",
    "referenced_names",
    "split_statements",
    "statement_ranges",
]
