from __future__ import annotations

import os

import pytest

from conftest import ROOT

GOLDEN = ROOT / "tests" / "golden"
SID = "20261106_193512_ab12cd"

TEMPLATES = [
    {"id": "jobs", "title": "Job list", "keys": ["title", "rows"]},
    {"id": "deploy-status", "title": "Deploy status", "keys": ["service", "state", "since"]},
]


@pytest.fixture
def ctx_mod(plugin):
    from hermes_iris.genui import context

    return context


@pytest.fixture
def v1(plugin):
    from hermes_iris.genui import catalog

    return catalog.v1()


def _check_golden(name: str, text: str) -> None:
    path = GOLDEN / name
    if os.environ.get("UPDATE_GOLDEN"):
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(text.encode("utf-8"))
    assert text == path.read_bytes().decode("utf-8"), f"{name} changed; rerun with UPDATE_GOLDEN=1 if on purpose"


def test_snapshot_without_templates(ctx_mod, v1):
    _check_golden("context_v1_plain.txt", ctx_mod.build(v1, []))


def test_snapshot_with_templates(ctx_mod, v1):
    _check_golden("context_v1_templates.txt", ctx_mod.build(v1, TEMPLATES))


def test_names_the_tool_and_the_rules(ctx_mod, v1):
    text = ctx_mod.build(v1, [])
    for needle in ("iris_ui", "tool_call", "surface_id", "fallback", "root", "OpenUI", "skill_view('iris:iris-genui'"):
        assert needle in text, needle
    assert "secret" in text.lower()


def test_digest_lists_every_component_with_its_positional_arguments(ctx_mod, v1):
    text = ctx_mod.build(v1, [])
    for name, spec in v1.components.items():
        args = ", ".join(p.name + ("" if p.required else "?") for p in spec.props)
        assert f"{name}({args})" in text, name


def test_templates_are_indexed(ctx_mod, v1):
    text = ctx_mod.build(v1, TEMPLATES)
    assert "jobs" in text and "Job list" in text and "title, rows" in text
    assert "deploy-status" in text


def test_budget_holds_with_many_templates(ctx_mod, v1):
    many = [{"id": f"template-{i}", "title": "A fairly long title for a template " + "x" * 20, "keys": ["a", "b", "c"]} for i in range(200)]
    text = ctx_mod.build(v1, many)
    assert len(text) <= ctx_mod.MAX_CHARS
    assert "more templates" in text
    assert "iris_ui" in text and "skill_view" in text  # the rules and the pointer are never cut


def test_budget_holds_with_a_huge_library(plugin, ctx_mod, v1):
    from hermes_iris.openui import Library

    data = {
        "id": "huge",
        "root": "Stack",
        "schema": {"properties": {}, "$defs": {}},
        "components": {},
    }
    for i in range(300):
        name = f"Component{i}"
        data["schema"]["properties"][name] = {"$ref": f"#/$defs/{name}"}
        data["schema"]["$defs"][name] = {
            "type": "object",
            "properties": {f"argument{j}": {"type": "string"} for j in range(6)},
            "required": ["argument0"],
        }
        data["components"][name] = {"signature": f"{name}()", "description": ""}
    text = ctx_mod.build(Library.from_json(data), TEMPLATES)
    assert len(text) <= ctx_mod.MAX_CHARS
    assert "iris_ui" in text and "skill_view" in text
    assert "Component0" in text and "more components" in text


def test_default_budget_is_2500(ctx_mod):
    assert ctx_mod.MAX_CHARS == 2500


def test_v1_context_is_comfortably_inside_the_budget(ctx_mod, v1):
    assert len(ctx_mod.build(v1, TEMPLATES)) <= 2200


def test_build_is_deterministic(ctx_mod, v1):
    assert ctx_mod.build(v1, TEMPLATES) == ctx_mod.build(v1, list(TEMPLATES))


# ---- the hook --------------------------------------------------------------------------------------------------------


@pytest.fixture
def store(plugin, hermes_home):
    from hermes_iris.genui import paths
    from hermes_iris.genui.store import Store

    return Store(paths.iris_root()).profile("default")


def test_hook_adds_context_for_a_flagged_session(ctx_mod, store):
    store.flag_session(SID)
    out = ctx_mod.on_pre_llm_call(session_id=SID, user_message="hi")
    assert set(out) == {"context"} and "iris_ui" in out["context"]


def test_hook_does_nothing_for_other_sessions(ctx_mod, store):
    assert ctx_mod.on_pre_llm_call(session_id=SID, user_message="hi") is None
    store.flag_session("another_one")
    assert ctx_mod.on_pre_llm_call(session_id=SID) is None


def test_hook_lists_only_approved_templates(ctx_mod, store):
    store.flag_session(SID)
    schema = {"type": "object", "properties": {"title": {"type": "string"}, "rows": {"type": "array"}}}
    store.put_template("jobs", {"name": "Job list", "data_schema": schema, "program": 'root = Text("x")', "status": "approved"})
    store.put_template("draft", {"name": "Not yet", "data_schema": schema, "program": 'root = Text("x")', "status": "proposed"})
    store.put_template("unmarked", {"name": "No flag", "data_schema": schema, "program": 'root = Text("x")'})
    text = ctx_mod.on_pre_llm_call(session_id=SID)["context"]
    assert "jobs" in text and "Job list" in text and "title, rows" in text
    assert "draft" not in text and "unmarked" not in text


def test_hook_never_raises(ctx_mod, store):
    assert ctx_mod.on_pre_llm_call() is None
    assert ctx_mod.on_pre_llm_call(session_id=None) is None
    assert ctx_mod.on_pre_llm_call(session_id=12345) is None
    store.flag_session(SID)
    (store._file("templates")).mkdir(parents=True, exist_ok=True)
    (store._file("templates", "broken.json")).write_text("{nope", "utf-8")
    assert "iris_ui" in ctx_mod.on_pre_llm_call(session_id=SID)["context"]


def test_hook_is_registered(plugin):
    hooks = {}

    class Ctx:
        def register_tool(self, **kw):
            pass

        def register_hook(self, name, fn):
            hooks[name] = fn

    plugin.register(Ctx())
    assert callable(hooks["pre_llm_call"])
