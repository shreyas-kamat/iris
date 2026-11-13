from __future__ import annotations

import pytest

SID = "20261113_051659_b9bbb3"
HOUR = 3600.0


@pytest.fixture
def push_dir(plugin, hermes_home):
    from hermes_iris.genui.store import Store

    return Store(hermes_home / "iris").profile("default").push_dir


def test_mark_then_take_once(push_dir):
    from hermes_iris.push import active

    assert active.is_active(push_dir, SID, now=1000.0) is False
    active.mark(push_dir, SID, now=1000.0)
    assert active.is_active(push_dir, SID, now=1001.0) is True
    assert active.take(push_dir, SID, now=1002.0) is True
    assert active.take(push_dir, SID, now=1003.0) is False
    assert active.is_active(push_dir, SID, now=1004.0) is False


def test_expires_after_6h(push_dir):
    from hermes_iris.push import active

    active.mark(push_dir, SID, now=0.0)
    assert active.is_active(push_dir, SID, now=6 * HOUR - 1) is True
    assert active.is_active(push_dir, SID, now=6 * HOUR + 1) is False
    assert active.take(push_dir, SID, now=6 * HOUR + 1) is False


def test_marking_again_refreshes(push_dir):
    from hermes_iris.push import active

    active.mark(push_dir, SID, now=0.0)
    active.mark(push_dir, SID, now=5 * HOUR)
    assert active.is_active(push_dir, SID, now=10 * HOUR) is True


def test_cap_200(push_dir):
    from hermes_iris.push import active

    for i in range(205):
        active.mark(push_dir, f"s{i}", now=float(i))
    assert active.is_active(push_dir, "s0", now=300.0) is False  # the oldest were dropped
    assert active.is_active(push_dir, "s4", now=300.0) is False
    assert active.is_active(push_dir, "s5", now=300.0) is True
    assert active.is_active(push_dir, "s204", now=300.0) is True


def test_unsafe_session_id_refused(push_dir):
    from hermes_iris.genui.store import InvalidName
    from hermes_iris.push import active

    with pytest.raises(InvalidName):
        active.mark(push_dir, "../x")


def test_route_marks_active(client, push_dir):
    from hermes_iris.push import active

    r = client.post(f"/api/plugins/iris/push/active/{SID}")
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert active.is_active(push_dir, SID) is True
    assert client.post("/api/plugins/iris/push/active/bad.id").status_code == 400
    # a different profile has its own marks
    assert active.is_active(push_dir.parent.parent / "work" / "push", SID) is False
