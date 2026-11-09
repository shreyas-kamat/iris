"""The usage log: one ``use`` row per finished turn of a flagged session, for ``/iris-refine``.

``iris_ui`` notes each display it accepts (``note_display``); Hermes's ``post_llm_call`` hook then writes one row,
``{kind: "use", ts, session, templates_used, surfaces}``, and forgets the notes. Only ids are kept: no program, data,
fallback, user message or reply ever reaches the file. Rows sit in the same ``usage.jsonl`` as the app's signals
(``kind: "signal"``), so readers tell them apart by ``kind``.

The tool handler and the hook run in the agent process, so a little memory carries the turn between them. It is bounded.
"""

from __future__ import annotations

import logging
import threading
import time
from collections import OrderedDict
from typing import Any

from . import flags
from .paths import current_profile, iris_root
from .store import InvalidName, Store, safe_component

_log = logging.getLogger("hermes_iris")

#: Sessions with notes waiting for their turn to end; the oldest are forgotten past this.
MAX_SESSIONS = 64
#: Distinct displays remembered per turn (the per-turn guard allows far fewer).
MAX_SURFACES = 50

_LOCK = threading.Lock()
#: session id -> {"surfaces": [ids], "templates": [ids]}, in order of first use.
_PENDING: OrderedDict[str, dict[str, list[str]]] = OrderedDict()


def reset() -> None:
    with _LOCK:
        _PENDING.clear()


def pending_sessions() -> int:
    with _LOCK:
        return len(_PENDING)


def note_display(session_id: Any, surface_id: Any, template_id: Any = None) -> None:
    """Remember that ``surface_id`` (made from ``template_id``, if any) was accepted this turn. Never raises."""
    try:
        session = safe_component(session_id)
        surface = safe_component(surface_id)
        template = safe_component(template_id) if template_id is not None else None
        with _LOCK:
            entry = _PENDING.get(session)
            if entry is None:
                entry = _PENDING[session] = {"surfaces": [], "templates": []}
                while len(_PENDING) > MAX_SESSIONS:
                    _PENDING.popitem(last=False)
            else:
                _PENDING.move_to_end(session)
            if surface not in entry["surfaces"] and len(entry["surfaces"]) < MAX_SURFACES:
                entry["surfaces"].append(surface)
            if template is not None and template not in entry["templates"] and len(entry["templates"]) < MAX_SURFACES:
                entry["templates"].append(template)
    except InvalidName:
        return
    except Exception:  # noqa: BLE001
        _log.debug("hermes-iris: could not note a display", exc_info=True)


def _take(session: str) -> dict[str, list[str]]:
    with _LOCK:
        return _PENDING.pop(session, None) or {"surfaces": [], "templates": []}


def on_post_llm_call(**kw: Any) -> None:
    """Hermes ``post_llm_call``: logs the turn that just ended for a flagged session. Returns None; never raises."""
    try:
        session_id = kw.get("session_id")
        if not isinstance(session_id, str) or not flags.is_flagged(session_id):
            return None
        session = safe_component(session_id)
        notes = _take(session)
        Store(iris_root()).profile(current_profile()).append_usage(
            {
                "kind": "use",
                "ts": time.time(),
                "session": session,
                "templates_used": notes["templates"],
                "surfaces": notes["surfaces"],
            }
        )
    except Exception:  # noqa: BLE001 - a hook must never break a turn
        _log.debug("hermes-iris: could not write a usage row", exc_info=True)
    return None
