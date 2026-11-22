"""Active chats: the stored session ids Iris has said the person is waiting on.

Iris marks a chat when the person sends to it; the mark is consumed when that turn ends and lapses after six hours.
One file, ``push/active.json`` (``{session id: marked at}``), because the hooks and the routes share only files.
"""

from __future__ import annotations

import threading
import time
from pathlib import Path

from ..genui.store import _atomic_write, _dump, _load, safe_component

#: A mark older than this no longer counts.
TTL_S = 6 * 3600.0

#: How many chats are remembered; the oldest marks are dropped first.
CAP = 200

_LOCK = threading.Lock()


def _path(push_dir: Path) -> Path:
    return Path(push_dir) / "active.json"


def _read(push_dir: Path) -> dict[str, float]:
    data = _load(_path(push_dir)) or {}
    return {k: float(v) for k, v in data.items() if isinstance(k, str) and isinstance(v, (int, float))}


def _now(now: float | None) -> float:
    return time.time() if now is None else now


def mark(push_dir: Path, session_id: object, now: float | None = None) -> None:
    sid = safe_component(session_id)
    t = _now(now)
    with _LOCK:
        marks = {k: v for k, v in _read(push_dir).items() if t - v <= TTL_S}
        marks[sid] = t
        if len(marks) > CAP:
            marks = dict(sorted(marks.items(), key=lambda kv: kv[1], reverse=True)[:CAP])
        _atomic_write(_path(push_dir), _dump(marks))


def is_active(push_dir: Path, session_id: object, now: float | None = None) -> bool:
    marked = _read(push_dir).get(safe_component(session_id))
    return marked is not None and _now(now) - marked <= TTL_S


def take(push_dir: Path, session_id: object, now: float | None = None) -> bool:
    """True, and the mark is cleared, when the chat was marked and the mark is still fresh."""
    sid = safe_component(session_id)
    t = _now(now)
    with _LOCK:
        marks = _read(push_dir)
        marked = marks.pop(sid, None)
        if marked is None:
            return False
        _atomic_write(_path(push_dir), _dump(marks))
        return t - marked <= TTL_S
