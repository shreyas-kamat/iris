"""iris-probe dashboard routes (mounted at /api/plugins/iris-probe/). Throwaway; delete after the probe."""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path

from fastapi import APIRouter

from hermes_constants import get_hermes_home

router = APIRouter()
_LOCK = threading.Lock()


def _dir() -> Path:
    d = get_hermes_home() / "iris-probe"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _read_flags() -> list[str]:
    try:
        return list(json.loads((_dir() / "flags.json").read_text("utf-8")))
    except (OSError, ValueError):
        return []


def _write_flags(flags: list[str]) -> None:
    tmp = _dir() / "flags.json.tmp"
    tmp.write_text(json.dumps(sorted(set(flags))), "utf-8")
    os.replace(tmp, _dir() / "flags.json")


@router.get("/hello")
def hello(profile: str | None = None):
    return {"ok": True, "plugin": "iris-probe", "profile": profile, "home": str(get_hermes_home()), "pid": os.getpid()}


@router.post("/sessions/{session_id}/flag")
def flag(session_id: str, profile: str | None = None):
    with _LOCK:
        flags = _read_flags()
        flags.append(session_id)
        _write_flags(flags)
    return {"ok": True, "flags": _read_flags()}


@router.delete("/sessions/{session_id}/flag")
def unflag(session_id: str, profile: str | None = None):
    with _LOCK:
        _write_flags([f for f in _read_flags() if f != session_id])
    return {"ok": True, "flags": _read_flags()}


@router.get("/events")
def events(since: float = 0.0, profile: str | None = None):
    path = _dir() / "events.jsonl"
    rows = []
    if path.exists():
        for line in path.read_text("utf-8").splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("t", 0) > since:
                rows.append(row)
    return {"ok": True, "pid": os.getpid(), "flags": _read_flags(), "events": rows[-500:]}


@router.post("/events/clear")
def clear(profile: str | None = None):
    with _LOCK:
        (_dir() / "events.jsonl").unlink(missing_ok=True)
    return {"ok": True}
