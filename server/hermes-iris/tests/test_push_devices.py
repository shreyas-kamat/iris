from __future__ import annotations

import pytest

URL = "/api/plugins/iris/push"
DEVICE = "a" * 32
TOKEN = "ab" * 32


@pytest.fixture
def push_dir(plugin, hermes_home):
    from hermes_iris.genui.store import Store

    return Store(hermes_home / "iris").profile("default").push_dir


@pytest.fixture
def devices(push_dir):
    from hermes_iris.push.devices import Devices

    return Devices(push_dir)


def test_defaults_fill_missing_events(plugin):
    from hermes_iris.push.devices import DEFAULT_SETTINGS, normalize_settings

    assert normalize_settings(None) == DEFAULT_SETTINGS
    assert normalize_settings("junk") == DEFAULT_SETTINGS
    assert DEFAULT_SETTINGS == {
        "reply": {"on": True, "text": "Attention!", "mode": "text"},
        "approval": {"on": True, "text": "Attention!", "mode": "content"},
        "job": {"on": True, "text": "Attention!", "mode": "content"},
    }
    got = normalize_settings({"reply": {"on": False}, "bogus": {"on": True}})
    assert got["reply"] == {"on": False, "text": "Attention!", "mode": "text"}
    assert got["approval"] == DEFAULT_SETTINGS["approval"]
    assert "bogus" not in got


def test_text_is_trimmed_and_kept_verbatim(plugin):
    from hermes_iris.push.devices import normalize_settings

    raw = '  "Hi" 👋 ' + "x" * 120
    text = normalize_settings({"reply": {"text": raw}})["reply"]["text"]
    assert len(text) == 100
    assert text.startswith('"Hi" 👋')
    assert normalize_settings({"reply": {"text": "   "}})["reply"]["text"] == "Attention!"
    assert normalize_settings({"reply": {"text": 5}})["reply"]["text"] == "Attention!"


def test_bad_mode_and_flag_fall_back(plugin):
    from hermes_iris.push.devices import normalize_settings

    got = normalize_settings({"approval": {"mode": "loud", "on": "yes"}})
    assert got["approval"] == {"on": True, "text": "Attention!", "mode": "content"}


def test_register_and_read_back(devices):
    rec = devices.register(DEVICE, "ios", TOKEN, "1.0.0", {"job": {"text": "Done"}})
    assert rec["device_id"] == DEVICE and rec["platform"] == "ios" and rec["apns_token"] == TOKEN
    assert rec["settings"]["job"]["text"] == "Done"
    assert devices.get(DEVICE) == rec
    assert [d["device_id"] for d in devices.all()] == [DEVICE]
    again = devices.register(DEVICE, "ios", TOKEN, "1.0.1", None)
    assert again["app_version"] == "1.0.1"
    assert len(devices.all()) == 1


def test_android_has_no_token(devices):
    rec = devices.register(DEVICE, "android", None, "1.0.0", None)
    assert rec["apns_token"] is None


def test_update_settings(devices):
    devices.register(DEVICE, "android", None, "1.0.0", None)
    rec = devices.update_settings(DEVICE, {"reply": {"on": False}})
    assert rec["settings"]["reply"]["on"] is False
    assert devices.get(DEVICE)["settings"]["reply"]["on"] is False
    assert devices.update_settings("b" * 32, {}) is None


def test_bad_device_id_refused(devices, client):
    from hermes_iris.genui.store import InvalidName

    with pytest.raises(InvalidName):
        devices.register("../x", "android", None, "1", None)
    r = client.put(f"{URL}/devices/..%2Fx", json={"platform": "android", "app_version": "1"})
    assert r.status_code in (400, 404)
    r = client.put(f"{URL}/devices/bad.id", json={"platform": "android", "app_version": "1"})
    assert r.status_code == 400


def test_bad_apns_token_refused(devices, client):
    from hermes_iris.push.devices import InvalidDevice

    for bad in ("zz" * 32, "ab" * 10, "ab" * 101, 5):
        with pytest.raises(InvalidDevice):
            devices.register(DEVICE, "ios", bad, "1", None)
    with pytest.raises(InvalidDevice):
        devices.register(DEVICE, "windows", None, "1", None)
    r = client.put(f"{URL}/devices/{DEVICE}", json={"platform": "ios", "apns_token": "nope", "app_version": "1"})
    assert r.status_code == 400
    r = client.put(f"{URL}/devices/{DEVICE}", json={"platform": "plan9", "app_version": "1"})
    assert r.status_code == 400


def test_remove(devices):
    devices.register(DEVICE, "android", None, "1", None)
    assert devices.remove(DEVICE) is True
    assert devices.remove(DEVICE) is False
    assert devices.get(DEVICE) is None


def test_routes_round_trip(client, devices):
    r = client.put(
        f"{URL}/devices/{DEVICE}",
        json={"platform": "ios", "apns_token": TOKEN, "app_version": "1.0.0", "settings": {"reply": {"text": "Yo"}}},
    )
    assert r.status_code == 200 and r.json()["ok"] is True
    assert devices.get(DEVICE)["settings"]["reply"]["text"] == "Yo"
    r = client.patch(f"{URL}/devices/{DEVICE}/settings", json={"job": {"on": False}})
    assert r.status_code == 200
    assert devices.get(DEVICE)["settings"]["job"]["on"] is False
    assert devices.get(DEVICE)["settings"]["reply"]["text"] == "Yo"  # merged, not replaced
    assert client.patch(f"{URL}/devices/{'c' * 32}/settings", json={}).status_code == 404
    r = client.delete(f"{URL}/devices/{DEVICE}")
    assert r.json() == {"ok": True, "deleted": True}
    assert client.delete(f"{URL}/devices/{DEVICE}").json()["deleted"] is False


def test_status_has_no_tokens(client, devices):
    devices.register(DEVICE, "ios", TOKEN, "1", None)
    r = client.get(f"{URL}/status")
    body = r.json()
    assert body == {"ok": True, "apns_configured": False, "devices": 1}
    assert TOKEN not in r.text and DEVICE not in r.text
    r = client.put(f"{URL}/devices/{DEVICE}", json={"platform": "ios", "apns_token": TOKEN, "app_version": "1"})
    assert TOKEN not in r.text


def test_capabilities_list_push(client):
    assert "push" in client.get("/api/plugins/iris/capabilities").json()["features"]


def test_profiles_are_separate(client):
    client.put(f"{URL}/devices/{DEVICE}?profile=work", json={"platform": "android", "app_version": "1"})
    assert client.get(f"{URL}/status?profile=work").json()["devices"] == 1
    assert client.get(f"{URL}/status").json()["devices"] == 0
