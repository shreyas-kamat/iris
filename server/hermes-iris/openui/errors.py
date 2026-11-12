"""Structured errors (language.md 8.2, 8.3). ``message`` and ``hint`` are text for the model and never compared."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class ErrorCode:
    UNKNOWN_COMPONENT = "unknown-component"
    MISSING_REQUIRED = "missing-required"
    NULL_REQUIRED = "null-required"
    TYPE_MISMATCH = "type-mismatch"
    EXCESS_ARGS = "excess-args"
    INLINE_RESERVED = "inline-reserved"
    UNKNOWN_FUNCTION = "unknown-function"
    NO_ROOT = "no-root"
    PARSE_FAILED = "parse-failed"
    PARSE_EXCEPTION = "parse-exception"


@dataclass(frozen=True)
class OpenUiError:
    code: str
    source: str = "parser"
    statement_id: str | None = None
    component: str | None = None
    path: str | None = None
    message: str = ""
    hint: str | None = None
    #: Only the non-fatal ``no-root`` is a warning: the page renders through it.
    warning: bool = False

    @property
    def is_fatal(self) -> bool:
        return not self.warning and self.code in (ErrorCode.NO_ROOT, ErrorCode.PARSE_FAILED, ErrorCode.PARSE_EXCEPTION)

    def to_json(self) -> dict[str, Any]:
        out: dict[str, Any] = {"source": self.source, "code": self.code}
        if self.statement_id is not None:
            out["statementId"] = self.statement_id
        if self.component is not None:
            out["component"] = self.component
        if self.path is not None:
            out["path"] = self.path
        out["message"] = self.message
        if self.hint is not None:
            out["hint"] = self.hint
        if self.warning:
            out["severity"] = "warning"
        return out
