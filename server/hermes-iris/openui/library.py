"""A component library as OpenUI describes it (prompt.md 2). The key order of ``properties`` is the positional order.

Built from the same JSON the Dart side exports (``catalog/*.library.json``); dicts keep insertion order.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

Json = dict[str, Any]

_BINDABLE = re.compile(r"(\w+)\??:\s*\$binding<")


def _as_map(o: Any) -> Json:
    return o if isinstance(o, dict) else {}


@dataclass(frozen=True)
class PropSpec:
    name: str
    #: The JSON Schema fragment for this prop, untouched.
    schema: Json
    required: bool
    #: True when the signature prints ``$binding<type>`` for this prop (the schema has no marker).
    bindable: bool = False

    @property
    def has_default(self) -> bool:
        return "default" in self.schema

    @property
    def default_value(self) -> Any:
        return self.schema.get("default")


def _props(obj: Json, bindable: set[str] | None = None) -> list[PropSpec]:
    required = set(obj.get("required") or [])
    return [
        PropSpec(name, _as_map(schema), name in required, name in (bindable or set()))
        for name, schema in _as_map(obj.get("properties")).items()
    ]


@dataclass(frozen=True)
class ComponentSpec:
    name: str
    description: str
    props: list[PropSpec]


@dataclass(frozen=True)
class FunctionSpec:
    name: str
    description: str
    params: list[PropSpec]
    returns: Json | None = None


@dataclass
class Library:
    json: Json
    id: str | None
    version: str | None
    root: str | None
    components: dict[str, ComponentSpec]
    functions: dict[str, FunctionSpec]
    actions: dict[str, FunctionSpec]
    defs: Json = field(default_factory=dict)

    @staticmethod
    def from_json(data: Json) -> Library:
        schema = _as_map(data.get("schema"))
        defs = _as_map(schema.get("$defs"))
        listed = _as_map(data.get("components"))

        components: dict[str, ComponentSpec] = {}
        for name in _as_map(schema.get("properties")):
            definition = _as_map(defs.get(name))
            signature = _as_map(listed.get(name)).get("signature") or ""
            components[name] = ComponentSpec(
                name,
                definition.get("description") or _as_map(listed.get(name)).get("description") or "",
                _props(definition, set(_BINDABLE.findall(signature))),
            )

        def fn(name: str, raw: Any) -> FunctionSpec:
            m = _as_map(raw)
            return FunctionSpec(
                name,
                m.get("description") or "",
                _props(_as_map(m.get("params"))),
                _as_map(m.get("returns")) if isinstance(m.get("returns"), dict) else None,
            )

        return Library(
            json=data,
            id=data.get("id"),
            version=data.get("version"),
            root=data.get("root"),
            components=components,
            functions={k: fn(k, v) for k, v in _as_map(schema.get("functions")).items()},
            actions={k: fn(k, v) for k, v in _as_map(schema.get("actions")).items()},
            defs=defs,
        )

    @staticmethod
    def load(path: str | Path) -> Library:
        return Library.from_json(json.loads(Path(path).read_text("utf-8")))
