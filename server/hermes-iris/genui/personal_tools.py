"""The study tools: the agent proposes a work profile and personal templates; the person approves them in Iris.

Handlers return a string and must never raise. They are registered in toolset ``iris``, so the ``pre_tool_call`` guard
keeps them to flagged sessions like ``iris_ui``.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from . import catalog, personal
from .paths import current_profile, iris_root
from .store import Store

_log = logging.getLogger("hermes_iris")

PROFILE_GET: dict[str, Any] = {
    "name": "iris_profile_get",
    "description": "Read the work profile the person has approved or that is waiting for their review in Iris.",
    "parameters": {"type": "object", "properties": {}},
}

PROFILE_PROPOSE: dict[str, Any] = {
    "name": "iris_profile_propose",
    "description": (
        "Propose a short work profile for the person to review in Iris: one or two sentences about what they do, and "
        "up to 12 short chips (topics, tools, roles). Nothing is used until they approve it. "
        "Returns {ok, rev, status} or {ok: false, errors} to fix and send again."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "summary": {"type": "string", "description": "One or two sentences, at most 600 characters."},
            "chips": {"type": "array", "items": {"type": "string"}, "description": "Up to 12, each at most 40 characters."},
        },
        "required": ["summary"],
    },
}

TEMPLATE_LIST: dict[str, Any] = {
    "name": "iris_template_list",
    "description": "List the person's templates (id, name, when to use, status, data keys). Programs are not included.",
    "parameters": {
        "type": "object",
        "properties": {"status": {"type": "string", "enum": list(personal.STATUSES), "description": "Only this status."}},
    },
}

TEMPLATE_PROPOSE: dict[str, Any] = {
    "name": "iris_template_propose",
    "description": (
        "Propose a personal display template for the person to review in Iris. A template is an OpenUI Lang program "
        "that reads a top-level `data` object (never define `data` yourself), a JSON Schema for that object, and "
        "made-up sample_data that fits it (no real names, secrets or ids). It is checked before it is stored; "
        "nothing is used until the person approves it. Returns {ok, id, rev, status} or {ok: false, errors}."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "Short id, letters, digits, _ and -."},
            "name": {"type": "string", "description": "What the person will see, at most 60 characters."},
            "when": {"type": "string", "description": "One line: when to use it, at most 200 characters."},
            "data_schema": {"type": "object", "description": 'JSON Schema of `data`; "type": "object".'},
            "program": {"type": "string", "description": "OpenUI Lang, root first, reading `data`."},
            "sample_data": {"type": "object", "description": "Made-up data that fits data_schema."},
        },
        "required": ["id", "name", "when", "data_schema", "program", "sample_data"],
    },
}

SCHEMAS: list[dict[str, Any]] = [PROFILE_GET, PROFILE_PROPOSE, TEMPLATE_LIST, TEMPLATE_PROPOSE]


def _profile_store():
    return Store(iris_root()).profile(current_profile())


def _answer(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False)


def _safely(what: str, run) -> str:
    try:
        return _answer(run())
    except Exception:  # noqa: BLE001 - a tool handler must not raise into the agent loop
        _log.exception("%s failed", what)
        return _answer({"ok": False, "errors": ["that could not be done; try again"]})


def handle_profile_get(args: Any = None, **kw: Any) -> str:
    return _safely("iris_profile_get", lambda: personal.get_profile(_profile_store()))


def handle_profile_propose(args: Any, **kw: Any) -> str:
    return _safely("iris_profile_propose", lambda: personal.propose_profile(_profile_store(), args))


def handle_template_list(args: Any = None, **kw: Any) -> str:
    def run() -> dict[str, Any]:
        status = args.get("status") if isinstance(args, dict) else None
        if status is not None and status not in personal.STATUSES:
            return {"ok": False, "errors": [f"status must be one of {', '.join(personal.STATUSES)}"]}
        return {"ok": True, "templates": personal.list_template_summaries(_profile_store(), status)}

    return _safely("iris_template_list", run)


def handle_template_propose(args: Any, **kw: Any) -> str:
    return _safely("iris_template_propose", lambda: personal.propose_template(_profile_store(), catalog.v1(), args))


#: (schema, handler) pairs for ``register``.
TOOLS = [
    (PROFILE_GET, handle_profile_get),
    (PROFILE_PROPOSE, handle_profile_propose),
    (TEMPLATE_LIST, handle_template_list),
    (TEMPLATE_PROPOSE, handle_template_propose),
]
