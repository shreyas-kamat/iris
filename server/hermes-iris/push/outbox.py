"""The event outbox: ``push/outbox.jsonl``, one JSON object per line, appended by the hooks and read by the stream and
the APNs worker.

Ids are increasing integers as strings (``time.time_ns``), so a cursor is just "the last id I saw". The file keeps
24 hours and 1,000 events; trimming rewrites it atomically. Hooks in two processes can append at once; each append is
one short ``O_APPEND`` write, and a trim racing an append can at worst lose that one event.
"""

from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path
from typing import Any

from ..genui.store import _atomic_write

MAX_AGE_S = 24 * 3600.0
MAX_EVENTS = 1000

_LOCK = threading.Lock()
_last_id = 0


def _path(push_dir: Path) -> Path:
    return Path(push_dir) / "outbox.jsonl"


def _next_id() -> str:
    global _last_id
    _last_id = max(time.time_ns(), _last_id + 1)
    return str(_last_id)


def _parse(text: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue  # a torn or foreign line
        if isinstance(row, dict) and isinstance(row.get("id"), str) and isinstance(row.get("ts"), (int, float)):
            rows.append(row)
    return rows


def _read_all(push_dir: Path) -> list[dict[str, Any]]:
    try:
        return _parse(_path(push_dir).read_text("utf-8"))
    except OSError:
        return []


def append(push_dir: Path, event: dict[str, Any], now: float | None = None) -> str:
    """Stores ``event`` with a new ``id`` and ``ts`` and returns the id. Never reads content back out of ``event``."""
    ts = time.time() if now is None else now
    path = _path(push_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    with _LOCK:
        event_id = _next_id()
        row = {**event, "id": event_id, "ts": ts}
        line = json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n"
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8", newline="") as f:
            f.write(line)
        _trim(push_dir, ts)
    return event_id


def _needs_trim(push_dir: Path, now: float) -> bool:
    """Cheap check (a newline count and the first line) so an ordinary append does not parse the whole file."""
    try:
        raw = _path(push_dir).read_bytes()
    except OSError:
        return False
    if raw.count(b"\n") > MAX_EVENTS:
        return True
    first = _parse(raw.split(b"\n", 1)[0].decode("utf-8", "replace"))
    return bool(first) and now - first[0]["ts"] > MAX_AGE_S


def _trim(push_dir: Path, now: float) -> None:
    if not _needs_trim(push_dir, now):
        return
    rows = _read_all(push_dir)
    keep = [r for r in rows if now - r["ts"] <= MAX_AGE_S][-MAX_EVENTS:]
    if len(keep) == len(rows):
        return
    data = "".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in keep)
    _atomic_write(_path(push_dir), data.encode("utf-8"))


def read_after(
    push_dir: Path, after: str | None, max_age_s: float, now: float | None = None
) -> list[dict[str, Any]]:
    """Events newer than the cursor ``after`` (all of them when it is ``None`` or not an id) and not older than
    ``max_age_s`` seconds, oldest first."""
    t = time.time() if now is None else now
    try:
        cursor = int(after) if after is not None else None
    except ValueError:
        cursor = None
    out = []
    for row in _read_all(push_dir):
        try:
            if cursor is not None and int(row["id"]) <= cursor:
                continue
        except ValueError:
            continue
        if t - row["ts"] <= max_age_s:
            out.append(row)
    return out
