"""Hook-side lookup of the session flag (D3). Hooks run on every turn of every session, so nothing here may raise."""

from __future__ import annotations

from .paths import current_profile, iris_root
from .store import Store


def is_flagged(session_id: str, profile: str | None = None) -> bool:
    """True when Iris switched generated UI on for this stored session id. Any problem reads as "not flagged"."""
    try:
        return Store(iris_root()).profile(profile or current_profile()).is_flagged(session_id)
    except Exception:  # noqa: BLE001 - a bad id, a missing home or an unreadable file must not break a turn
        return False
