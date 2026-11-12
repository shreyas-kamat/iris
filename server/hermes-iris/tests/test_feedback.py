"""Signals from the app (used, expanded, dismissed, not useful): validated, bounded, and logged without content."""

from __future__ import annotations

import pytest

BASE = "/api/plugins/iris"


def signal(**kw):
    return {"signal": "used", "surface": "s1", "template": "deploy", "session": "20261107_a", **kw}


def test_capabilities_list_feedback(client):
    assert "feedback" in client.get(f"{BASE}/capabilities").json()["features"]


def test_signals_are_logged_to_the_usage_file(client, hermes_home):
    r = client.post(f"{BASE}/feedback", json={"signals": [signal(), signal(signal="expanded", template=None)]})
    assert r.status_code == 200
    assert r.json() == {"ok": True, "accepted": 2}

    from hermes_iris.genui.store import Store

    rows = Store(hermes_home / "iris").profile("default").read_usage()
    assert [row["signal"] for row in rows] == ["used", "expanded"]
    assert all(row["kind"] == "signal" and isinstance(row["ts"], (int, float)) for row in rows)
    assert rows[0]["template"] == "deploy" and rows[0]["surface"] == "s1" and rows[0]["session"] == "20261107_a"
    assert "template" not in rows[1]


def test_an_unknown_signal_is_refused_and_nothing_is_logged(client, hermes_home):
    r = client.post(f"{BASE}/feedback", json={"signals": [signal(), signal(signal="loved")]})
    assert r.status_code == 422
    body = r.json()
    assert body["ok"] is False and "signal" in body["errors"][0]

    from hermes_iris.genui.store import Store

    assert Store(hermes_home / "iris").profile("default").read_usage() == []


@pytest.mark.parametrize("field", ["surface", "template", "session"])
def test_an_unsafe_id_is_refused(client, field):
    r = client.post(f"{BASE}/feedback", json={"signals": [signal(**{field: "../x"})]})
    assert r.status_code == 422


def test_a_batch_is_capped(client):
    r = client.post(f"{BASE}/feedback", json={"signals": [signal()] * 101})
    assert r.status_code == 422
    assert "100" in r.json()["errors"][0]


def test_a_bad_body_is_a_422(client):
    assert client.post(f"{BASE}/feedback", json={"nope": 1}).status_code == 422
    assert client.post(f"{BASE}/feedback", content=b"not json").status_code == 422


def test_an_empty_batch_is_fine(client):
    assert client.post(f"{BASE}/feedback", json={"signals": []}).json() == {"ok": True, "accepted": 0}


def test_extra_fields_are_not_stored(client, hermes_home):
    client.post(f"{BASE}/feedback", json={"signals": [signal(text="my private words", data={"a": 1})]})

    from hermes_iris.genui.store import Store

    row = Store(hermes_home / "iris").profile("default").read_usage()[0]
    assert set(row) <= {"kind", "ts", "signal", "surface", "template", "session"}
