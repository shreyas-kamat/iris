"""Templates (D6): a stored OpenUI program that reads a top-level ``data`` object, plus a JSON Schema for that object.

``expand`` checks the data against the schema and prepends ``data = {...}`` to the program, so a reply costs a few
hundred bytes of JSON instead of a whole program, and the result is still plain OpenUI Lang that the app renders with
the same code path as anything else.

The schema checker handles the subset templates use (``type``, ``enum``, ``required``, ``properties``,
``additionalProperties: false``, ``items``, ``minItems``/``maxItems``, ``minLength``/``maxLength``,
``minimum``/``maximum``); an unknown keyword is ignored, never an error. Error text names the path so the model can fix
it.
"""

from __future__ import annotations

import json
import re
from typing import Any

MAX_ERRORS = 20
_DATA_STATEMENT = re.compile(r"^\s*data\s*=(?!=)", re.M)


class TemplateError(Exception):
    def __init__(self, errors: list[str]) -> None:
        super().__init__("; ".join(errors))
        self.errors = errors


def _is_num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


_TYPES = {
    "string": lambda v: isinstance(v, str),
    "number": _is_num,
    "integer": lambda v: _is_num(v) and float(v).is_integer(),
    "boolean": lambda v: isinstance(v, bool),
    "array": lambda v: isinstance(v, list),
    "object": lambda v: isinstance(v, dict),
    "null": lambda v: v is None,
}

_ARTICLE = {"object": "an object", "array": "an array", "integer": "an integer", "null": "null"}


def _join(path: str, key: str) -> str:
    return f"{path}.{key}" if path else key


def check_data(schema: dict[str, Any], data: Any) -> list[str]:
    """Problems with ``data`` against ``schema``, as short lines; empty when it conforms."""
    errors: list[str] = []
    _check(schema if isinstance(schema, dict) else {}, data, "", errors)
    return errors[:MAX_ERRORS]


def _check(schema: dict[str, Any], v: Any, path: str, errors: list[str]) -> None:
    if len(errors) >= MAX_ERRORS:
        return
    name = path or "data"
    t = schema.get("type")
    if t is not None:
        types = t if isinstance(t, list) else [t]
        if not any(_TYPES.get(x, lambda _v: True)(v) for x in types):
            want = " or ".join(_ARTICLE.get(x, f"a {x}") for x in types)
            errors.append(f"{name} must be {want}")
            return
    enum = schema.get("enum")
    if isinstance(enum, list) and not any(type(x) is type(v) and x == v for x in enum):
        errors.append(f"{name} must be one of {', '.join(json.dumps(x) for x in enum)}")
        return
    if isinstance(v, str):
        if isinstance(schema.get("maxLength"), int) and len(v) > schema["maxLength"]:
            errors.append(f"{name} is longer than {schema['maxLength']} characters")
        if isinstance(schema.get("minLength"), int) and len(v) < schema["minLength"]:
            errors.append(f"{name} is shorter than {schema['minLength']} characters")
    elif _is_num(v):
        if _is_num(schema.get("minimum")) and v < schema["minimum"]:
            errors.append(f"{name} must be at least {schema['minimum']}")
        if _is_num(schema.get("maximum")) and v > schema["maximum"]:
            errors.append(f"{name} must be at most {schema['maximum']}")
    elif isinstance(v, list):
        if isinstance(schema.get("maxItems"), int) and len(v) > schema["maxItems"]:
            errors.append(f"{name} has more than {schema['maxItems']} items")
        if isinstance(schema.get("minItems"), int) and len(v) < schema["minItems"]:
            errors.append(f"{name} has fewer than {schema['minItems']} items")
        items = schema.get("items")
        if isinstance(items, dict):
            for i, x in enumerate(v):
                _check(items, x, f"{path}[{i}]", errors)
    elif isinstance(v, dict):
        props = schema.get("properties") if isinstance(schema.get("properties"), dict) else {}
        for key in schema.get("required") or []:
            if key not in v:
                errors.append(f"{_join(path, key)} is required")
        for key, value in v.items():
            if key in props and isinstance(props[key], dict):
                _check(props[key], value, _join(path, key), errors)
            elif schema.get("additionalProperties") is False:
                errors.append(f"{_join(path, key)} is not allowed")


def expand(template: dict[str, Any], data: Any) -> str:
    """The program for ``template`` with ``data`` bound: ``data = {...}`` followed by the template body."""
    program = template.get("program")
    if not isinstance(program, str) or not program.strip():
        raise TemplateError(["the template has no program"])
    if _DATA_STATEMENT.search(program):
        raise TemplateError(["a template may not define data itself; it reads the data it is given"])
    errors = check_data(template.get("schema") or {}, data)
    if errors:
        raise TemplateError(errors)
    try:
        literal = json.dumps(data, ensure_ascii=False, allow_nan=False)
    except (TypeError, ValueError):
        raise TemplateError(["data must be plain JSON (no NaN or Infinity)"]) from None
    return f"data = {literal}\n{program}"
