from __future__ import annotations

import asyncio
import json

import pytest

SID = "20261113_051659_b9bbb3"
DEVICE = "a" * 32
IOS_DEVICE = "b" * 32
T0 = 1_000_000.0
URL = "/api/plugins/iris/push/stream"


@pytest.fixture
def env(plugin, hermes_home):
    from hermes_iris.genui.store import Store
    from hermes_iris.push import outbox, stream
    from hermes_iris.push.devices import Devices

    push_dir = Store(hermes_home / "iris").profile("default").push_dir
    devices = Devices(push_dir)
    devices.register(DEVICE, "android", None, "1", {"reply": {"text": "Look!", "mode": "content"}})
    devices.register(IOS_DEVICE, "ios", "ab" * 32, "1", None)
    return type("Env", (), {"dir": push_dir, "devices": devices, "outbox": outbox, "stream": stream})


class Clock:
    """A fake clock: ``sleep`` advances it, runs an optional script, and stops the stream after ``polls`` sleeps."""

    def __init__(self, polls: int, script=None) -> None:
        self.t = T0
        self.polls = polls
        self.count = 0
        self.script = script

    def now(self) -> float:
        return self.t

    async def sleep(self, seconds: float) -> None:
        self.count += 1
        self.t += seconds
        if self.script:
            self.script(self.count)
        if self.count >= self.polls:
            raise asyncio.CancelledError


def run(env, clock, *, device=DEVICE, after=None, **kw) -> list[str]:
    async def go() -> list[str]:
        out: list[str] = []
        try:
            async for frame in env.stream.frames(env.dir, device, after, now=clock.now, sleep=clock.sleep, **kw):
                out.append(frame)
        except asyncio.CancelledError:
            pass
        return out

    return asyncio.run(go())


def notices(frames: list[str]) -> list[dict]:
    out = []
    for f in frames:
        if f.startswith(":"):
            continue
        lines = f.strip("\n").split("\n")
        assert lines[0].startswith("id: ") and lines[1] == "event: notice" and lines[2].startswith("data: ")
        assert f.endswith("\n\n")
        payload = json.loads(lines[2][len("data: "):])
        assert payload["event_id"] == lines[0][len("id: "):]
        out.append(payload)
    return out


def reply(i: int, **kw) -> dict:
    return {"kind": "reply", "session_id": SID, "title": f"t{i}", "outcome": "completed", "preview": f"p{i}", **kw}


def test_replays_after_cursor(env):
    a = env.outbox.append(env.dir, reply(1), now=T0 - 30)
    b = env.outbox.append(env.dir, reply(2), now=T0 - 20)
    c = env.outbox.append(env.dir, reply(3), now=T0 - 10)
    got = notices(run(env, Clock(1), after=a))
    assert [n["event_id"] for n in got] == [b, c]
    assert got[0] == {"event_id": b, "kind": "reply", "session_id": SID, "title": "Look!", "body": "p2",
                      "category": None, "collapse": f"reply-{SID}"}


def test_skips_events_older_than_15_min(env):
    env.outbox.append(env.dir, reply(1), now=T0 - 901)
    fresh = env.outbox.append(env.dir, reply(2), now=T0 - 899)
    got = notices(run(env, Clock(1), after="1"))
    assert [n["event_id"] for n in got] == [fresh]


def test_a_fresh_connection_does_not_replay_old_events(env):
    env.outbox.append(env.dir, reply(1), now=T0 - 5)
    got = notices(run(env, Clock(2)))
    assert got == []


def test_a_fresh_connection_gets_new_events(env):
    ids: list[str] = []

    def script(count: int) -> None:
        if count == 1:
            ids.append(env.outbox.append(env.dir, reply(9), now=T0 + 1))

    got = notices(run(env, Clock(3, script)))
    assert [n["event_id"] for n in got] == ids


def test_events_arriving_while_open_are_sent_once(env):
    ids: list[str] = []

    def script(count: int) -> None:
        if count in (2, 4):
            ids.append(env.outbox.append(env.dir, reply(count), now=T0 + count))

    got = notices(run(env, Clock(8, script), after="1"))
    assert [n["event_id"] for n in got] == ids and len(ids) == 2


def test_renders_per_device_settings(env):
    env.devices.update_settings(DEVICE, {"approval": {"mode": "text", "text": "Hey"}, "job": {"on": False}})
    env.outbox.append(env.dir, reply(1), now=T0 - 5)
    env.outbox.append(env.dir, {"kind": "approval", "session_id": SID, "title": None, "command": "SECRETCMD",
                                "description": "SECRETDESC"}, now=T0 - 4)
    env.outbox.append(env.dir, {"kind": "job", "session_id": "cron_j_20261113_060000", "job_id": "j",
                                "job_name": "J", "outcome": "completed"}, now=T0 - 3)
    env.outbox.append(env.dir, {"kind": "approval_done", "session_id": SID}, now=T0 - 2)
    frames = run(env, Clock(1), after="1")
    got = notices(frames)
    assert [n["kind"] for n in got] == ["reply", "approval", "approval_done"]  # the job is switched off
    assert got[1]["title"] == "Hey" and got[1]["body"] is None and got[1]["category"] == "approval"
    assert "SECRET" not in "".join(frames)
    assert got[2] == {"event_id": got[2]["event_id"], "kind": "approval_done", "session_id": SID,
                      "collapse": f"approval-{SID}"}


def test_settings_changes_apply_to_a_running_stream(env):
    def script(count: int) -> None:
        if count == 1:
            env.devices.update_settings(DEVICE, {"reply": {"on": False}})
            env.outbox.append(env.dir, reply(1), now=T0 + 1)

    assert notices(run(env, Clock(3, script), after="1")) == []


def test_ping_when_idle(env):
    frames = run(env, Clock(60))
    assert frames.count(": ping\n\n") == 2  # at 25 s and 50 s of a 60 s idle stream
    assert notices(frames) == []


def test_no_ping_right_after_a_notice(env):
    env.outbox.append(env.dir, reply(1), now=T0 - 1)
    frames = run(env, Clock(20), after="1")
    assert len(notices(frames)) == 1 and ": ping\n\n" not in frames


def test_a_removed_device_ends_the_stream(env):
    def script(count: int) -> None:
        if count == 2:
            env.devices.remove(DEVICE)

    clock = Clock(50, script)
    assert run(env, clock) == []
    assert clock.count == 2  # it stopped on its own, not because the clock ran out


def test_unknown_device_404(client, env):
    assert client.get(URL, params={"device_id": "c" * 32}).status_code == 404


def test_ios_device_404(client, env):
    assert client.get(URL, params={"device_id": IOS_DEVICE}).status_code == 404


def test_bad_device_id_400(client, env):
    assert client.get(URL, params={"device_id": "../x"}).status_code == 400


def test_the_route_answers_as_an_event_stream(plugin, hermes_home, env):
    from conftest import load_plugin_api

    api = load_plugin_api()
    response = asyncio.run(api.push_stream(device_id=DEVICE, after=None, profile=None))
    assert response.media_type == "text/event-stream"
    assert response.headers["cache-control"] == "no-cache"
    assert response.headers["x-accel-buffering"] == "no"
