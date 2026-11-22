"""The APNs delivery worker: a daemon thread in the dashboard process that sends new outbox events to iPhones.

Every second it visits each profile under the Iris root that has a ``push`` directory, reads the events after that
profile's ``push/apns.cursor`` (skipping any older than 10 minutes), renders each for every registered iOS device and
sends it. The cursor is written after each event, so a restart never sends one twice. A ``retry`` gets one more try
after 5 seconds; a dead token removes the device. Errors are logged by type only, never with content or tokens.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path
from typing import Any, Callable

from ..genui.store import _NAME, Store, _atomic_write
from . import apns, outbox, render
from .devices import Devices

_log = logging.getLogger("hermes_iris")

MAX_AGE_S = 10 * 60.0
POLL_S = 1.0
RETRY_AFTER_S = 5.0

Send = Callable[[Any, str, dict], str]

_thread: threading.Thread | None = None
_start_lock = threading.Lock()


def _cursor_path(push_dir: Path) -> Path:
    return Path(push_dir) / "apns.cursor"


def _read_cursor(push_dir: Path) -> str | None:
    try:
        value = _cursor_path(push_dir).read_text("ascii").strip()
    except (OSError, ValueError):
        return None
    return value if value.isdigit() else None


def _write_cursor(push_dir: Path, event_id: str) -> None:
    _atomic_write(_cursor_path(push_dir), event_id.encode("ascii"))


def _push_dirs(root: Path) -> list[Path]:
    """Each profile's ``push`` directory under ``root``, in name order. Links out of the store are skipped."""
    store = Store(root)
    try:
        names = sorted(p.name for p in Path(root).iterdir() if p.is_dir() and _NAME.fullmatch(p.name))
    except OSError:
        return []
    out = []
    for name in names:
        try:
            push_dir = store.profile(name).push_dir
        except Exception:  # noqa: BLE001 - a link out of the store, or an odd name
            continue
        if push_dir.is_dir() and not push_dir.is_symlink():
            out.append(push_dir)
    return out


def _deliver(cfg: Any, devices: Devices, device: dict, event: dict, send: Send, sleep: Callable[[float], None]) -> bool:
    """Sends ``event`` to one device as its settings say. True when Apple took it."""
    token = device.get("apns_token")
    if device.get("platform") != "ios" or not token:
        return False
    notice = render.notice(event, device.get("settings") or {})
    if notice is None or notice.get("kind") == "approval_done":
        return False
    result = send(cfg, token, notice)
    if result == "retry":
        sleep(RETRY_AFTER_S)
        result = send(cfg, token, notice)
    if result == "drop_device":
        devices.remove(device["device_id"])
        _log.info("hermes-iris: removed an iOS device whose APNs token is no longer valid")
    return result == "ok"


def _serve(push_dir: Path, cfg: Any, now: float, send: Send, sleep: Callable[[float], None]) -> int:
    events = outbox.read_after(push_dir, _read_cursor(push_dir), MAX_AGE_S, now)
    if not events:
        return 0
    devices = Devices(push_dir)
    sent = 0
    for event in events:
        targets = sorted((d for d in devices.all() if d.get("platform") == "ios"), key=lambda d: d["device_id"])
        for device in targets:
            try:
                sent += _deliver(cfg, devices, device, event, send, sleep)
            except Exception as e:  # noqa: BLE001 - one bad device must not stop the others
                _log.warning("hermes-iris: APNs delivery to a device failed (%s)", type(e).__name__)
        _write_cursor(push_dir, event["id"])
    return sent


def run_once(root: Path, now: float, send: Send, sleep: Callable[[float], None] = time.sleep) -> int:
    """One pass over every profile. Returns how many notifications Apple accepted."""
    cfg = apns.load_config(root)
    if cfg is None:
        return 0
    sent = 0
    for push_dir in _push_dirs(root):
        try:
            sent += _serve(push_dir, cfg, now, send, sleep)
        except Exception as e:  # noqa: BLE001 - a broken profile must not stop the rest
            _log.warning("hermes-iris: APNs delivery for a profile failed (%s)", type(e).__name__)
    return sent


def _hold_lock(root: Path):
    """One sender per server: an exclusive lock on ``<root>/push/.worker.lock`` (POSIX only). ``None`` when another
    process holds it; the lock lives as long as the returned file stays open."""
    try:
        import fcntl
    except ImportError:  # Windows (development only)
        return True
    path = Path(root) / "push" / ".worker.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    f = open(path, "a")  # noqa: SIM115 - held open for the life of the process
    try:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.close()
        return None
    os.chmod(path, 0o600)
    return f


def _loop(root: Path) -> None:
    lock = None
    while True:
        try:
            if lock is None and (Path(root) / "push" / "apns.json").is_file():
                lock = _hold_lock(root)
            if lock is not None:
                run_once(root, time.time(), apns.send)
        except Exception as e:  # noqa: BLE001 - the thread must outlive any one bad pass
            _log.warning("hermes-iris: APNs worker pass failed (%s)", type(e).__name__)
        time.sleep(POLL_S)


def start(root: Path) -> threading.Thread:
    """Starts the worker thread once per process and returns it."""
    global _thread
    with _start_lock:
        if _thread is None:
            _thread = threading.Thread(target=_loop, args=(Path(root),), name="hermes-iris-apns", daemon=True)
            _thread.start()
        return _thread


__all__ = ["run_once", "start"]
