"""A Python port of the OpenUI Lang 1.0 lexer, parser and validator (plan 2.4; spec decision D10).

Validation only: nothing here evaluates an expression. The Dart package ``packages/openui_lang`` is the reference
implementation for Iris; both run the same vendored conformance fixtures.
"""

from .errors import ErrorCode, OpenUiError
from .library import Library
from .validate import Limits, ParseResult, Validation, parse_program, validate_program

__all__ = [
    "ErrorCode",
    "Library",
    "Limits",
    "OpenUiError",
    "ParseResult",
    "Validation",
    "parse_program",
    "validate_program",
]
