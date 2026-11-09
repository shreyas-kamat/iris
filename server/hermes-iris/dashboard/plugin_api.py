"""hermes-iris dashboard routes, mounted by Hermes at ``/api/plugins/iris/``.

Hermes imports this file on its own (``spec_from_file_location``), outside any package, so it loads the plugin
directory as a package itself to reach the shared modules. Every route sits behind the dashboard's own login (measured
in Phase 0.2), so none checks credentials, and every one takes ``?profile=``.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse

_PACKAGE = "hermes_iris"
_ROOT = Path(__file__).resolve().parent.parent


def _core():
    """The plugin package, loaded once per process under a fixed private name."""
    mod = sys.modules.get(_PACKAGE)
    if mod is None:
        spec = importlib.util.spec_from_file_location(
            _PACKAGE, _ROOT / "__init__.py", submodule_search_locations=[str(_ROOT)]
        )
        assert spec and spec.loader
        mod = importlib.util.module_from_spec(spec)
        sys.modules[_PACKAGE] = mod
        try:
            spec.loader.exec_module(mod)
        except Exception:
            sys.modules.pop(_PACKAGE, None)
            raise
    return mod


core = _core()
catalog = importlib.import_module(f"{_PACKAGE}.genui.catalog")
store_mod = importlib.import_module(f"{_PACKAGE}.genui.store")
paths = importlib.import_module(f"{_PACKAGE}.genui.paths")
personal = importlib.import_module(f"{_PACKAGE}.genui.personal")
feedback = importlib.import_module(f"{_PACKAGE}.genui.feedback")
router = APIRouter()


def _profile_store(profile: str | None):
    """The caller's profile store. A missing ``?profile=`` is the default profile; an unsafe one is a 400."""
    try:
        return store_mod.Store(paths.iris_root()).profile("default" if profile is None else profile)
    except store_mod.InvalidName as e:
        raise HTTPException(status_code=400, detail=f"profile: {e}") from None


#: Names of the features this build offers; Iris reads them to decide what to show. Appended to as tasks land.
FEATURES: list[str] = ["capabilities", "session-flag", "surfaces", "profile", "templates", "feedback", "refine"]


@router.get("/capabilities")
def capabilities(profile: str | None = None):
    return {
        "version": core.__version__,
        "openui": core.OPENUI_VERSION,
        "library_ids": catalog.library_ids(),
        "features": FEATURES,
    }


# ---- sessions: switching generated UI on (D3) -----------------------------------------------------------------------


def _session_flag(session_id: str, profile: str | None, action: str):
    p = _profile_store(profile)
    try:
        if action == "set":
            p.flag_session(session_id)
        elif action == "clear":
            p.unflag_session(session_id)
        flagged = p.is_flagged(session_id)
    except store_mod.InvalidName as e:
        raise HTTPException(status_code=400, detail=f"session: {e}") from None
    return {"ok": True, "session": session_id, "flagged": flagged}


@router.post("/sessions/{session_id}/genui")
def flag_session(session_id: str, profile: str | None = None):
    """Flags a session by its *stored* id (the only id hooks see; Phase 0.5). Iris re-sends it after every reconnect."""
    return _session_flag(session_id, profile, "set")


@router.get("/sessions/{session_id}/genui")
def get_session_flag(session_id: str, profile: str | None = None):
    return _session_flag(session_id, profile, "get")


@router.delete("/sessions/{session_id}/genui")
def unflag_session(session_id: str, profile: str | None = None):
    return _session_flag(session_id, profile, "clear")


# ---- surfaces: what the agent showed, for the app to render ---------------------------------------------------------


@router.get("/surfaces/{session_id}")
def list_surfaces(session_id: str, profile: str | None = None):
    """A summary of every surface in a session (no programs; fetch one for its code)."""
    p = _profile_store(profile)
    try:
        ids = p.list_surfaces(session_id)
    except store_mod.InvalidName as e:
        raise HTTPException(status_code=400, detail=f"session: {e}") from None
    out = []
    for surface_id in ids:
        s = p.get_surface(session_id, surface_id)
        if s is None:
            continue
        out.append({k: s.get(k) for k in ("surface_id", "rev", "placement", "template", "updated")})
    return {"ok": True, "session": session_id, "surfaces": out}


@router.get("/surfaces/{session_id}/{surface_id}")
def get_surface(session_id: str, surface_id: str, profile: str | None = None):
    p = _profile_store(profile)
    try:
        s = p.get_surface(session_id, surface_id)
    except store_mod.InvalidName as e:
        raise HTTPException(status_code=400, detail=str(e)) from None
    if s is None:
        raise HTTPException(status_code=404, detail="no such surface")
    return {"ok": True, "surface": s}


# ---- the person's profile and templates (Phase 5): the agent proposes, the person decides here ------------------------


async def _json_body(request: Request):
    try:
        return await request.json()
    except ValueError:
        return None


def _answer(result: dict):
    """A service result as a response: 422 with ``{ok: false, errors}`` when it was refused, otherwise the result."""
    if result.get("ok") is False:
        return JSONResponse(result, status_code=422)
    return result


@router.get("/profile")
def get_profile(profile: str | None = None):
    return personal.get_profile(_profile_store(profile))


@router.put("/profile")
async def put_profile(request: Request, profile: str | None = None):
    return _answer(personal.put_profile(_profile_store(profile), await _json_body(request)))


@router.get("/templates")
def list_templates(profile: str | None = None, status: str | None = None):
    """Every template with its program and sample, for the review and Displays screens."""
    if status is not None and status not in personal.STATUSES:
        raise HTTPException(status_code=400, detail=f"status must be one of {', '.join(personal.STATUSES)}")
    return {"ok": True, "templates": personal.list_templates(_profile_store(profile), status)}


def _template_id(template_id: str) -> str:
    try:
        return store_mod.safe_component(template_id)
    except store_mod.InvalidName as e:
        raise HTTPException(status_code=400, detail=f"template: {e}") from None


@router.get("/templates/{template_id}")
def get_template(template_id: str, profile: str | None = None):
    t = _profile_store(profile).get_template(_template_id(template_id))
    if t is None:
        raise HTTPException(status_code=404, detail="no such template")
    return {"ok": True, "template": t}


@router.put("/templates/{template_id}")
async def put_template(template_id: str, request: Request, profile: str | None = None):
    """The person's edit or approval. Sent fields are merged onto the stored template and the result is validated."""
    p = _profile_store(profile)
    return _answer(personal.put_template(p, catalog.v1(), _template_id(template_id), await _json_body(request)))


@router.delete("/templates/{template_id}")
def delete_template(template_id: str, profile: str | None = None):
    tid = _template_id(template_id)
    return {"ok": True, "id": tid, "deleted": _profile_store(profile).delete_template(tid)}


@router.post("/feedback")
async def post_feedback(request: Request, profile: str | None = None):
    """Signals about displays the app drew (used, expanded, dismissed, not useful). Best effort on the app's side."""
    return _answer(feedback.record(_profile_store(profile), await _json_body(request)))
