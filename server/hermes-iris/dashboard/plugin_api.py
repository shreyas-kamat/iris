"""hermes-iris dashboard routes, mounted by Hermes at ``/api/plugins/iris/``.

Hermes imports this file on its own (``spec_from_file_location``), outside any package, so it loads the plugin
directory as a package itself to reach the shared modules. Every route sits behind the dashboard's own login (measured
in Phase 0.2), so none checks credentials, and every one takes ``?profile=``.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter, HTTPException

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
router = APIRouter()


def _profile_store(profile: str | None):
    """The caller's profile store. A missing ``?profile=`` is the default profile; an unsafe one is a 400."""
    try:
        return store_mod.Store(paths.iris_root()).profile("default" if profile is None else profile)
    except store_mod.InvalidName as e:
        raise HTTPException(status_code=400, detail=f"profile: {e}") from None


#: Names of the features this build offers; Iris reads them to decide what to show. Appended to as tasks land.
FEATURES: list[str] = ["capabilities", "session-flag"]


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
