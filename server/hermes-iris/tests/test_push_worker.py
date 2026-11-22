from __future__ import annotations

import logging

import pytest

SID = "20261113_051659_b9bbb3"
IOS = "a" * 32
IOS_TEXT = "b" * 32
ANDROID = "c" * 32
TOK = "ab" * 32
TOK_TEXT = "cd" * 32
T0 = 1_800_000_000.0


class Sender:
    """Stands in for ``apns.send``: records each call and answers from a script (default ``ok``)."""

    def __init__(self, answers=None) -> None:
        self.calls: list[tuple[str, dict]] = []
        self.answers = list(answers or [])

    def __call__(self, cfg, token, notice):
        self.calls.append((token, notice))
        return self.answers.pop(0) if self.answers else "ok"


@pytest.fixture
def env(plugin, hermes_home, apns_key):
    from hermes_iris.genui.store import Store
    from hermes_iris.push import outbox, worker
    from hermes_iris.push.devices import Devices

    root = hermes_home / "iris"
    push_dir = Store(root).profile("default").push_dir
    devices = Devices(push_dir)
    devices.register(IOS, "ios", TOK, "1", {"reply": {"text": "Look!", "mode": "content"}})
    devices.register(IOS_TEXT, "ios", TOK_TEXT, "1", {"reply": {"text": "Psst", "mode": "text"}})
    devices.register(ANDROID, "android", None, "1", None)
    sleeps: list[float] = []

    def run(send, now=T0):
        return worker.run_once(root, now, send, sleep=sleeps.append)

    return type("Env", (), {"root": root, "dir": push_dir, "devices": devices, "outbox": outbox, "run": run,
                            "sleeps": sleeps, "worker": worker})


def reply(**kw) -> dict:
    return {"kind": "reply", "session_id": SID, "title": None, "outcome": "completed", "preview": "SECRET preview", **kw}


def test_sends_to_each_ios_device_as_its_settings_say(env):
    eid = env.outbox.append(env.dir, reply(), now=T0 - 5)
    send = Sender()
    assert env.run(send) == 2
    by_token = dict(send.calls)
    assert set(by_token) == {TOK, TOK_TEXT}  # never the Android device
    assert by_token[TOK] == {"event_id": eid, "kind": "reply", "session_id": SID, "title": "Look!",
                             "body": "SECRET preview", "category": None, "collapse": f"reply-{SID}"}
    assert by_token[TOK_TEXT]["title"] == "Psst" and by_token[TOK_TEXT]["body"] is None
    assert "SECRET" not in repr(by_token[TOK_TEXT])


def test_cursor_survives_restart(env):
    env.outbox.append(env.dir, reply(), now=T0 - 5)
    assert env.run(Sender()) == 2
    assert (env.dir / "apns.cursor").is_file()
    again = Sender()
    assert env.run(again, now=T0 + 1) == 0 and again.calls == []  # no resend, even from a fresh process
    env.outbox.append(env.dir, reply(), now=T0 + 2)
    later = Sender()
    assert env.run(later, now=T0 + 3) == 2


def test_old_events_skipped(env):
    env.outbox.append(env.dir, reply(preview="old"), now=T0 - 601)
    env.outbox.append(env.dir, reply(preview="new"), now=T0 - 599)
    send = Sender()
    env.run(send)
    assert {n["body"] for _, n in send.calls} == {"new", None}


def test_switched_off_kind_is_not_sent(env):
    env.devices.update_settings(IOS, {"job": {"on": False}})
    env.outbox.append(env.dir, {"kind": "job", "session_id": "cron_j_20261113_060000", "job_id": "j",
                                "job_name": "J", "outcome": "completed"}, now=T0 - 1)
    send = Sender()
    env.run(send)
    assert [t for t, _ in send.calls] == [TOK_TEXT]


def test_approval_done_is_not_sent(env):
    env.outbox.append(env.dir, {"kind": "approval_done", "session_id": SID}, now=T0 - 1)
    send = Sender()
    assert env.run(send) == 0 and send.calls == []
    assert (env.dir / "apns.cursor").is_file()  # still consumed


def test_retry_once_then_move_on(env):
    env.devices.remove(IOS_TEXT)
    env.outbox.append(env.dir, reply(), now=T0 - 2)
    env.outbox.append(env.dir, reply(), now=T0 - 1)
    send = Sender(["retry", "retry", "retry", "ok"])
    assert env.run(send) == 1
    assert len(send.calls) == 4  # each event tried twice at most
    assert env.sleeps == [5.0, 5.0]


def test_dead_token_drops_the_device(env):
    env.outbox.append(env.dir, reply(), now=T0 - 1)
    env.run(Sender(["drop_device", "ok"]))  # devices are visited in id order: IOS first
    assert env.devices.get(IOS) is None
    assert env.devices.get(IOS_TEXT) is not None


def test_no_config_sends_nothing(env):
    (env.root / "push" / "apns.json").unlink()
    env.outbox.append(env.dir, reply(), now=T0 - 1)
    send = Sender()
    assert env.run(send) == 0 and send.calls == []


def test_every_profile_is_served(env):
    from hermes_iris.genui.store import Store
    from hermes_iris.push.devices import Devices

    other = Store(env.root).profile("work").push_dir
    Devices(other).register("d" * 32, "ios", "ef" * 32, "1", None)
    env.outbox.append(other, reply(), now=T0 - 1)
    send = Sender()
    assert env.run(send) == 1
    assert send.calls[0][0] == "ef" * 32


def test_a_bad_profile_does_not_stop_the_rest(env, monkeypatch):
    from hermes_iris.genui.store import Store
    from hermes_iris.push.devices import Devices

    other = Store(env.root).profile("work").push_dir
    Devices(other).register("d" * 32, "ios", "ef" * 32, "1", None)
    env.outbox.append(other, reply(), now=T0 - 1)
    env.outbox.append(env.dir, reply(), now=T0 - 1)

    def boom(cfg, token, notice):
        if token == TOK:
            raise RuntimeError(f"token {token}")
        return "ok"

    assert env.run(boom) == 2  # TOK_TEXT in default, and the work device


def test_errors_are_logged_without_content(env, caplog):
    caplog.set_level(logging.DEBUG)
    env.outbox.append(env.dir, reply(), now=T0 - 1)

    def boom(cfg, token, notice):
        raise RuntimeError(f"{token} {notice}")

    env.run(boom)
    assert caplog.records
    assert TOK not in caplog.text and "SECRET" not in caplog.text


def test_start_is_idempotent(env, monkeypatch):
    started = []
    monkeypatch.setattr(env.worker, "_thread", None)
    monkeypatch.setattr(env.worker, "_loop", lambda root: started.append(root))
    first = env.worker.start(env.root)
    assert env.worker.start(env.root) is first
    first.join(1)
    assert started == [env.root] and first.daemon


def test_status_reports_apns(client, env, monkeypatch):
    from hermes_iris.push import apns

    monkeypatch.setattr(apns.shutil, "which", lambda name: "/usr/bin/curl")
    assert client.get("/api/plugins/iris/push/status").json()["apns_configured"] is True
    monkeypatch.setattr(apns.shutil, "which", lambda name: None)
    assert client.get("/api/plugins/iris/push/status").json()["apns_configured"] is False


def test_push_test_route_sends_to_one_device(client, env, monkeypatch):
    from hermes_iris.push import apns

    sent = []
    monkeypatch.setattr(apns, "send", lambda cfg, token, notice: sent.append((token, notice)) or "ok")
    r = client.post(f"/api/plugins/iris/push/test/{IOS}")
    assert r.status_code == 200 and r.json() == {"ok": True, "result": "ok"}
    assert sent[0][0] == TOK and sent[0][1]["title"] == "Look!" and sent[0][1]["kind"] == "test"
    assert client.post(f"/api/plugins/iris/push/test/{'e' * 32}").status_code == 404
    assert client.post(f"/api/plugins/iris/push/test/{ANDROID}").status_code == 404
