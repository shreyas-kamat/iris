"""Test harness: Hermes is not installed here, so stand in for ``hermes_constants`` and load the plugin the two ways
Hermes does (as a package, and ``dashboard/plugin_api.py`` on its own from a file)."""

from __future__ import annotations

import importlib.util
import os
import sys
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def _install_fake_hermes_constants() -> None:
    mod = types.ModuleType("hermes_constants")

    def get_hermes_home() -> Path:
        return Path(os.environ["HERMES_HOME"])

    mod.get_hermes_home = get_hermes_home  # type: ignore[attr-defined]
    mod.get_default_hermes_root = get_hermes_home  # type: ignore[attr-defined]
    mod.profile_name_for_home = lambda path=None: None  # type: ignore[attr-defined]
    sys.modules["hermes_constants"] = mod


_install_fake_hermes_constants()


def load_package(name: str = "hermes_iris"):
    """Load the plugin directory as a package, the way Hermes's plugin loader does."""
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, ROOT / "__init__.py", submodule_search_locations=[str(ROOT)])
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def load_plugin_api():
    """Load ``dashboard/plugin_api.py`` the way ``_mount_plugin_api_routes`` does: from its file, outside any package."""
    name = "hermes_dashboard_plugin_iris"
    sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location(name, ROOT / "dashboard" / "plugin_api.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def hermes_home(tmp_path, monkeypatch) -> Path:
    home = tmp_path / "hermes"
    home.mkdir()
    monkeypatch.setenv("HERMES_HOME", str(home))
    return home


@pytest.fixture
def plugin(hermes_home):
    return load_package()


@pytest.fixture
def client(hermes_home):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    api = load_plugin_api()
    app = FastAPI()
    app.include_router(api.router, prefix="/api/plugins/iris")
    return TestClient(app)
