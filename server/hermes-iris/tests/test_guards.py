from __future__ import annotations

import json

import pytest

SID = "20261106_193512_ab12cd"


@pytest.fixture
def g(plugin, hermes_home):
    from hermes_iris.genui import guards

    guards.reset()
    return guards


@pytest.fixture
def flagged(plugin, hermes_home):
    from hermes_iris.genui import paths
    from hermes_iris.genui.store import Store

    Store(paths.iris_root()).profile("default").flag_session(SID)


def call(g, name="iris_ui", args=None, session=SID, turn="t1"):
    return g.on_pre_tool_call(tool_name=name, args=args or {}, session_id=session, turn_id=turn, task_id="x")


def test_blocks_in_an_unflagged_session(g):
    out = call(g)
    assert out["action"] == "block"
    assert "Iris" in out["message"] and "Markdown" in out["message"]


def test_blocks_every_iris_tool_in_an_unflagged_session(g):
    for name in ("iris_ui", "iris_profile_propose", "iris_made_up_tool"):
        assert call(g, name)["action"] == "block", name


def test_allows_a_flagged_session(g, flagged):
    assert call(g) is None


def test_learning_tools_work_in_any_session(g):
    """A scheduled /iris-refine run is not an Iris-flagged session; the tools it needs still work there."""
    for name in (
        "iris_usage_summary",
        "iris_template_refine",
        "iris_template_list",
        "iris_template_propose",
        "iris_profile_get",
    ):
        assert call(g, name, session="cron_20261109_090000") is None, name
        assert call(g, name, session=None) is None, name


def test_display_and_profile_writes_stay_in_flagged_sessions(g):
    for name in ("iris_ui", "iris_profile_propose"):
        assert call(g, name, session="cron_20261109_090000")["action"] == "block", name


def test_ignores_other_tools(g):
    for name in ("terminal", "read_file", "tool_call", "tool_search", "irisx", "my_iris_ui"):
        assert call(g, name) is None, name


def test_a_missing_or_odd_session_is_blocked_not_a_crash(g):
    for session in (None, "", "not valid!", 5):
        assert call(g, session=session)["action"] == "block"


def test_never_raises(g):
    assert g.on_pre_tool_call() is None
    assert g.on_pre_tool_call(tool_name=None, args=None) is None
    assert g.on_pre_tool_call(tool_name=3, args="x", session_id=object()) is None


def test_at_most_four_surfaces_per_turn(g, flagged):
    for i in range(4):
        assert call(g, args={"surface_id": f"s{i}"}) is None
    out = call(g, args={"surface_id": "s4"})
    assert out["action"] == "block" and "4" in out["message"]


def test_updating_the_same_surface_counts_once(g, flagged):
    for _ in range(10):
        assert call(g, args={"surface_id": "same"}) is None


def test_deleting_does_not_count(g, flagged):
    for i in range(10):
        assert call(g, args={"surface_id": f"d{i}", "delete": True}) is None
    assert call(g, args={"surface_id": "real"}) is None


def test_turns_are_independent(g, flagged):
    for i in range(4):
        call(g, args={"surface_id": f"s{i}"}, turn="a")
    assert call(g, args={"surface_id": "x"}, turn="a")["action"] == "block"
    assert call(g, args={"surface_id": "x"}, turn="b") is None


def test_turn_memory_is_bounded(g, flagged):
    for i in range(g.TURNS_REMEMBERED + 50):
        call(g, args={"surface_id": "s"}, turn=f"turn{i}")
    assert g.remembered_turns() <= g.TURNS_REMEMBERED


def test_a_blocked_call_does_not_use_up_the_budget(g, flagged):
    for i in range(4):
        call(g, args={"surface_id": f"s{i}"})
    for _ in range(3):
        assert call(g, args={"surface_id": "s9"})["action"] == "block"
    assert call(g, args={"surface_id": "s0"}) is None  # an update of one already shown is still fine


# ---- transform_tool_result ---------------------------------------------------------------------------------------------


def tr(g, result, name="iris_ui"):
    return g.on_transform_tool_result(tool_name=name, result=result, args={})


def test_success_receipt_is_trimmed_to_the_essentials(g):
    raw = json.dumps({"ok": True, "surface_id": "s1", "rev": 3, "debug": "x" * 500, "extra": [1, 2, 3]})
    assert json.loads(tr(g, raw)) == {"ok": True, "surface_id": "s1", "rev": 3}


def test_delete_receipt(g):
    raw = json.dumps({"ok": True, "surface_id": "s1", "deleted": True, "junk": 1})
    assert json.loads(tr(g, raw)) == {"ok": True, "surface_id": "s1", "deleted": True}


def test_error_receipt_keeps_the_lines_but_caps_the_size(g):
    raw = json.dumps({"ok": False, "errors": [f"line {i} " + "x" * 300 for i in range(30)]})
    out = tr(g, raw)
    assert len(out) <= 1500
    parsed = json.loads(out)
    assert parsed["ok"] is False and parsed["errors"][0].startswith("line 0")


def test_short_errors_pass_through_unchanged(g):
    raw = json.dumps({"ok": False, "errors": ["a", "b"]}, ensure_ascii=False)
    assert json.loads(tr(g, raw)) == {"ok": False, "errors": ["a", "b"]}


def test_other_tools_and_odd_results_are_left_alone(g):
    assert tr(g, '{"ok": true}', name="terminal") is None
    assert tr(g, "plain text") is None
    assert tr(g, "[1, 2]") is None
    assert tr(g, None) is None
    assert tr(g, 5) is None


def test_transform_never_raises(g):
    assert g.on_transform_tool_result() is None
    assert g.on_transform_tool_result(tool_name="iris_ui", result=object()) is None


def test_register_hooks(plugin):
    hooks = {}

    class Ctx:
        def register_tool(self, **kw):
            pass

        def register_hook(self, name, fn):
            hooks[name] = fn

    plugin.register(Ctx())
    assert callable(hooks["pre_tool_call"]) and callable(hooks["transform_tool_result"])
