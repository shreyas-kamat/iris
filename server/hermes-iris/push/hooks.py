"""Hermes hooks that turn agent activity into outbox events.

All of these run in the agent process, on every turn of every session, so each one is wrapped: it never raises, never
blocks on the network (it appends to a file), and never logs content. The facts they rely on were measured in the
Task 1 probe (``docs/superpowers/plans/2026-11-13-push-probe.md``):

* ``on_session_end`` fires once per finished turn (it carries a ``turn_id``) and once more when a chat is closed (no
  ``turn_id``; ignored here). It does not carry the reply, but ``post_llm_call`` fired just before it with the same
  ``turn_id`` and the reply text, so a short preview is kept in memory in between.
* A cron run is a turn with ``platform == "cron"``; its job id is in ``task_id`` (``cron:<job id>:<run>``).
* ``pre_approval_request`` with ``surface == "smart"`` is the guardian model's own check; nobody is asked. Only
  ``gateway`` / ``cli`` asks reach a person.
"""

from __future__ import annotations

import json
import logging
import threading
from collections import OrderedDict
from typing import Any, Callable

from ..genui.paths import current_profile, hermes_home, iris_root
from ..genui.store import Store
from . import active, outbox

_log = logging.getLogger("hermes_iris")

PREVIEW_MAX = 140
COMMAND_MAX = 500
#: Turn previews waiting for their ``on_session_end``; the oldest are forgotten past this.
MAX_PREVIEWS = 50
#: Chats with an announced approval, so a response only withdraws what was shown.
MAX_APPROVALS = 50

_LOCK = threading.Lock()
_PREVIEWS: OrderedDict[str, str] = OrderedDict()
_APPROVALS: OrderedDict[str, None] = OrderedDict()


def _no_title(session_id: str) -> str | None:
    return None


#: ``session id -> chat title`` or ``None``. Not wired to Hermes's session store yet (no verified API), so a
#: notification falls back to the person's own text.
title_for: Callable[[str], str | None] = _no_title


def reset() -> None:
    with _LOCK:
        _PREVIEWS.clear()
        _APPROVALS.clear()


def pending_previews() -> int:
    with _LOCK:
        return len(_PREVIEWS)


def _push_dir():
    return Store(iris_root()).profile(current_profile()).push_dir


def _bounded_put(table: OrderedDict, key: str, value: Any, cap: int) -> None:
    table[key] = value
    table.move_to_end(key)
    while len(table) > cap:
        table.popitem(last=False)


def _preview(text: object) -> str | None:
    if not isinstance(text, str):
        return None
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line if len(line) <= PREVIEW_MAX else line[: PREVIEW_MAX - 1].rstrip() + "…"
    return None


def _title(session_id: str) -> str | None:
    try:
        title = title_for(session_id)
    except Exception:  # noqa: BLE001
        return None
    return title if isinstance(title, str) and title.strip() else None


def on_post_llm_call(**kw: Any) -> None:
    """Keeps a first-line preview of the reply for the ``on_session_end`` of the same turn."""
    try:
        turn_id = kw.get("turn_id")
        preview = _preview(kw.get("assistant_response"))
        if isinstance(turn_id, str) and turn_id and preview:
            with _LOCK:
                _bounded_put(_PREVIEWS, turn_id, preview, MAX_PREVIEWS)
    except Exception:  # noqa: BLE001 - a hook must never break a turn
        _log.debug("hermes-iris: push could not note a reply", exc_info=True)
    return None


def _job_name(job_id: str) -> str:
    try:
        data = json.loads((hermes_home() / "cron" / "jobs.json").read_text("utf-8"))
        for job in data.get("jobs", []):
            if isinstance(job, dict) and job.get("id") == job_id and isinstance(job.get("name"), str):
                return job["name"]
    except Exception:  # noqa: BLE001 - no file, bad JSON, no home: the id will do
        pass
    return job_id


def _cron_job_id(kw: dict[str, Any]) -> str | None:
    task_id = kw.get("task_id")
    if isinstance(task_id, str):
        parts = task_id.split(":")
        if len(parts) >= 2 and parts[0] == "cron" and parts[1]:
            return parts[1]
    session_id = kw.get("session_id")  # cron_<job id>_<YYYYMMDD>_<HHMMSS>
    if isinstance(session_id, str) and session_id.startswith("cron_"):
        pieces = session_id[len("cron_"):].rsplit("_", 2)
        if len(pieces) == 3 and pieces[0]:
            return pieces[0]
    return None


def on_session_end(**kw: Any) -> None:
    """A finished turn: a reply for an active Iris chat, or a finished scheduled job."""
    try:
        turn_id = kw.get("turn_id")
        if not isinstance(turn_id, str) or not turn_id:
            return None  # a chat closing, not a turn
        with _LOCK:
            preview = _PREVIEWS.pop(turn_id, None)
        session_id = kw.get("session_id")
        if not isinstance(session_id, str):
            return None
        interrupted = bool(kw.get("interrupted"))
        failed = bool(kw.get("failed")) or not kw.get("completed")
        push_dir = _push_dir()
        if kw.get("platform") == "cron":
            job_id = _cron_job_id(kw)
            if interrupted or job_id is None:
                return None
            outbox.append(push_dir, {
                "kind": "job", "session_id": session_id, "job_id": job_id, "job_name": _job_name(job_id),
                "outcome": "failed" if failed else "completed",
            })
            return None
        if not active.take(push_dir, session_id) or interrupted:
            return None
        outbox.append(push_dir, {
            "kind": "reply", "session_id": session_id, "title": _title(session_id),
            "outcome": "failed" if failed else "completed", "preview": None if failed else preview,
        })
    except Exception:  # noqa: BLE001
        _log.debug("hermes-iris: push could not record a finished turn", exc_info=True)
    return None


def on_pre_approval_request(**kw: Any) -> None:
    """A person is being asked to approve a command in a chat they are waiting on."""
    try:
        session_key = kw.get("session_key")
        if kw.get("surface") not in ("gateway", "cli") or kw.get("coalesced") or not isinstance(session_key, str):
            return None
        push_dir = _push_dir()
        if not active.is_active(push_dir, session_key):
            return None
        command = kw.get("command")
        description = kw.get("description")
        outbox.append(push_dir, {
            "kind": "approval", "session_id": session_key, "title": _title(session_key),
            "command": command[:COMMAND_MAX] if isinstance(command, str) else None,
            "description": description if isinstance(description, str) else None,
        })
        with _LOCK:
            _bounded_put(_APPROVALS, session_key, None, MAX_APPROVALS)
    except Exception:  # noqa: BLE001
        _log.debug("hermes-iris: push could not record an approval", exc_info=True)
    return None


def on_post_approval_response(**kw: Any) -> None:
    """The ask was answered (or timed out): withdraw the notification that announced it."""
    try:
        session_key = kw.get("session_key")
        if kw.get("surface") not in ("gateway", "cli") or not isinstance(session_key, str):
            return None
        with _LOCK:
            announced = _APPROVALS.pop(session_key, 0) is None
        if announced:
            outbox.append(_push_dir(), {"kind": "approval_done", "session_id": session_key})
    except Exception:  # noqa: BLE001
        _log.debug("hermes-iris: push could not record an approval answer", exc_info=True)
    return None
