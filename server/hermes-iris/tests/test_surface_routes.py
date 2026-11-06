from __future__ import annotations

import pytest

SID = "20261106_193512_ab12cd"
BASE = "/api/plugins/iris/surfaces"
GOOD = 'root = Stack([a])\na = Text("Hello", "title")\n'


@pytest.fixture
def store(plugin, hermes_home):
    from hermes_iris.genui import paths
    from hermes_iris.genui.store import Store

    return Store(paths.iris_root()).profile("default")


@pytest.fixture
def seeded(plugin, store):
    from hermes_iris.genui import catalog, surfaces

    lib = catalog.v1()
    assert surfaces.submit(store, lib, SID, {"surface_id": "a", "code": GOOD, "fallback": "Hello"})["ok"]
    assert surfaces.submit(store, lib, SID, {"surface_id": "a", "code": GOOD, "fallback": "Hello 2"})["rev"] == 2
    assert surfaces.submit(store, lib, SID, {"surface_id": "kit", "code": GOOD, "fallback": "k", "placement": "reply_kit"})["ok"]


def test_list_a_sessions_surfaces(client, seeded):
    r = client.get(f"{BASE}/{SID}")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True and body["session"] == SID
    by_id = {s["surface_id"]: s for s in body["surfaces"]}
    assert set(by_id) == {"a", "kit"}
    assert by_id["a"]["rev"] == 2 and by_id["a"]["placement"] == "inline"
    assert by_id["kit"]["placement"] == "reply_kit"
    assert "code" not in by_id["a"], "the list is a summary; the program comes from the single-surface route"


def test_an_unknown_session_has_no_surfaces(client):
    assert client.get(f"{BASE}/{SID}").json()["surfaces"] == []


def test_get_one_surface(client, seeded):
    r = client.get(f"{BASE}/{SID}/a")
    assert r.status_code == 200
    s = r.json()["surface"]
    assert s["code"] == GOOD and s["fallback"] == "Hello 2" and s["rev"] == 2
    assert s["surface_id"] == "a" and s["session"] == SID and s["template"] is None


def test_a_missing_surface_is_a_404(client, seeded):
    r = client.get(f"{BASE}/{SID}/nope")
    assert r.status_code == 404


@pytest.mark.parametrize("path", ["bad.id/a", f"{SID}/bad.id", "x" * 65 + "/a"])
def test_unsafe_ids_are_a_400(client, path):
    assert client.get(f"{BASE}/{path}").status_code == 400


def test_the_profile_query_scopes_the_surfaces(client, seeded):
    assert client.get(f"{BASE}/{SID}", params={"profile": "work"}).json()["surfaces"] == []
    assert client.get(f"{BASE}/{SID}/a", params={"profile": "work"}).status_code == 404


def test_an_unsafe_profile_is_a_400(client):
    assert client.get(f"{BASE}/{SID}", params={"profile": "../x"}).status_code == 400


def test_capabilities_lists_surfaces(client):
    assert "surfaces" in client.get("/api/plugins/iris/capabilities").json()["features"]
