"""The Android event stream: Server-Sent Events that Iris's foreground service holds open.

Frames are ``id: <event id>`` / ``event: notice`` / ``data: <notice json>``; an idle stream sends a ``: ping`` comment
so proxies keep it open and Iris can tell a dead connection from a quiet one. The outbox is polled once a second.
A connection resumes from a cursor (``after``) and gets a short replay; a brand-new connection (no cursor) starts from
now, so installing Iris does not buzz for things that happened before.

Each notice is rendered per device on every poll, so a settings change applies to a stream that is already open.
"""

from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path
from typing import Any, AsyncIterator, Awaitable, Callable

from . import outbox, render
from .devices import Devices

POLL_S = 1.0
PING_S = 25.0
#: Events older than this are not replayed to a device that was offline.
REPLAY_S = 15 * 60.0


def _frame(notice: dict[str, Any]) -> str:
    data = json.dumps(notice, ensure_ascii=False, separators=(",", ":"))
    return f"id: {notice['event_id']}\nevent: notice\ndata: {data}\n\n"


def _latest_id(push_dir: Path) -> str:
    events = outbox.read_after(push_dir, None, float("inf"))
    return events[-1]["id"] if events else "0"


async def frames(
    push_dir: Path,
    device_id: str,
    after: str | None,
    *,
    now: Callable[[], float] = time.time,
    sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
) -> AsyncIterator[str]:
    """SSE frames for one Android device until the device is removed or the caller stops iterating."""
    devices = Devices(push_dir)
    cursor = after if after is not None else _latest_id(push_dir)
    last_sent = now()
    while True:
        device = devices.get(device_id)
        if device is None:
            return
        for event in outbox.read_after(push_dir, cursor, REPLAY_S, now=now()):
            cursor = event["id"]
            notice = render.notice(event, device.get("settings", {}))
            if notice is not None:
                yield _frame(notice)
                last_sent = now()
        if now() - last_sent >= PING_S:
            yield ": ping\n\n"
            last_sent = now()
        await sleep(POLL_S)
