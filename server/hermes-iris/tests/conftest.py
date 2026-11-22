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

# Importing dashboard/plugin_api.py would start the real APNs worker thread.
os.environ["HERMES_IRIS_PUSH_WORKER"] = "0"


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


APNS_TEAM = "TEAM123456"
APNS_KEY_ID = "KEY1234567"


@pytest.fixture
def apns_key(hermes_home):
    """A fresh P-256 key written the way Apple hands it out (a PKCS#8 ``.p8``), plus ``apns.json`` beside it.
    Returns the private key so a test can verify signatures with its public half."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    key = ec.generate_private_key(ec.SECP256R1())
    push = hermes_home / "iris" / "push"
    push.mkdir(parents=True)
    p8 = push / f"AuthKey_{APNS_KEY_ID}.p8"
    p8.write_bytes(
        key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    )
    os.chmod(p8, 0o600)
    (push / "apns.json").write_text(
        '{"team_id": "%s", "key_id": "%s", "bundle_id": "com.iflotech.iris", "key_path": "%s",'
        ' "environment": "sandbox"}' % (APNS_TEAM, APNS_KEY_ID, p8.name),
        "utf-8",
    )
    return key


@pytest.fixture
def client(hermes_home):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    api = load_plugin_api()
    app = FastAPI()
    app.include_router(api.router, prefix="/api/plugins/iris")
    return TestClient(app)
