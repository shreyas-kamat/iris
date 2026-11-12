from __future__ import annotations

import json

import pytest

SID = "20261106_193512_ab12cd"
URL = f"/api/plugins/iris/sessions/{SID}/genui"


@pytest.fixture
def store(plugin, hermes_home):
    from hermes_iris.genui.store import Store

    return Store(hermes_home / "iris")


def test_flag_and_unflag(store):
    p = store.profile("default")
    assert p.is_flagged(SID) is False
    p.flag_session(SID)
    assert p.is_flagged(SID) is True
    assert p.flag_session(SID) is None  # idempotent
    assert p.unflag_session(SID) is True
    assert p.unflag_session(SID) is False
    assert p.is_flagged(SID) is False


def test_flags_survive_a_restart(store, hermes_home):
    from hermes_iris.genui.store import Store

    store.profile("default").flag_session(SID)
    assert Store(hermes_home / "iris").profile("default").is_flagged(SID)


def test_flags_are_per_profile(store):
    store.profile("work").flag_session(SID)
    assert store.profile("work").is_flagged(SID)
    assert not store.profile("default").is_flagged(SID)


def test_flags_are_pruned_to_the_newest(plugin, hermes_home, monkeypatch):
    from hermes_iris.genui import store as store_mod

    assert store_mod.FLAG_LIMIT == 500
    monkeypatch.setattr(store_mod, "FLAG_LIMIT", 25)
    store = store_mod.Store(hermes_home / "iris")
    p = store.profile("default")
    for i in range(store_mod.FLAG_LIMIT + 20):
        p.flag_session(f"s{i}")
    flagged = p.flagged_sessions()
    assert len(flagged) == store_mod.FLAG_LIMIT
    assert p.is_flagged(f"s{store_mod.FLAG_LIMIT + 19}")
    assert not p.is_flagged("s0")


def test_a_damaged_flag_file_reads_as_no_flags(store, hermes_home):
    p = store.profile("default")
    p.flag_session(SID)
    (hermes_home / "iris" / "default" / "flags.json").write_text("{nope", "utf-8")
    assert p.is_flagged(SID) is False
    p.flag_session("other")  # and writing again recovers
    assert p.is_flagged("other")


def test_route_flags_a_session(client, hermes_home):
    r = client.post(URL)
    assert r.status_code == 200
    assert r.json() == {"ok": True, "session": SID, "flagged": True}
    assert client.get(URL).json()["flagged"] is True
    on_disk = json.loads((hermes_home / "iris" / "default" / "flags.json").read_text("utf-8"))
    assert SID in on_disk


def test_route_unflags(client):
    client.post(URL)
    assert client.delete(URL).json() == {"ok": True, "session": SID, "flagged": False}
    assert client.get(URL).json()["flagged"] is False


def test_route_respects_the_profile_query(client):
    client.post(URL, params={"profile": "work"})
    assert client.get(URL, params={"profile": "work"}).json()["flagged"] is True
    assert client.get(URL).json()["flagged"] is False


@pytest.mark.parametrize("session", ["bad.id", "a b", "x" * 65, "%00"])
def test_route_refuses_unsafe_session_ids(client, session):
    r = client.post(f"/api/plugins/iris/sessions/{session}/genui")
    assert r.status_code == 400


@pytest.mark.parametrize("profile", ["../x", "a/b", "", "a b", "x" * 65])
def test_route_refuses_unsafe_profiles(client, profile):
    assert client.post(URL, params={"profile": profile}).status_code == 400


def test_the_hook_side_sees_what_the_route_wrote(client, plugin):
    from hermes_iris.genui import flags

    assert flags.is_flagged(SID) is False
    client.post(URL)
    assert flags.is_flagged(SID) is True
    assert flags.is_flagged(SID, profile="work") is False


def test_the_hook_side_never_raises(plugin, monkeypatch):
    from hermes_iris.genui import flags

    assert flags.is_flagged("not a valid id!") is False
    assert flags.is_flagged(None) is False  # type: ignore[arg-type]
    monkeypatch.delenv("HERMES_HOME")
    assert flags.is_flagged(SID) is False


def test_capabilities_lists_the_feature(client):
    assert "session-flag" in client.get("/api/plugins/iris/capabilities").json()["features"]
