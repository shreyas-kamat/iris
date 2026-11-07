from __future__ import annotations

import json

import pytest

SID = "20261106_193512_ab12cd"
GOOD = 'root = Stack([a])\na = Text("Hello", "title")\n'

TEMPLATE = {
    "name": "Job list",
    "status": "approved",
    "data_schema": {
        "type": "object",
        "properties": {"title": {"type": "string"}, "rows": {"type": "array", "items": {"type": "object"}}},
        "required": ["title", "rows"],
    },
    "program": (
        "root = Stack([head, list])\n"
        'head = Text(data.title, "title")\n'
        'list = Stack(@Each(data.rows, "r", ListRow(r.name, r.state)))\n'
    ),
}


@pytest.fixture
def env(plugin, hermes_home):
    from hermes_iris.genui import catalog, surfaces
    from hermes_iris.genui.store import Store

    store = Store(hermes_home / "iris")
    return type("Env", (), {"p": store.profile("default"), "lib": catalog.v1(), "s": surfaces})


def submit(env, **args):
    args.setdefault("surface_id", "s1")
    return env.s.submit(env.p, env.lib, SID, args)


def test_stores_a_valid_program(env):
    r = submit(env, code=GOOD, fallback="Hello")
    assert r == {"ok": True, "surface_id": "s1", "rev": 1}
    saved = env.p.get_surface(SID, "s1")
    assert saved["code"] == GOOD and saved["fallback"] == "Hello" and saved["rev"] == 1
    assert saved["placement"] == "inline" and saved["session"] == SID and saved["template"] is None


def test_an_update_bumps_the_revision_and_keeps_created(env):
    submit(env, code=GOOD, fallback="one")
    first = env.p.get_surface(SID, "s1")
    r = submit(env, code='root = Text("Two")\n', fallback="two")
    assert r["rev"] == 2
    second = env.p.get_surface(SID, "s1")
    assert second["created"] == first["created"] and second["updated"] >= first["updated"]
    assert second["code"] == 'root = Text("Two")\n'


def test_surfaces_are_per_session(env):
    submit(env, code=GOOD, fallback="x")
    other = env.s.submit(env.p, env.lib, "20261107_000000_ffffff", {"surface_id": "s1", "code": GOOD, "fallback": "x"})
    assert other["rev"] == 1


def test_delete(env):
    submit(env, code=GOOD, fallback="x")
    assert submit(env, delete=True) == {"ok": True, "surface_id": "s1", "deleted": True}
    assert env.p.get_surface(SID, "s1") is None
    assert submit(env, delete=True) == {"ok": True, "surface_id": "s1", "deleted": False}


def test_reply_kit_placement(env):
    assert submit(env, code=GOOD, fallback="x", placement="reply_kit")["ok"]
    assert env.p.get_surface(SID, "s1")["placement"] == "reply_kit"


def test_template_with_data(env):
    env.p.put_template("jobs", TEMPLATE)
    r = submit(env, template="jobs", data={"title": "Jobs", "rows": [{"name": "backup", "state": "ok"}]}, fallback="Jobs: backup ok")
    assert r["ok"], r
    saved = env.p.get_surface(SID, "s1")
    assert saved["template"] == "jobs"
    assert saved["code"].startswith('data = {"title": "Jobs", "rows": [{"name": "backup", "state": "ok"}]}\n')


def test_rejects_invalid_data_for_a_template(env):
    env.p.put_template("jobs", TEMPLATE)
    r = submit(env, template="jobs", data={"rows": []}, fallback="x")
    assert r["ok"] is False and any("title is required" in e for e in r["errors"]), r
    assert env.p.get_surface(SID, "s1") is None


def test_unknown_template_lists_the_ones_that_exist(env):
    env.p.put_template("jobs", TEMPLATE)
    r = submit(env, template="nope", data={}, fallback="x")
    assert r["ok"] is False and "jobs" in " ".join(r["errors"])


def test_template_without_data(env):
    env.p.put_template("jobs", TEMPLATE)
    r = submit(env, template="jobs", fallback="x")
    assert r["ok"] is False and any("data" in e for e in r["errors"])


def test_rejection_gives_model_readable_lines(env):
    r = submit(env, code='root = Stack([a])\na = Gauge(3)\n', fallback="x")
    assert r["ok"] is False
    assert any("unknown component" in e and "Available:" in e for e in r["errors"]), r
    assert env.p.get_surface(SID, "s1") is None


def test_a_rejected_update_leaves_the_old_surface(env):
    submit(env, code=GOOD, fallback="x")
    r = submit(env, code="root = (", fallback="x")
    assert r["ok"] is False
    assert env.p.get_surface(SID, "s1")["rev"] == 1


def test_fallback_is_required(env):
    for fallback in (None, "", "   "):
        args = {"code": GOOD}
        if fallback is not None:
            args["fallback"] = fallback
        r = submit(env, **args)
        assert r["ok"] is False and any("fallback" in e for e in r["errors"]), r


def test_exactly_one_of_code_and_template(env):
    both = submit(env, code=GOOD, template="x", data={}, fallback="x")
    neither = submit(env, fallback="x")
    for r in (both, neither):
        assert r["ok"] is False and any("code" in e and "template" in e for e in r["errors"]), r


@pytest.mark.parametrize(
    "bad",
    [
        {"surface_id": "../x"},
        {"surface_id": ""},
        {"surface_id": None},
        {"placement": "banner"},
        {"code": 3},
        {"fallback": 3},
        {"data": [1]},
    ],
)
def test_bad_arguments_are_reported_not_raised(env, bad):
    args = {"surface_id": "s1", "code": GOOD, "fallback": "x", **bad}
    r = env.s.submit(env.p, env.lib, SID, args)
    assert r["ok"] is False and r["errors"], r


def test_a_bad_session_id_is_reported(env):
    r = env.s.submit(env.p, env.lib, "bad id!", {"surface_id": "s", "code": GOOD, "fallback": "x"})
    assert r["ok"] is False


def test_the_fallback_is_capped(env):
    r = submit(env, code=GOOD, fallback="x" * 9000)
    assert r["ok"] is False and any("fallback" in e for e in r["errors"])


# ---- the tool as Hermes calls it ------------------------------------------------------------------------------------


def test_handler_returns_json_text(plugin, hermes_home):
    from hermes_iris.genui import tool

    out = tool.handle_iris_ui({"surface_id": "s1", "code": GOOD, "fallback": "Hello"}, session_id=SID, task_id="t")
    assert isinstance(out, str)
    assert json.loads(out) == {"ok": True, "surface_id": "s1", "rev": 1}


def test_handler_without_a_session_is_an_error_not_a_crash(plugin, hermes_home):
    from hermes_iris.genui import tool

    out = json.loads(tool.handle_iris_ui({"surface_id": "s1", "code": GOOD, "fallback": "x"}))
    assert out["ok"] is False


def test_handler_never_raises(plugin, hermes_home):
    from hermes_iris.genui import tool

    for args in (None, [], "x", {"surface_id": object()}):
        out = json.loads(tool.handle_iris_ui(args, session_id=SID))  # type: ignore[arg-type]
        assert out["ok"] is False


def test_schema_names_every_argument(plugin):
    from hermes_iris.genui import tool

    props = tool.SCHEMA["parameters"]["properties"]
    assert tool.SCHEMA["name"] == "iris_ui"
    assert set(props) == {"surface_id", "code", "template", "data", "fallback", "placement", "delete"}
    assert tool.SCHEMA["parameters"]["required"] == ["surface_id"]
    assert props["placement"]["enum"] == ["inline", "reply_kit"]


def test_register_adds_the_tool(plugin):
    calls = []

    class Ctx:
        def register_tool(self, **kw):
            calls.append(kw)

        def __getattr__(self, name):
            return lambda *a, **k: None

    plugin.register(Ctx())
    (call,) = [c for c in calls if c["name"] == "iris_ui"]
    assert call["toolset"] == "iris" and callable(call["handler"]) and call["schema"]["name"] == "iris_ui"
