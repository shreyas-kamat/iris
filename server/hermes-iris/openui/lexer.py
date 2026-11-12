"""Lexer for OpenUI Lang 1.0 (language.md 1.3). It never throws: a character that matches no rule is skipped."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any, NamedTuple

# Token kinds. Plain strings keep the parser readable and the tokens printable.
COMPONENT = "component"
REFERENCE = "reference"
STATE_NAME = "stateName"
BUILTIN = "builtin"
STRING = "string"
NUMBER = "number"
TRUE = "true"
FALSE = "false"
NULL = "null"
ASSIGN = "assign"
EQ = "eq"
NEQ = "neq"
GT = "gt"
LT = "lt"
GTE = "gte"
LTE = "lte"
PLUS = "plus"
MINUS = "minus"
STAR = "star"
SLASH = "slash"
PERCENT = "percent"
AND = "and"
OR = "or"
NOT = "not"
QUESTION = "question"
COLON = "colon"
DOT = "dot"
COMMA = "comma"
LPAREN = "lParen"
RPAREN = "rParen"
LBRACKET = "lBracket"
RBRACKET = "rBracket"
LBRACE = "lBrace"
RBRACE = "rBrace"
NEWLINE = "newline"
EOF = "eof"


@dataclass(frozen=True)
class Token:
    kind: str
    #: Offset of the first character in the source.
    start: int
    #: Offset just past the last character.
    end: int
    #: Name (without ``@``; ``$`` kept for state names), decoded string, or ``float`` for numbers.
    value: Any = None


class LexResult(NamedTuple):
    tokens: list[Token]
    unterminated_string: bool


def _is_digit(c: int) -> bool:
    return 0x30 <= c <= 0x39


def _is_alpha(c: int) -> bool:
    return 0x61 <= c <= 0x7A or 0x41 <= c <= 0x5A or c == 0x5F


def _is_alnum(c: int) -> bool:
    return _is_alpha(c) or _is_digit(c)


#: Tokens after which a ``-`` is subtraction, not the sign of a number (language.md 1.3).
_VALUE_ENDS = {NUMBER, STRING, REFERENCE, COMPONENT, RPAREN, RBRACKET, TRUE, FALSE, NULL, STATE_NAME, BUILTIN}

_SINGLE = {
    0x2E: DOT,
    0x3F: QUESTION,
    0x3A: COLON,
    0x2C: COMMA,
    0x2B: PLUS,
    0x2A: STAR,
    0x25: PERCENT,
    0x28: LPAREN,
    0x29: RPAREN,
    0x5B: LBRACKET,
    0x5D: RBRACKET,
    0x7B: LBRACE,
    0x7D: RBRACE,
}

#: char -> (token when alone, token when doubled or followed by =, the second char)
_PAIRS = {
    0x3D: (ASSIGN, EQ, 0x3D),  # = ==
    0x21: (NOT, NEQ, 0x3D),  # ! !=
    0x3E: (GT, GTE, 0x3D),  # > >=
    0x3C: (LT, LTE, 0x3D),  # < <=
    0x26: (AND, AND, 0x26),  # & &&
    0x7C: (OR, OR, 0x7C),  # | ||
}


def lex(src: str) -> list[Token]:
    return lex_all(src).tokens


def lex_all(src: str) -> LexResult:
    unterminated = False
    tokens: list[Token] = []
    n = len(src)
    i = 0

    def at(k: int) -> int:
        return ord(src[k]) if k < n else -1

    while i < n:
        c = ord(src[i])
        if c in (0x20, 0x09, 0x0D):  # space, tab, \r
            i += 1
        elif c == 0x0A:
            tokens.append(Token(NEWLINE, i, i + 1))
            i += 1
        elif c == 0x23:  # #
            i = _skip_line(src, i)
        elif c == 0x2F:  # /
            if at(i + 1) == 0x2F:
                i = _skip_line(src, i)
            else:
                tokens.append(Token(SLASH, i, i + 1))
                i += 1
        elif c in _PAIRS:
            single, double, second = _PAIRS[c]
            if at(i + 1) == second:
                tokens.append(Token(double, i, i + 2))
                i += 2
            else:
                tokens.append(Token(single, i, i + 1))
                i += 1
        elif c in _SINGLE:
            tokens.append(Token(_SINGLE[c], i, i + 1))
            i += 1
        elif c == 0x22:
            end, value, closed = _double_quoted(src, i)
            unterminated = not closed
            tokens.append(Token(STRING, i, end, value))
            i = end
        elif c == 0x27:
            end, value, closed = _single_quoted(src, i)
            unterminated = not closed
            tokens.append(Token(STRING, i, end, value))
            i = end
        elif c in (0x24, 0x40):  # $name or @name
            if _is_alpha(at(i + 1)):
                j = i + 1
                while j < n and _is_alnum(ord(src[j])):
                    j += 1
                if c == 0x24:
                    tokens.append(Token(STATE_NAME, i, j, src[i:j]))
                else:
                    tokens.append(Token(BUILTIN, i, j, src[i + 1 : j]))
                i = j
            else:
                i += 1
        elif _is_digit(c) or (c == 0x2D and _is_digit(at(i + 1)) and not _after_value(tokens)):
            end, value = _number(src, i)
            tokens.append(Token(NUMBER, i, end, value))
            i = end
        elif c == 0x2D:
            tokens.append(Token(MINUS, i, i + 1))
            i += 1
        elif _is_alpha(c):
            j = i
            while j < n and _is_alnum(ord(src[j])):
                j += 1
            word = src[i:j]
            if word == "true":
                tokens.append(Token(TRUE, i, j))
            elif word == "false":
                tokens.append(Token(FALSE, i, j))
            elif word == "null":
                tokens.append(Token(NULL, i, j))
            else:
                upper = 0x41 <= c <= 0x5A
                tokens.append(Token(COMPONENT if upper else REFERENCE, i, j, word))
            i = j
        else:
            i += 1  # unknown character, including a lone surrogate half
    tokens.append(Token(EOF, n, n))
    return LexResult(tokens, unterminated)


def _skip_line(src: str, i: int) -> int:
    j = src.find("\n", i)
    return len(src) if j == -1 else j


def _after_value(tokens: list[Token]) -> bool:
    return bool(tokens) and tokens[-1].kind in _VALUE_ENDS


def _number(src: str, start: int) -> tuple[int, float]:
    n = len(src)
    i = start

    def digit(k: int) -> bool:
        return k < n and _is_digit(ord(src[k]))

    if src[i] == "-":
        i += 1
    while digit(i):
        i += 1
    if i < n and src[i] == "." and digit(i + 1):
        i += 1
        while digit(i):
            i += 1
    dangling = False
    if i < n and src[i] in "eE":
        i += 1
        if i < n and src[i] in "+-":
            i += 1
        exp_start = i
        while digit(i):
            i += 1
        dangling = i == exp_start
    return i, (math.nan if dangling else float(src[start:i]))


_HEX4 = re.compile(r"[0-9a-fA-F]{4}")


def _join_surrogates(s: str) -> str:
    """Dart strings are UTF-16: ``\\ud83d\\ude00`` is one character there, so combine escaped pairs here too."""
    if not any("\ud800" <= ch <= "\udfff" for ch in s):
        return s
    return s.encode("utf-16-le", "surrogatepass").decode("utf-16-le", "surrogatepass")


_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f"}


def _double_quoted(src: str, start: int) -> tuple[int, str, bool]:
    n = len(src)
    out: list[str] = []
    i = start + 1
    while i < n:
        c = src[i]
        if c == '"':
            return i + 1, _join_surrogates("".join(out)), True
        if c != "\\":
            out.append(c)
            i += 1
            continue
        if i + 1 >= n:
            i += 1  # dangling backslash at the end of a streaming buffer
            break
        e = src[i + 1]
        i += 2
        if e in _ESCAPES:
            out.append(_ESCAPES[e])
        elif e == "u":
            stop = min(n, i + 4)
            hex_ = src[i:stop]
            if _HEX4.fullmatch(hex_):
                out.append(chr(int(hex_, 16)))
            else:
                # Partly received or malformed escape: keep what arrived as text, as the reference does.
                out.append("\\u" + hex_)
            i = stop
        else:  # \" \\ \/ and any other escaped character: the character itself
            out.append(e)
    return n, _join_surrogates("".join(out)), False


def _single_quoted(src: str, start: int) -> tuple[int, str, bool]:
    n = len(src)
    out: list[str] = []
    i = start + 1
    while i < n:
        c = src[i]
        if c == "'":
            return i + 1, "".join(out), True
        if c == "\\":
            i += 1
            if i < n:
                e = src[i]
                out.append({"n": "\n", "t": "\t"}.get(e, e))
                i += 1
        else:
            out.append(c)
            i += 1
    return n, "".join(out), False
