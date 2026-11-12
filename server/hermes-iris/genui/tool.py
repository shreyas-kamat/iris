"""The ``iris_ui`` tool as Hermes registers it. Handlers return a string and must never raise."""

from __future__ import annotations

import json
import logging
from typing import Any

from . import catalog, surfaces
from .paths import current_profile, iris_root
from .store import Store

_log = logging.getLogger("hermes_iris")

SCHEMA: dict[str, Any] = {
    "name": "iris_ui",
    "description": (
        "Show a native display in the Iris app: a card, stats, a list or a form, written in OpenUI Lang. "
        "Pass `code` (a program, `root = ...` on the first line) or `template` plus `data`. Always pass `fallback`, "
        "the same content as Markdown. Reuse a `surface_id` to update that display; `delete: true` removes it. "
        "Returns {ok, surface_id, rev}, or {ok: false, errors} to fix and send again."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "surface_id": {"type": "string", "description": "Short id, letters, digits, _ and -. Reuse it to update."},
            "code": {"type": "string", "description": "An OpenUI Lang program, root first."},
            "template": {"type": "string", "description": "The id of an approved template."},
            "data": {"type": "object", "description": "The template's data."},
            "fallback": {"type": "string", "description": "The same content as Markdown. Required unless deleting."},
            "placement": {"type": "string", "enum": ["inline", "reply_kit"], "description": "Default inline."},
            "delete": {"type": "boolean", "description": "Remove this surface."},
        },
        "required": ["surface_id"],
    },
}


def _answer(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False)


def handle_iris_ui(args: Any, **kw: Any) -> str:
    try:
        session_id = kw.get("session_id")
        if not session_id:
            return _answer({"ok": False, "errors": ["there is no session for this call"]})
        profile = Store(iris_root()).profile(current_profile())
        return _answer(surfaces.submit(profile, catalog.v1(), session_id, args))
    except Exception:  # noqa: BLE001 - a tool handler must not raise into the agent loop
        _log.exception("iris_ui failed")
        return _answer({"ok": False, "errors": ["the display could not be saved; try again"]})
