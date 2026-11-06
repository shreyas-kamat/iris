"""iris-probe: throwaway GenUI Phase 0 probe (plan step 0.1). Delete after the probe.

Records event metadata (ids, lengths, timestamps, short previews) to
``<hermes home>/iris-probe/events.jsonl``; the dashboard route ``GET /events`` reads it back.
Flags live in ``<hermes home>/iris-probe/flags.json`` because the dashboard's ``plugin_api``
module is imported separately from this package (and may run in another process).
"""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from typing import Any

from hermes_constants import get_hermes_home

_LOCK = threading.Lock()
_STRIP_MARKER = "[[iris-strip]]"


def _dir() -> Path:
    d = get_hermes_home() / "iris-probe"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _flags() -> set[str]:
    try:
        return set(json.loads((_dir() / "flags.json").read_text("utf-8")))
    except (OSError, ValueError):
        return set()


def _record(event: str, **fields: Any) -> None:
    row = {"t": round(time.time(), 3), "event": event, "home": str(get_hermes_home()), **fields}
    with _LOCK, (_dir() / "events.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, default=str) + "\n")


def _preview(value: Any, n: int = 80) -> str:
    text = value if isinstance(value, str) else json.dumps(value, default=str)
    return text[:n]


def _handle_iris_probe(args: dict, **kw: Any) -> str:
    payload = args.get("payload", "") if isinstance(args, dict) else ""
    length = len(payload) if isinstance(payload, str) else len(json.dumps(payload, default=str))
    _record("tool.handler", length=length, kw_keys=sorted(kw))
    return json.dumps({"length": length})


_SCHEMA = {
    "name": "iris_probe",
    "description": "Diagnostic no-op for the Iris app. Only call it when the user explicitly asks you to "
    "call iris_probe; pass exactly the payload they ask for. Returns the payload's length.",
    "parameters": {
        "type": "object",
        "properties": {"payload": {"type": "string", "description": "Any text."}},
        "required": ["payload"],
    },
}


def _ids(kw: dict) -> dict:
    return {k: kw.get(k) for k in ("session_id", "task_id", "turn_id", "platform", "tool_call_id") if k in kw}


def _on_pre_llm_call(**kw: Any):
    sid = kw.get("session_id") or ""
    flagged = sid in _flags()
    _record(
        "pre_llm_call", **_ids(kw), flagged=flagged, is_first_turn=kw.get("is_first_turn"),
        sender_id=kw.get("sender_id"), parent_session_id=kw.get("parent_session_id"),
        model=kw.get("model"), user_preview=_preview(kw.get("user_message", "")),
        history_len=len(kw.get("conversation_history") or []), kw_keys=sorted(kw),
    )
    return {"context": "[iris-probe]"} if flagged else None


def _on_pre_tool_call(**kw: Any):
    args = kw.get("args") or {}
    payload = args.get("payload") if isinstance(args, dict) else None
    _record(
        "pre_tool_call", **_ids(kw), tool_name=kw.get("tool_name"),
        arg_keys=sorted(args) if isinstance(args, dict) else None,
        payload_len=len(payload) if isinstance(payload, str) else None, kw_keys=sorted(kw),
    )
    return None


def _on_post_llm_call(**kw: Any):
    text = kw.get("assistant_response") or ""
    _record(
        "post_llm_call", **_ids(kw), flagged=(kw.get("session_id") or "") in _flags(),
        response_len=len(text) if isinstance(text, str) else None,
        response_preview=_preview(text), kw_keys=sorted(kw),
    )
    return None


def _on_transform_llm_output(**kw: Any):
    """0.8 (D2b): in a flagged session, strip the marker from the final text."""
    text = kw.get("response_text") or ""
    sid = kw.get("session_id") or ""
    hit = isinstance(text, str) and _STRIP_MARKER in text
    _record("transform_llm_output", **_ids(kw), flagged=sid in _flags(), marker=hit, kw_keys=sorted(kw))
    if hit and sid in _flags():
        return text.replace(_STRIP_MARKER, "").strip() + "\n(stripped by iris-probe)"
    return None


def _on_session_start(**kw: Any):
    _record("on_session_start", **_ids(kw), kw_keys=sorted(kw))
    return None


def register(ctx) -> None:
    ctx.register_tool(name="iris_probe", toolset="iris_probe", schema=_SCHEMA, handler=_handle_iris_probe)
    ctx.register_hook("pre_llm_call", _on_pre_llm_call)
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
    ctx.register_hook("post_llm_call", _on_post_llm_call)
    ctx.register_hook("transform_llm_output", _on_transform_llm_output)
    ctx.register_hook("on_session_start", _on_session_start)
    _record("register")
