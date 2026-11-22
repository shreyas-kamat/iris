"""The device registry: one file per Iris install, ``push/devices/<device id>.json``.

A device holds its platform, its APNs token (iOS only) and the person's notification settings. Settings live on the
server so a device in ``text`` mode never receives content (see ``render.py``).
"""

from __future__ import annotations

import copy
import re
import threading
import time
from pathlib import Path
from typing import Any

from ..genui.store import InvalidName, _atomic_write, _dump, _load, _names, safe_component

DEFAULT_TEXT = "Attention!"
TEXT_MAX = 100
EVENTS = ("reply", "approval", "job")
MODES = ("content", "text")
PLATFORMS = ("android", "ios")

DEFAULT_SETTINGS: dict[str, dict[str, Any]] = {
    "reply": {"on": True, "text": DEFAULT_TEXT, "mode": "text"},
    "approval": {"on": True, "text": DEFAULT_TEXT, "mode": "content"},
    "job": {"on": True, "text": DEFAULT_TEXT, "mode": "content"},
}

_TOKEN = re.compile(r"[0-9A-Fa-f]{64,200}")
_LOCK = threading.Lock()


class InvalidDevice(ValueError):
    """A device registration that is not acceptable (platform, token or shape)."""


def _normalize_event(raw: object, default: dict[str, Any]) -> dict[str, Any]:
    out = dict(default)
    if not isinstance(raw, dict):
        return out
    if isinstance(raw.get("on"), bool):
        out["on"] = raw["on"]
    text = raw.get("text")
    if isinstance(text, str):
        out["text"] = text.strip()[:TEXT_MAX].rstrip() or DEFAULT_TEXT
    if raw.get("mode") in MODES:
        out["mode"] = raw["mode"]
    return out


def normalize_settings(raw: object) -> dict[str, dict[str, Any]]:
    """``raw`` as complete, valid settings: defaults fill gaps, unknown keys go, ``text`` is 1-100 characters."""
    src = raw if isinstance(raw, dict) else {}
    return {kind: _normalize_event(src.get(kind), DEFAULT_SETTINGS[kind]) for kind in EVENTS}


def _merge_settings(current: dict[str, Any], patch: object) -> dict[str, Any]:
    """``patch`` applied onto ``current`` event by event, so a partial update keeps the rest."""
    src = patch if isinstance(patch, dict) else {}
    merged: dict[str, Any] = {}
    for kind in EVENTS:
        base = dict(current.get(kind, DEFAULT_SETTINGS[kind]))
        part = src.get(kind)
        if isinstance(part, dict):
            base.update({k: v for k, v in part.items() if k in ("on", "text", "mode")})
        merged[kind] = base
    return normalize_settings(merged)


class Devices:
    def __init__(self, push_dir: Path) -> None:
        self._dir = Path(push_dir) / "devices"

    def _path(self, device_id: object) -> Path:
        return self._dir / f"{safe_component(device_id)}.json"

    def register(
        self, device_id: object, platform: object, apns_token: object, app_version: object, settings: object
    ) -> dict[str, Any]:
        did = safe_component(device_id)
        if platform not in PLATFORMS:
            raise InvalidDevice("platform must be 'android' or 'ios'")
        if apns_token is not None and (not isinstance(apns_token, str) or _TOKEN.fullmatch(apns_token) is None):
            raise InvalidDevice("apns_token must be 64-200 hex characters")
        if platform == "android":
            apns_token = None
        version = app_version if isinstance(app_version, str) else ""
        with _LOCK:
            existing = _load(self._path(did))
            record = {
                "device_id": did,
                "platform": platform,
                "apns_token": apns_token.lower() if isinstance(apns_token, str) else None,
                "app_version": version[:32],
                "settings": normalize_settings(settings),
                "registered": existing.get("registered") if existing else time.time(),
                "updated": time.time(),
            }
            _atomic_write(self._path(did), _dump(record))
        return copy.deepcopy(record)

    def get(self, device_id: object) -> dict[str, Any] | None:
        return _load(self._path(device_id))

    def all(self) -> list[dict[str, Any]]:
        out = []
        for name in _names(self._dir, ".json"):
            record = _load(self._dir / f"{name}.json")
            if record is not None:
                out.append(record)
        return out

    def update_settings(self, device_id: object, settings: object) -> dict[str, Any] | None:
        with _LOCK:
            record = _load(self._path(device_id))
            if record is None:
                return None
            record["settings"] = _merge_settings(record.get("settings", {}), settings)
            record["updated"] = time.time()
            _atomic_write(self._path(device_id), _dump(record))
        return record

    def remove(self, device_id: object) -> bool:
        try:
            self._path(device_id).unlink()
        except FileNotFoundError:
            return False
        return True


__all__ = ["DEFAULT_SETTINGS", "Devices", "InvalidDevice", "InvalidName", "normalize_settings"]
