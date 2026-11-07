from __future__ import annotations

import pytest

from test_personal import PROGRAM, SAMPLE, SCHEMA, proposal

BASE = "/api/plugins/iris"


@pytest.fixture
def seeded(plugin, hermes_home):
    from hermes_iris.genui import catalog, personal
    from hermes_iris.genui.store import Store

    p = Store(hermes_home / "iris").profile("default")
    personal.propose_profile(p, {"summary": "Engineer", "chips": ["APIs"]})
    personal.propose_template(p, catalog.v1(), proposal())
    return p


def test_capabilities_list_the_new_features(client):
    features = client.get(f"{BASE}/capabilities").json()["features"]
    assert "profile" in features and "templates" in features


def test_get_profile_when_there_is_none(client):
    assert client.get(f"{BASE}/profile").json() == {"ok": True, "profile": None}


def test_get_and_put_profile(client, seeded):
    got = client.get(f"{BASE}/profile").json()["profile"]
    assert got["summary"] == "Engineer" and got["status"] == "proposed"
    r = client.put(f"{BASE}/profile", json={"summary": "Mine", "chips": ["x", "y"], "status": "approved"})
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True and body["profile"]["summary"] == "Mine" and body["profile"]["status"] == "approved"
    assert client.get(f"{BASE}/profile").json()["profile"]["chips"] == ["x", "y"]


def test_put_profile_with_a_bad_body_is_a_422_with_errors(client, seeded):
    r = client.put(f"{BASE}/profile", json={"chips": "no"})
    assert r.status_code == 422 and r.json()["ok"] is False and r.json()["errors"]
    assert client.put(f"{BASE}/profile", content=b"[1]", headers={"content-type": "application/json"}).status_code == 422


def test_list_templates_returns_full_records(client, seeded):
    body = client.get(f"{BASE}/templates").json()
    assert body["ok"] is True
    (t,) = body["templates"]
    assert t["id"] == "jobs" and t["program"] == PROGRAM and t["sample_data"] == SAMPLE and t["data_schema"] == SCHEMA
    assert t["status"] == "proposed" and t["name"] == "Job list"


def test_list_templates_can_filter_by_status(client, seeded):
    assert client.get(f"{BASE}/templates", params={"status": "approved"}).json()["templates"] == []
    assert len(client.get(f"{BASE}/templates", params={"status": "proposed"}).json()["templates"]) == 1
    assert client.get(f"{BASE}/templates", params={"status": "bogus"}).status_code == 400


def test_get_one_template(client, seeded):
    r = client.get(f"{BASE}/templates/jobs")
    assert r.status_code == 200 and r.json()["template"]["name"] == "Job list"
    assert client.get(f"{BASE}/templates/nope").status_code == 404
    assert client.get(f"{BASE}/templates/bad.id").status_code == 400


def test_approve_rename_and_retire(client, seeded):
    r = client.put(f"{BASE}/templates/jobs", json={"name": "My jobs", "status": "approved"})
    assert r.status_code == 200 and r.json()["template"]["status"] == "approved"
    assert client.get(f"{BASE}/templates/jobs").json()["template"]["name"] == "My jobs"
    r = client.put(f"{BASE}/templates/jobs", json={"status": "retired"})
    assert r.json()["template"]["status"] == "retired"


def test_put_a_template_that_does_not_validate_is_a_422(client, seeded):
    r = client.put(f"{BASE}/templates/jobs", json={"program": 'root = Nope("x")\n'})
    assert r.status_code == 422 and r.json()["ok"] is False and r.json()["errors"]
    assert client.get(f"{BASE}/templates/jobs").json()["template"]["program"] == PROGRAM


def test_put_creates_a_template_given_every_field(client, seeded):
    body = proposal(id="ignored")
    del body["id"]
    r = client.put(f"{BASE}/templates/fresh", json={**body, "status": "approved"})
    assert r.status_code == 200 and r.json()["template"]["id"] == "fresh"
    assert client.put(f"{BASE}/templates/fresh2", json={"name": "x"}).status_code == 422


def test_delete_a_template(client, seeded):
    assert client.delete(f"{BASE}/templates/jobs").json() == {"ok": True, "id": "jobs", "deleted": True}
    assert client.delete(f"{BASE}/templates/jobs").json() == {"ok": True, "id": "jobs", "deleted": False}
    assert client.get(f"{BASE}/templates/jobs").status_code == 404
    assert client.delete(f"{BASE}/templates/bad.id").status_code == 400


def test_every_route_takes_a_profile(client, seeded):
    assert client.get(f"{BASE}/templates", params={"profile": "work"}).json()["templates"] == []
    assert client.get(f"{BASE}/profile", params={"profile": "work"}).json()["profile"] is None
    assert client.get(f"{BASE}/profile", params={"profile": "../x"}).status_code == 400
    assert client.get(f"{BASE}/templates", params={"profile": "bad.name"}).status_code == 400
