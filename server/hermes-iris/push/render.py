"""Turns an outbox event into what one device is allowed to see.

The person's own words are the title. In ``text`` mode nothing else leaves the server for that device: the result
holds no ``preview``, ``command``, ``job_name`` or ``description``, only ids Iris needs to open the right chat.
"""

from __future__ import annotations

from typing import Any


def _body(event: dict[str, Any], kind: str) -> str | None:
    title = event.get("title") or None
    if kind == "reply":
        if event.get("outcome") == "failed":
            return f"Reply failed: {title}" if title else "Reply failed"
        return event.get("preview") or title
    if kind == "approval":
        return event.get("command") or event.get("description") or None
    if kind == "job":
        name = event.get("job_name") or event.get("job_id") or "A scheduled job"
        if event.get("outcome") == "no_output":
            return f"{name} produced no output"
        if event.get("outcome") == "failed":
            return f"{name} failed"
        return f"{name} finished"
    return None


def notice(event: dict[str, Any], settings: dict[str, Any]) -> dict[str, Any] | None:
    """The notification for ``event`` under a device's ``settings``, or ``None`` when that kind is switched off."""
    kind = event.get("kind")
    session_id = event.get("session_id")
    event_id = event.get("id")
    if kind == "approval_done":
        # Settings do not apply: this only withdraws a notification that was already shown.
        return {"event_id": event_id, "kind": "approval_done", "session_id": session_id,
                "collapse": f"approval-{session_id}"}
    if kind not in ("reply", "approval", "job"):
        return None
    conf = settings.get(kind)
    if not isinstance(conf, dict) or not conf.get("on"):
        return None
    return {
        "event_id": event_id,
        "kind": kind,
        "session_id": session_id,
        "title": conf.get("text"),
        "body": _body(event, kind) if conf.get("mode") == "content" else None,
        "category": "approval" if kind == "approval" else None,
        "collapse": f"{kind}-{session_id}",
    }
