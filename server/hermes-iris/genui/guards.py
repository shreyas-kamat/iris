"""Hooks that keep ``iris_*`` tools to Iris sessions and keep their results small.

* ``pre_tool_call`` vetoes any ``iris_*`` tool in a session Iris did not flag (D3), and the fifth distinct surface of
  one turn. The model gets a sentence it can act on.
* ``transform_tool_result`` trims ``iris_ui``'s receipt before it enters the model's context.

Hermes contracts (release 2026.9.24): ``pre_tool_call`` returns ``{"action": "block", "message": ...}`` or None;
``transform_tool_result`` returns a replacement string or None (first string wins). Both are fail-open in Hermes, and
nothing here may raise.
"""

from __future__ import annotations

import json
import threading
from collections import OrderedDict
from typing import Any

from . import flags

MAX_SURFACES_PER_TURN = 4
TURNS_REMEMBERED = 64
RECEIPT_ERRORS_MAX_CHARS = 1200

#: The learning tools a scheduled ``/iris-refine`` run needs. A cron run is not a session Iris flagged, so these are
#: allowed anywhere. They only read counts or *propose*; nothing they write is used until the person approves it.
#: ``iris_ui`` and ``iris_profile_propose`` stay in flagged sessions.
ANY_SESSION = frozenset(
    {
        "iris_usage_summary",
        "iris_template_refine",
        "iris_template_list",
        "iris_template_propose",
        "iris_profile_get",
    }
)

_LOCK = threading.Lock()
#: turn id -> the distinct surface ids it has used, oldest turn first.
_TURNS: OrderedDict[str, set[str]] = OrderedDict()

_NOT_IRIS = (
    "iris_ui is only available when the person is chatting in the Iris app, and this is not an Iris session. "
    "Answer in plain Markdown instead."
)


def reset() -> None:
    with _LOCK:
        _TURNS.clear()


def remembered_turns() -> int:
    with _LOCK:
        return len(_TURNS)


def _block(message: str) -> dict[str, str]:
    return {"action": "block", "message": message}


def on_pre_tool_call(**kw: Any) -> dict[str, str] | None:
    try:
        name = kw.get("tool_name")
        if not isinstance(name, str) or not name.startswith("iris_"):
            return None
        if name in ANY_SESSION:
            return None
        if not flags.is_flagged(kw.get("session_id")):  # type: ignore[arg-type]
            return _block(_NOT_IRIS)
        if name == "iris_ui":
            return _limit_surfaces(kw)
        return None
    except Exception:  # noqa: BLE001 - a hook must never break a turn
        return None


def _limit_surfaces(kw: dict[str, Any]) -> dict[str, str] | None:
    args = kw.get("args")
    if not isinstance(args, dict) or args.get("delete") is True:
        return None
    surface = args.get("surface_id")
    turn = kw.get("turn_id")
    if not isinstance(surface, str) or not isinstance(turn, str) or not turn:
        return None
    with _LOCK:
        used = _TURNS.get(turn)
        if used is None:
            used = _TURNS[turn] = set()
            while len(_TURNS) > TURNS_REMEMBERED:
                _TURNS.popitem(last=False)
        if surface not in used and len(used) >= MAX_SURFACES_PER_TURN:
            return _block(
                f"At most {MAX_SURFACES_PER_TURN} displays per reply. Update one you already showed this turn "
                "(same surface_id) or put the rest in the text."
            )
        used.add(surface)
    return None


def on_transform_tool_result(**kw: Any) -> str | None:
    try:
        if kw.get("tool_name") != "iris_ui":
            return None
        result = kw.get("result")
        if not isinstance(result, str):
            return None
        data = json.loads(result)
        if not isinstance(data, dict):
            return None
        if data.get("ok") is True:
            keep = {k: data[k] for k in ("ok", "surface_id", "rev", "deleted") if k in data}
            return json.dumps(keep, ensure_ascii=False)
        if data.get("ok") is False:
            return json.dumps({"ok": False, "errors": _cap_errors(data.get("errors"))}, ensure_ascii=False)
        return None
    except Exception:  # noqa: BLE001
        return None


def _cap_errors(errors: Any) -> list[str]:
    out: list[str] = []
    used = 0
    for e in errors if isinstance(errors, list) else []:
        line = str(e)
        if used + len(line) > RECEIPT_ERRORS_MAX_CHARS:
            room = RECEIPT_ERRORS_MAX_CHARS - used
            if room > 40:
                out.append(line[: room - 1] + "…")
            out.append("(more problems not shown; fix these first)")
            break
        out.append(line)
        used += len(line)
    return out
