"""The ``iris_ui`` service: check what the model sent, expand a template if asked, validate, store, answer.

The answer is what the model sees, so it is short: ``{ok, surface_id, rev}`` or ``{ok: false, errors: [...]}`` where
each error is one line it can act on. Nothing here logs a program, its data or the fallback text.
"""

from __future__ import annotations

import threading
import time
from typing import Any

from ..openui import Library, validate_program
from . import templates, usage
from .store import InvalidName, ProfileStore, StoreError, safe_component

PLACEMENTS = ("inline", "reply_kit")
FALLBACK_MAX = 8000
_LOCK = threading.Lock()


def _fail(*errors: str) -> dict[str, Any]:
    return {"ok": False, "errors": list(errors)}


def submit(profile: ProfileStore, library: Library, session_id: Any, args: Any) -> dict[str, Any]:
    """Handles one ``iris_ui`` call for ``session_id`` (the stored id)."""
    if not isinstance(args, dict):
        return _fail("the arguments must be an object")
    try:
        session = safe_component(session_id)
    except InvalidName:
        return _fail("there is no usable session for this call")

    surface_id = args.get("surface_id")
    try:
        safe_component(surface_id)
    except InvalidName:
        return _fail("surface_id must be 1-64 letters, digits, '_' or '-'")

    delete = args.get("delete")
    if delete is not None and not isinstance(delete, bool):
        return _fail("delete must be true or false")
    if delete:
        with _LOCK:
            return {"ok": True, "surface_id": surface_id, "deleted": profile.delete_surface(session, surface_id)}

    problems: list[str] = []
    placement = args.get("placement")
    if placement is not None and placement not in PLACEMENTS:
        problems.append(f"placement must be one of {', '.join(PLACEMENTS)}")
    for key, kind, word in (("code", str, "text"), ("template", str, "a template id"), ("data", dict, "an object"), ("fallback", str, "text")):
        if args.get(key) is not None and not isinstance(args[key], kind):
            problems.append(f"{key} must be {word}")
    fallback = args.get("fallback")
    if not problems:
        if not isinstance(fallback, str) or not fallback.strip():
            problems.append("fallback is required: the same content as Markdown, for places that cannot show the display")
        elif len(fallback) > FALLBACK_MAX:
            problems.append(f"fallback is longer than {FALLBACK_MAX} characters")
        if (args.get("code") is None) == (args.get("template") is None):
            problems.append("give either code, or template with data, not both and not neither")
    if problems:
        return _fail(*problems)

    template_id = args.get("template")
    if template_id is not None:
        try:
            template = profile.get_template(template_id)
        except InvalidName:
            template = None
        if template is None:
            known = [i for i in profile.list_templates() if (profile.get_template(i) or {}).get("status") == "approved"]
            listing = ", ".join(known[:20]) if known else "none yet"
            return _fail(f'unknown template "{template_id}". Available templates: {listing}')
        if template.get("status") != "approved":
            return _fail(f'template "{template_id}" is not approved yet; use code instead')
        if args.get("data") is None:
            return _fail("a template needs data")
        try:
            code = templates.expand(template, args["data"])
        except templates.TemplateError as e:
            return _fail(*e.errors)
        if placement is None and template.get("kind") == "reply_kit":
            placement = "reply_kit"
    else:
        code = args["code"]
    placement = placement or "inline"

    verdict = validate_program(library, code)
    if not verdict.ok:
        return _fail(*verdict.lines)

    try:
        with _LOCK:
            existing = profile.get_surface(session, surface_id)
            now = time.time()
            rev = (existing.get("rev", 0) if existing else 0) + 1
            profile.put_surface(
                session,
                surface_id,
                {
                    "surface_id": surface_id,
                    "session": session,
                    "placement": placement,
                    "template": template_id,
                    "code": code,
                    "fallback": fallback,
                    "rev": rev,
                    "created": existing.get("created", now) if existing else now,
                    "updated": now,
                },
            )
    except StoreError:
        return _fail("the display could not be saved; try again")
    usage.note_display(session, surface_id, template_id)
    return {"ok": True, "surface_id": surface_id, "rev": rev}
