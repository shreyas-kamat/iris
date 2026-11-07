"""Signals the app sends about displays it drew: ``used``, ``expanded``, ``dismissed``, ``not_useful``.

Each is one row in the profile's ``usage.jsonl`` (``kind: "signal"``) so ``/iris-refine`` can read use and signals from
one place. Only ids and the signal name are kept: no program, data or text ever reaches the log.
"""

from __future__ import annotations

import time
from typing import Any

from .store import InvalidName, ProfileStore, safe_component

SIGNALS = ("used", "expanded", "dismissed", "not_useful")

#: One request carries at most this many signals; the app batches and sends a few at a time.
MAX_BATCH = 100

_IDS = ("surface", "template", "session")


def record(profile: ProfileStore, body: Any) -> dict[str, Any]:
    """Validates ``{"signals": [...]}`` and appends every row, or refuses the whole batch with ``errors``."""
    items = body.get("signals") if isinstance(body, dict) else None
    if not isinstance(items, list):
        return {"ok": False, "errors": ['the body must be {"signals": [...]}']}
    if len(items) > MAX_BATCH:
        return {"ok": False, "errors": [f"at most {MAX_BATCH} signals per request"]}

    rows: list[dict[str, Any]] = []
    errors: list[str] = []
    now = time.time()
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            errors.append(f"signals[{i}] must be an object")
            continue
        name = item.get("signal")
        if name not in SIGNALS:
            errors.append(f"signals[{i}].signal must be one of {', '.join(SIGNALS)}")
            continue
        row: dict[str, Any] = {"kind": "signal", "ts": now, "signal": name}
        for key in _IDS:
            value = item.get(key)
            if value is None:
                continue
            try:
                row[key] = safe_component(value)
            except InvalidName:
                errors.append(f"signals[{i}].{key} is not a valid id")
                break
        else:
            rows.append(row)
    if errors:
        return {"ok": False, "errors": errors}
    for row in rows:
        profile.append_usage(row)
    return {"ok": True, "accepted": len(rows)}
