from __future__ import annotations

import json
import os
import sys

import pytest

DAY = 86400.0


@pytest.fixture
def push_dir(plugin, hermes_home):
    from hermes_iris.genui.store import Store

    return Store(hermes_home / "iris").profile("default").push_dir


def _event(i: int = 0) -> dict:
    return {"kind": "reply", "session_id": "s1", "title": f"t{i}", "outcome": "completed", "preview": "hi"}


def test_ids_increase(push_dir):
    from hermes_iris.push import outbox

    ids = [outbox.append(push_dir, _event(i)) for i in range(50)]
    assert all(isinstance(i, str) for i in ids)
    assert [int(i) for i in ids] == sorted({int(i) for i in ids})
    assert len(set(ids)) == 50


def test_read_after_and_max_age(push_dir):
    from hermes_iris.push import outbox

    a = outbox.append(push_dir, _event(1), now=1000.0)
    b = outbox.append(push_dir, _event(2), now=1100.0)
    c = outbox.append(push_dir, _event(3), now=1200.0)
    got = outbox.read_after(push_dir, None, 10_000.0, now=1200.0)
    assert [e["id"] for e in got] == [a, b, c]
    assert got[0]["ts"] == 1000.0 and got[0]["title"] == "t1" and got[0]["kind"] == "reply"
    assert [e["id"] for e in outbox.read_after(push_dir, a, 10_000.0, now=1200.0)] == [b, c]
    assert outbox.read_after(push_dir, c, 10_000.0, now=1200.0) == []
    # older than max_age is skipped even after the cursor
    assert [e["id"] for e in outbox.read_after(push_dir, None, 150.0, now=1200.0)] == [b, c]
    assert [e["id"] for e in outbox.read_after(push_dir, a, 50.0, now=1200.0)] == [c]


def test_unknown_cursor_replays_everything_in_window(push_dir):
    from hermes_iris.push import outbox

    a = outbox.append(push_dir, _event(1), now=1000.0)
    assert [e["id"] for e in outbox.read_after(push_dir, "garbage", 500.0, now=1100.0)] == [a]


def test_reads_nothing_when_no_file(push_dir):
    from hermes_iris.push import outbox

    assert outbox.read_after(push_dir, None, 100.0) == []


def test_cap_is_1000(plugin):
    from hermes_iris.push import outbox

    assert outbox.MAX_EVENTS == 1000 and outbox.MAX_AGE_S == DAY


def test_trims_to_the_cap(push_dir, monkeypatch):
    from hermes_iris.push import outbox

    monkeypatch.setattr(outbox, "MAX_EVENTS", 20)  # 1,000 real appends take ~20 s of file I/O on Windows
    ids = [outbox.append(push_dir, _event(i), now=1000.0 + i) for i in range(30)]
    got = outbox.read_after(push_dir, None, 1e9, now=3000.0)
    assert len(got) == 20
    assert got[0]["id"] == ids[10] and got[-1]["id"] == ids[-1]


def test_trims_older_than_24h(push_dir):
    from hermes_iris.push import outbox

    outbox.append(push_dir, _event(1), now=0.0)
    keep = outbox.append(push_dir, _event(2), now=DAY + 10)
    got = outbox.read_after(push_dir, None, 1e12, now=DAY + 10)
    assert [e["id"] for e in got] == [keep]


def test_torn_line_is_skipped(push_dir):
    from hermes_iris.push import outbox

    a = outbox.append(push_dir, _event(1), now=1000.0)
    with open(push_dir / "outbox.jsonl", "a", encoding="utf-8") as f:
        f.write('{"id": "1", "kind": \n')
    b = outbox.append(push_dir, _event(2), now=1001.0)
    assert [e["id"] for e in outbox.read_after(push_dir, None, 1e9, now=1002.0)] == [a, b]


def test_emoji_and_quotes_survive(push_dir):
    from hermes_iris.push import outbox

    e = _event(1)
    e["title"] = 'Say "hi" 👋'
    outbox.append(push_dir, e, now=1000.0)
    assert outbox.read_after(push_dir, None, 1e9, now=1000.0)[0]["title"] == 'Say "hi" 👋'
    assert "\n" not in json.dumps(e, ensure_ascii=False).replace("\\n", "")


@pytest.mark.skipif(sys.platform == "win32", reason="POSIX file modes")
def test_file_0600(push_dir):
    from hermes_iris.push import outbox

    outbox.append(push_dir, _event(1))
    assert (os.stat(push_dir / "outbox.jsonl").st_mode & 0o777) == 0o600
