"""The per-profile file store: ``<root>/<profile>/{profile.json, templates/, surfaces/<session>/, usage.jsonl}``.

Files only, because the hooks (agent process) and the routes (dashboard process) share nothing else. Every name that
becomes a path component goes through :func:`safe_component`; every write is a temp file in the same directory
followed by ``os.replace``; files are private to the owner. Nothing here logs content.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import threading
from pathlib import Path
from typing import Any

#: Rotate ``usage.jsonl`` once it reaches this size; one rotated file (``usage.jsonl.1``) is kept.
USAGE_MAX_BYTES = 1024 * 1024

_NAME = re.compile(r"[A-Za-z0-9_-]{1,64}")
_USAGE_LOCK = threading.Lock()


class StoreError(Exception):
    """The store could not do what was asked (bad shape, or a path that leaves the store)."""


class InvalidName(StoreError, ValueError):
    """A profile, session, surface or template id that is not safe to use as a path component."""


def safe_component(name: object) -> str:
    """``name`` if it is 1-64 characters of ``A-Z a-z 0-9 _ -``; otherwise :class:`InvalidName`."""
    if not isinstance(name, str) or _NAME.fullmatch(name) is None:
        raise InvalidName("names are 1-64 characters of letters, digits, '_' and '-'")
    return name


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".part")  # mode 0600
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _dump(value: dict[str, Any]) -> bytes:
    if not isinstance(value, dict):
        raise StoreError("a stored record must be a JSON object")
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def _load(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text("utf-8"))
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def _names(directory: Path, suffix: str) -> list[str]:
    try:
        entries = [p for p in directory.iterdir() if p.is_file()]
    except OSError:
        return []
    return sorted(
        p.name[: -len(suffix)]
        for p in entries
        if p.name.endswith(suffix) and _NAME.fullmatch(p.name[: -len(suffix)])
    )


class Store:
    """All profiles under one root (normally ``<hermes root>/iris``)."""

    def __init__(self, root: Path, *, usage_max_bytes: int = USAGE_MAX_BYTES) -> None:
        self.root = Path(root)
        self.usage_max_bytes = usage_max_bytes

    def profile(self, name: object) -> ProfileStore:
        return ProfileStore(self, safe_component(name))


class ProfileStore:
    def __init__(self, store: Store, name: str) -> None:
        self._store = store
        self.name = name

    # -- paths -------------------------------------------------------------------------------------------------

    @property
    def dir(self) -> Path:
        """The profile directory, checked not to be a link out of the store."""
        d = self._store.root / self.name
        if d.is_symlink():
            raise StoreError("the profile directory is a link")
        try:
            d.resolve().relative_to(self._store.root.resolve())
        except ValueError:
            raise StoreError("the profile directory is outside the store") from None
        return d

    def _file(self, *parts: str) -> Path:
        return self.dir.joinpath(*parts)

    # -- profile.json ------------------------------------------------------------------------------------------

    def get_profile(self) -> dict[str, Any] | None:
        return _load(self._file("profile.json"))

    def put_profile(self, profile: dict[str, Any]) -> None:
        _atomic_write(self._file("profile.json"), _dump(profile))

    # -- templates/<id>.json -----------------------------------------------------------------------------------

    def get_template(self, template_id: object) -> dict[str, Any] | None:
        return _load(self._file("templates", f"{safe_component(template_id)}.json"))

    def put_template(self, template_id: object, template: dict[str, Any]) -> None:
        _atomic_write(self._file("templates", f"{safe_component(template_id)}.json"), _dump(template))

    def delete_template(self, template_id: object) -> bool:
        return self._remove(self._file("templates", f"{safe_component(template_id)}.json"))

    def list_templates(self) -> list[str]:
        return _names(self._file("templates"), ".json")

    # -- surfaces/<session>/<surface>.json ---------------------------------------------------------------------

    def get_surface(self, session_id: object, surface_id: object) -> dict[str, Any] | None:
        return _load(self._surface_path(session_id, surface_id))

    def put_surface(self, session_id: object, surface_id: object, surface: dict[str, Any]) -> None:
        _atomic_write(self._surface_path(session_id, surface_id), _dump(surface))

    def delete_surface(self, session_id: object, surface_id: object) -> bool:
        return self._remove(self._surface_path(session_id, surface_id))

    def list_surfaces(self, session_id: object) -> list[str]:
        return _names(self._file("surfaces", safe_component(session_id)), ".json")

    def _surface_path(self, session_id: object, surface_id: object) -> Path:
        return self._file("surfaces", safe_component(session_id), f"{safe_component(surface_id)}.json")

    # -- usage.jsonl -------------------------------------------------------------------------------------------

    def append_usage(self, row: dict[str, Any]) -> None:
        line = json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n"
        path = self._file("usage.jsonl")
        path.parent.mkdir(parents=True, exist_ok=True)
        with _USAGE_LOCK:
            try:
                if path.stat().st_size >= self._store.usage_max_bytes:
                    os.replace(path, path.with_name("usage.jsonl.1"))
            except OSError:
                pass
            fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
            with os.fdopen(fd, "a", encoding="utf-8", newline="") as f:
                f.write(line)

    def read_usage(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for name in ("usage.jsonl.1", "usage.jsonl"):
            try:
                text = self._file(name).read_text("utf-8")
            except OSError:
                continue
            for line in text.splitlines():
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if isinstance(row, dict):
                    rows.append(row)
        return rows

    # -- reset -------------------------------------------------------------------------------------------------

    def reset(self) -> None:
        """Delete everything stored for this profile."""
        d = self._store.root / self.name
        if d.is_symlink():
            d.unlink()
        elif d.exists():
            shutil.rmtree(d)

    @staticmethod
    def _remove(path: Path) -> bool:
        try:
            path.unlink()
        except FileNotFoundError:
            return False
        return True
