"""Expression syntax tree (language.md 1.5) and the validated program tree (9.1). Immutable; no behaviour."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


class Expr:
    __slots__ = ()


@dataclass(frozen=True)
class StrLit(Expr):
    value: str


@dataclass(frozen=True)
class NumLit(Expr):
    value: float


@dataclass(frozen=True)
class BoolLit(Expr):
    value: bool


@dataclass(frozen=True)
class NullLit(Expr):
    pass


@dataclass(frozen=True)
class ArrayExpr(Expr):
    items: tuple[Expr, ...]


@dataclass(frozen=True)
class ObjectExpr(Expr):
    #: Keys keep source order; duplicates are kept, the later one wins when read.
    entries: tuple[tuple[str, Expr], ...]


@dataclass(frozen=True)
class RefExpr(Expr):
    """A bare identifier, whatever its case, or a ``$state`` name (the ``$`` is part of ``name``)."""

    name: str

    @property
    def is_state(self) -> bool:
        return self.name.startswith("$")


@dataclass(frozen=True)
class CallExpr(Expr):
    """``Name(args)`` where the head is a component, or ``Query``/``Mutation``/``Action``."""

    name: str
    args: tuple[Expr, ...]


@dataclass(frozen=True)
class FnExpr(Expr):
    """``@Name(args)``: a built-in, a custom function or an action."""

    name: str
    args: tuple[Expr, ...]


@dataclass(frozen=True)
class MemberExpr(Expr):
    object: Expr
    field: str


@dataclass(frozen=True)
class IndexExpr(Expr):
    object: Expr
    index: Expr


@dataclass(frozen=True)
class UnaryExpr(Expr):
    op: str
    operand: Expr


@dataclass(frozen=True)
class BinaryExpr(Expr):
    op: str
    left: Expr
    right: Expr


@dataclass(frozen=True)
class TernaryExpr(Expr):
    cond: Expr
    then: Expr
    otherwise: Expr


@dataclass(frozen=True)
class AssignExpr(Expr):
    target: str
    value: Expr


# ---- the validated tree -------------------------------------------------------------------------------------------


@dataclass
class Element:
    type: str
    #: The statement this call was written in.
    statement_id: str
    #: Named props in positional order. Absent and null props are not stored.
    props: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class Binding:
    """A prop bound two-way to ``$name``."""

    name: str


@dataclass(frozen=True)
class Deferred:
    """An expression the evaluator (client side) must run. The server never evaluates it."""

    expr: Expr
    statement_id: str
