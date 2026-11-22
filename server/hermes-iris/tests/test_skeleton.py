import json

import yaml

from conftest import ROOT


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
    assert meta["version"] == manifest["version"] == plugin.__version__
    assert manifest["api"] == "plugin_api.py"
    assert (ROOT / "dashboard" / manifest["entry"]).is_file()


def test_no_pyproject_in_the_plugin_directory():
    # Hermes treats any pyproject.toml as "declares Python dependencies" and refuses a forced, non-interactive
    # reinstall (what the app's Update does). The plugin has no runtime dependencies, so it must not ship one.
    assert not (ROOT / "pyproject.toml").exists()
    assert not (ROOT / "requirements.txt").exists()


def test_register_runs_against_a_bare_context(plugin):
    class Ctx:
        def __getattr__(self, name):  # tolerate whatever registration calls exist
            return lambda *a, **k: None

    plugin.register(Ctx())
