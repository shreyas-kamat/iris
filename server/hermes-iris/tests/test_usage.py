from __future__ import annotations

import json

import pytest

SID = "20261106_193512_ab12cd"
OTHER = "20261106_200000_ff00aa"
GOOD = 'root = Stack([a])\na = Text("Hello", "title")\n'

TEMPLATE = {
    "name": "Job list",
    "status": "approved",
    "data_schema": {
        "type": "object",
        "properties": {"title": {"type": "string"}},
        "required": ["title"],
    },
    "program": 'root = Text(data.title, "title")\n',
}


@pytest.fixture
def env(plugin, hermes_home):
    from hermes_iris.genui import catalog, surfaces, usage
    from hermes_iris.genui.store import Store

    usage.reset()
    profile = Store(hermes_home / "iris").profile("default")
    profile.flag_session(SID)
    profile.flag_session(OTHER)
    return type("Env", (), {"p": profile, "lib": catalog.v1(), "s": surfaces, "u": usage})


def show(env, session=SID, **args):
    args.setdefault("surface_id", "s1")
    args.setdefault("code", GOOD)
    args.setdefault("fallback", "Hello")
    return env.s.submit(env.p, env.lib, session, args)


def rows(env):
    return [r for r in env.p.read_usage() if r.get("kind") == "use"]


def finish(env, session=SID, **kw):
    return env.u.on_post_llm_call(session_id=session, user_message="hi", assistant_response="ok", **kw)


def test_a_turn_with_displays_logs_one_use_row(env):
    show(env, surface_id="a")
    show(env, surface_id="b")
    assert finish(env) is None
    [row] = rows(env)
    assert row["session"] == SID
    assert row["surfaces"] == ["a", "b"]
    assert row["templates_used"] == []
    assert isinstance(row["ts"], float)


def test_templates_are_listed_once_each(env):
    env.p.put_template("jobs", dict(TEMPLATE))
    show(env, surface_id="a", code=None, template="jobs", data={"title": "x"})
    show(env, surface_id="b", code=None, template="jobs", data={"title": "y"})
    show(env, surface_id="c")
    finish(env)
    [row] = rows(env)
    assert row["templates_used"] == ["jobs"]
    assert row["surfaces"] == ["a", "b", "c"]


def test_the_same_surface_updated_twice_counts_once(env):
    show(env, surface_id="a")
    show(env, surface_id="a")
    finish(env)
    assert rows(env)[0]["surfaces"] == ["a"]


def test_a_turn_without_displays_still_logs_an_empty_row(env):
    finish(env)
    [row] = rows(env)
    assert row["surfaces"] == [] and row["templates_used"] == []


def test_a_refused_call_is_not_counted(env):
    show(env, surface_id="a", code="nonsense (")
    finish(env)
    assert rows(env)[0]["surfaces"] == []


def test_a_delete_is_not_a_display_shown(env):
    show(env, surface_id="a")
    finish(env)
    show(env, surface_id="a", delete=True, code=None, fallback=None)
    finish(env)
    assert [r["surfaces"] for r in rows(env)] == [["a"], []]


def test_the_next_turn_starts_empty(env):
    show(env, surface_id="a")
    finish(env)
    finish(env)
    assert [r["surfaces"] for r in rows(env)] == [["a"], []]


def test_sessions_do_not_mix(env):
    show(env, session=SID, surface_id="a")
    show(env, session=OTHER, surface_id="b")
    finish(env, session=OTHER)
    finish(env, session=SID)
    by = {r["session"]: r["surfaces"] for r in rows(env)}
    assert by == {SID: ["a"], OTHER: ["b"]}


def test_an_unflagged_session_is_not_logged(env, hermes_home):
    stranger = "20261106_999999_deadbe"
    assert finish(env, session=stranger) is None
    assert rows(env) == []


def test_no_program_text_or_message_reaches_the_log(env):
    show(env, surface_id="a", fallback="SECRET-FALLBACK", code='root = Text("SECRET-CODE")\n')
    env.u.on_post_llm_call(session_id=SID, user_message="SECRET-USER", assistant_response="SECRET-REPLY")
    raw = (hermes_usage_path(env)).read_text(encoding="utf-8")
    assert "SECRET" not in raw
    assert set(json.loads(raw.splitlines()[-1])) == {"kind", "ts", "session", "templates_used", "surfaces"}


def hermes_usage_path(env):
    return env.p._file("usage.jsonl")


def test_pending_work_is_bounded(env):
    for i in range(env.u.MAX_SESSIONS + 20):
        sid = f"20261106_{i:06d}_aaaaaa"
        env.p.flag_session(sid)
        show(env, session=sid, surface_id="a")
    assert env.u.pending_sessions() <= env.u.MAX_SESSIONS
    for i in range(env.u.MAX_SURFACES + 20):
        show(env, surface_id=f"s{i}")
    finish(env)
    assert len(rows(env)[-1]["surfaces"]) <= env.u.MAX_SURFACES


def test_never_raises(env):
    assert env.u.on_post_llm_call() is None
    assert env.u.on_post_llm_call(session_id=5) is None
    assert env.u.on_post_llm_call(session_id=object(), user_message=None) is None


def test_the_hook_is_registered(plugin):
    hooks = {}

    class Ctx:
        def register_tool(self, **kw):
            pass

        def register_hook(self, name, fn):
            hooks[name] = fn

        def register_skill(self, *a, **kw):
            pass

    plugin.register(Ctx())
    assert callable(hooks["post_llm_call"])


def test_old_readers_can_tell_rows_apart_by_kind(env):
    show(env, surface_id="a")
    finish(env)
    env.p.append_usage({"kind": "signal", "ts": 1.0, "signal": "used"})
    kinds = sorted(r["kind"] for r in env.p.read_usage())
    assert kinds == ["signal", "use"]
