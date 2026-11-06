import json
import re

import yaml

from conftest import ROOT


def _pyproject_version() -> str:
    m = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "pyproject.toml").read_text("utf-8"), re.M)
    assert m
    return m.group(1)


def test_capabilities(client, plugin):
    r = client.get("/api/plugins/iris/capabilities")
    assert r.status_code == 200
    body = r.json()
    assert body["version"] == plugin.__version__
    assert body["openui"] == "1.0"
    assert isinstance(body["library_ids"], list)
    assert "capabilities" in body["features"]


def test_capabilities_takes_a_profile(client):
    assert client.get("/api/plugins/iris/capabilities", params={"profile": "work"}).status_code == 200


def test_versions_agree(plugin):
    manifest = json.loads((ROOT / "dashboard" / "manifest.json").read_text("utf-8"))
    meta = yaml.safe_load((ROOT / "plugin.yaml").read_text("utf-8"))
    assert meta["name"] == "iris" == manifest["name"]
    assert meta["version"] == manifest["version"] == plugin.__version__ == _pyproject_version()
    assert manifest["api"] == "plugin_api.py"
    assert (ROOT / "dashboard" / manifest["entry"]).is_file()


def test_register_runs_against_a_bare_context(plugin):
    class Ctx:
        def __getattr__(self, name):  # tolerate whatever registration calls exist
            return lambda *a, **k: None

    plugin.register(Ctx())
