"""hermes-iris dashboard routes, mounted by Hermes at ``/api/plugins/iris/``.

Hermes imports this file on its own (``spec_from_file_location``), outside any package, so it loads the plugin
directory as a package itself to reach the shared modules. Every route sits behind the dashboard's own login (measured
in Phase 0.2), so none checks credentials, and every one takes ``?profile=``.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter

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
router = APIRouter()

#: Names of the features this build offers; Iris reads them to decide what to show. Appended to as tasks land.
FEATURES: list[str] = ["capabilities"]


@router.get("/capabilities")
def capabilities(profile: str | None = None):
    return {
        "version": core.__version__,
        "openui": core.OPENUI_VERSION,
        "library_ids": [],
        "features": FEATURES,
    }
