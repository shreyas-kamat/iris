from __future__ import annotations

import json

import pytest

SID = "20261106_193512_ab12cd"

SCHEMA = {
    "type": "object",
    "properties": {"title": {"type": "string"}, "rows": {"type": "array", "items": {"type": "object"}}},
    "required": ["title", "rows"],
}
PROGRAM = (
    "root = Stack([head, list])\n"
    'head = Text(data.title, "title")\n'
    'list = Stack(@Each(data.rows, "r", ListRow(r.name, r.state)))\n'
)
SAMPLE = {"title": "Jobs", "rows": [{"name": "backup", "state": "ok"}]}


def proposal(**over):
    base = {
        "id": "jobs",
        "name": "Job list",
        "when": "Whenever cron jobs are listed",
        "data_schema": SCHEMA,
        "program": PROGRAM,
        "sample_data": SAMPLE,
    }
    base.update(over)
    return base


@pytest.fixture
def env(plugin, hermes_home):
    from hermes_iris.genui import catalog, personal
    from hermes_iris.genui.store import Store

    store = Store(hermes_home / "iris")
    return type("Env", (), {"p": store.profile("default"), "lib": catalog.v1(), "m": personal})


# ---- profile ---------------------------------------------------------------------------------------------------------


def test_no_profile_yet(env):
    assert env.m.get_profile(env.p) == {"ok": True, "profile": None}


def test_propose_a_profile(env):
    r = env.m.propose_profile(env.p, {"summary": "Backend engineer who ships APIs", "chips": ["APIs", "On call", "Python"]})
    assert r == {"ok": True, "rev": 1, "status": "proposed"}
    prof = env.m.get_profile(env.p)["profile"]
    assert prof["summary"] == "Backend engineer who ships APIs"
    assert prof["chips"] == ["APIs", "On call", "Python"] and prof["status"] == "proposed" and prof["rev"] == 1


def test_a_new_proposal_replaces_the_old_and_keeps_what_was_approved(env):
    env.m.propose_profile(env.p, {"summary": "One", "chips": ["a"]})
    env.m.put_profile(env.p, {"status": "approved"})
    r = env.m.propose_profile(env.p, {"summary": "Two", "chips": ["b"]})
    assert r["rev"] == 3 and r["status"] == "proposed"
    prof = env.m.get_profile(env.p)["profile"]
    assert prof["summary"] == "Two"
    assert prof["previous"] == {"summary": "One", "chips": ["a"]}


@pytest.mark.parametrize(
    "args, needle",
    [
        ("nope", "object"),
        ({"chips": []}, "summary"),
        ({"summary": "  "}, "summary"),
        ({"summary": "x" * 601}, "600"),
        ({"summary": "ok", "chips": "a"}, "chips must be a list"),
        ({"summary": "ok", "chips": [1]}, "chips"),
        ({"summary": "ok", "chips": ["a"] * 13}, "12"),
        ({"summary": "ok", "chips": ["x" * 41]}, "40"),
    ],
)
def test_bad_profiles_are_refused_with_a_line_to_fix(env, args, needle):
    r = env.m.propose_profile(env.p, args)
    assert r["ok"] is False and any(needle in e for e in r["errors"]), r
    assert env.m.get_profile(env.p)["profile"] is None


def test_the_person_edits_the_profile(env):
    env.m.propose_profile(env.p, {"summary": "One", "chips": ["a"]})
    r = env.m.put_profile(env.p, {"summary": "Mine", "status": "approved"})
    assert r["ok"] is True and r["profile"]["summary"] == "Mine" and r["profile"]["status"] == "approved"
    assert r["profile"]["chips"] == ["a"], "fields that are not sent keep their value"
    assert r["profile"]["rev"] == 2


def test_put_profile_needs_a_known_status(env):
    env.m.propose_profile(env.p, {"summary": "One"})
    r = env.m.put_profile(env.p, {"status": "maybe"})
    assert r["ok"] is False and "status" in r["errors"][0]


def test_put_profile_with_nothing_stored_needs_a_summary(env):
    assert env.m.put_profile(env.p, {"status": "approved"})["ok"] is False
    assert env.m.put_profile(env.p, {"summary": "Fresh", "status": "approved"})["ok"] is True


# ---- templates -------------------------------------------------------------------------------------------------------


def test_propose_a_template(env):
    r = env.m.propose_template(env.p, env.lib, proposal())
    assert r == {"ok": True, "id": "jobs", "rev": 1, "status": "proposed"}
    t = env.p.get_template("jobs")
    assert t["name"] == "Job list" and t["when"] == "Whenever cron jobs are listed"
    assert t["data_schema"] == SCHEMA and t["program"] == PROGRAM and t["sample_data"] == SAMPLE
    assert t["status"] == "proposed" and t["rev"] == 1 and t["id"] == "jobs"
    assert t["created"] <= t["updated"]


def test_a_proposed_template_is_not_usable_until_approved(env):
    from hermes_iris.genui import surfaces

    env.m.propose_template(env.p, env.lib, proposal())
    r = surfaces.submit(env.p, env.lib, SID, {"surface_id": "s", "template": "jobs", "data": SAMPLE, "fallback": "x"})
    assert r["ok"] is False and "not approved" in r["errors"][0]
    env.m.put_template(env.p, env.lib, "jobs", {"status": "approved"})
    r = surfaces.submit(env.p, env.lib, SID, {"surface_id": "s", "template": "jobs", "data": SAMPLE, "fallback": "x"})
    assert r["ok"] is True


def test_the_sample_must_fit_the_schema(env):
    r = env.m.propose_template(env.p, env.lib, proposal(sample_data={"title": 3, "rows": []}))
    assert r["ok"] is False and any("title must be a string" in e for e in r["errors"])
    assert env.p.get_template("jobs") is None


def test_the_program_must_validate_with_the_sample_expanded(env):
    r = env.m.propose_template(env.p, env.lib, proposal(program='root = Nope("x")\n'))
    assert r["ok"] is False and r["errors"]
    assert env.p.get_template("jobs") is None


def test_a_template_cannot_define_data_itself(env):
    r = env.m.propose_template(env.p, env.lib, proposal(program='data = {}\nroot = Text("x")\n'))
    assert r["ok"] is False and any("data" in e for e in r["errors"])


@pytest.mark.parametrize(
    "over, needle",
    [
        ({"id": "../x"}, "id"),
        ({"id": 5}, "id"),
        ({"name": ""}, "name"),
        ({"name": "n" * 61}, "name"),
        ({"when": ""}, "when"),
        ({"when": "w" * 201}, "when"),
        ({"data_schema": "x"}, "data_schema"),
        ({"data_schema": {"type": "array"}}, "data_schema"),
        ({"data_schema": {"type": "object", "pad": "x" * 5000}}, "data_schema"),
        ({"program": ""}, "program"),
        ({"program": 4}, "program"),
        ({"sample_data": []}, "sample_data"),
        ({"sample_data": {"title": "t", "rows": [], "pad": "x" * 5000}}, "sample_data"),
    ],
)
def test_malformed_proposals_say_which_field(env, over, needle):
    r = env.m.propose_template(env.p, env.lib, proposal(**over))
    assert r["ok"] is False and any(needle in e for e in r["errors"]), r


def test_a_missing_field_is_named(env):
    args = proposal()
    del args["when"]
    r = env.m.propose_template(env.p, env.lib, args)
    assert r["ok"] is False and any("when" in e for e in r["errors"])


def test_re_proposing_a_proposed_template_bumps_the_revision(env):
    env.m.propose_template(env.p, env.lib, proposal())
    r = env.m.propose_template(env.p, env.lib, proposal(name="Jobs v2"))
    assert r["rev"] == 2
    t = env.p.get_template("jobs")
    assert t["name"] == "Jobs v2" and t["created"] <= t["updated"]


def test_a_proposal_cannot_replace_an_approved_template(env):
    env.m.propose_template(env.p, env.lib, proposal())
    env.m.put_template(env.p, env.lib, "jobs", {"status": "approved"})
    r = env.m.propose_template(env.p, env.lib, proposal(name="Sneaky"))
    assert r["ok"] is False and "approved" in r["errors"][0]
    assert env.p.get_template("jobs")["name"] == "Job list"


def test_a_retired_template_can_be_proposed_again(env):
    env.m.propose_template(env.p, env.lib, proposal())
    env.m.put_template(env.p, env.lib, "jobs", {"status": "retired"})
    r = env.m.propose_template(env.p, env.lib, proposal(name="Back"))
    assert r["ok"] is True and r["status"] == "proposed"


def test_template_count_is_capped(env):
    for i in range(env.m.MAX_TEMPLATES):
        assert env.m.propose_template(env.p, env.lib, proposal(id=f"t{i}"))["ok"]
    r = env.m.propose_template(env.p, env.lib, proposal(id="one-more"))
    assert r["ok"] is False and str(env.m.MAX_TEMPLATES) in r["errors"][0]
    assert env.m.propose_template(env.p, env.lib, proposal(id="t0", name="Again"))["ok"], "updating is not adding"


def test_the_person_renames_and_retires(env):
    env.m.propose_template(env.p, env.lib, proposal())
    r = env.m.put_template(env.p, env.lib, "jobs", {"name": "My jobs", "status": "approved"})
    assert r["ok"] is True and r["template"]["name"] == "My jobs" and r["template"]["status"] == "approved"
    assert r["template"]["program"] == PROGRAM and r["template"]["rev"] == 2
    r = env.m.put_template(env.p, env.lib, "jobs", {"status": "retired"})
    assert r["template"]["status"] == "retired" and r["template"]["rev"] == 3


def test_put_validates_changed_content(env):
    env.m.propose_template(env.p, env.lib, proposal())
    r = env.m.put_template(env.p, env.lib, "jobs", {"program": 'root = Nope("x")\n'})
    assert r["ok"] is False
    assert env.p.get_template("jobs")["program"] == PROGRAM


def test_put_creates_only_with_every_field(env):
    r = env.m.put_template(env.p, env.lib, "fresh", {"name": "Only a name"})
    assert r["ok"] is False
    body = proposal(id="fresh")
    del body["id"]
    body["status"] = "approved"
    r = env.m.put_template(env.p, env.lib, "fresh", body)
    assert r["ok"] is True and r["template"]["id"] == "fresh" and r["template"]["status"] == "approved"


def test_put_cannot_change_the_id_or_reach_outside(env):
    env.m.propose_template(env.p, env.lib, proposal())
    r = env.m.put_template(env.p, env.lib, "jobs", {"id": "other", "name": "X"})
    assert r["template"]["id"] == "jobs"
    assert env.m.put_template(env.p, env.lib, "../x", proposal())["ok"] is False


def test_put_needs_a_known_status(env):
    env.m.propose_template(env.p, env.lib, proposal())
    r = env.m.put_template(env.p, env.lib, "jobs", {"status": "live"})
    assert r["ok"] is False and "status" in r["errors"][0]


def test_list_templates_gives_summaries_with_the_data_keys(env):
    env.m.propose_template(env.p, env.lib, proposal())
    env.m.propose_template(env.p, env.lib, proposal(id="other", name="Other"))
    env.m.put_template(env.p, env.lib, "other", {"status": "approved"})
    r = env.m.list_template_summaries(env.p)
    by = {t["id"]: t for t in r}
    assert set(by) == {"jobs", "other"}
    assert by["jobs"] == {
        "id": "jobs",
        "name": "Job list",
        "when": "Whenever cron jobs are listed",
        "kind": "display",
        "status": "proposed",
        "rev": 1,
        "keys": ["title", "rows"],
    }
    assert by["other"]["status"] == "approved"
    only = env.m.list_template_summaries(env.p, status="approved")
    assert [t["id"] for t in only] == ["other"]


def test_damaged_template_files_are_skipped(env, hermes_home):
    env.m.propose_template(env.p, env.lib, proposal())
    (hermes_home / "iris" / "default" / "templates" / "broken.json").write_text("{nope", "utf-8")
    assert [t["id"] for t in env.m.list_template_summaries(env.p)] == ["jobs"]


# ---- the tools ---------------------------------------------------------------------------------------------------------


def run(handler, args, **kw):
    kw.setdefault("session_id", SID)
    return json.loads(handler(args, **kw))


def test_tool_schemas_and_registration(plugin):
    from hermes_iris.genui import personal_tools as pt

    names = {s["name"] for s in pt.SCHEMAS}
    assert names == {"iris_profile_get", "iris_profile_propose", "iris_template_list", "iris_template_propose"}
    calls = []

    class Ctx:
        def register_tool(self, **kw):
            calls.append(kw)

        def __getattr__(self, name):
            return lambda *a, **k: None

    plugin.register(Ctx())
    registered = {c["name"]: c for c in calls}
    assert names <= set(registered)
    assert all(registered[n]["toolset"] == "iris" and callable(registered[n]["handler"]) for n in names)
    assert pt.TEMPLATE_PROPOSE["parameters"]["required"] == ["id", "name", "when", "data_schema", "program", "sample_data"]


def test_tools_work_end_to_end(plugin, hermes_home):
    from hermes_iris.genui import personal_tools as pt

    assert run(pt.handle_profile_get, {}) == {"ok": True, "profile": None}
    assert run(pt.handle_profile_propose, {"summary": "Engineer", "chips": ["a"]})["ok"]
    assert run(pt.handle_profile_get, {})["profile"]["summary"] == "Engineer"
    assert run(pt.handle_template_propose, proposal()) == {"ok": True, "id": "jobs", "rev": 1, "status": "proposed"}
    listed = run(pt.handle_template_list, {})
    assert [t["id"] for t in listed["templates"]] == ["jobs"]
    assert "program" not in listed["templates"][0]


def test_tool_errors_do_not_raise(plugin, hermes_home):
    from hermes_iris.genui import personal_tools as pt

    assert run(pt.handle_template_propose, "nope")["ok"] is False
    assert run(pt.handle_profile_propose, None)["ok"] is False


# ---- kind: a template is a display or a reply kit --------------------------------------------------------------------


def test_kind_defaults_to_display_and_is_kept(env):
    env.m.propose_template(env.p, env.lib, proposal())
    assert env.p.get_template("jobs")["kind"] == "display"
    env.m.propose_template(env.p, env.lib, proposal(id="kit", kind="reply_kit"))
    assert env.p.get_template("kit")["kind"] == "reply_kit"
    assert {t["id"]: t["kind"] for t in env.m.list_template_summaries(env.p)} == {"jobs": "display", "kit": "reply_kit"}


def test_kind_must_be_known(env):
    r = env.m.propose_template(env.p, env.lib, proposal(kind="banner"))
    assert r["ok"] is False and any("kind" in e for e in r["errors"])


def test_the_person_can_not_leave_kind_unknown_on_put(env):
    env.m.propose_template(env.p, env.lib, proposal())
    assert env.m.put_template(env.p, env.lib, "jobs", {"kind": "reply_kit"})["template"]["kind"] == "reply_kit"
    assert env.m.put_template(env.p, env.lib, "jobs", {"kind": "x"})["ok"] is False


def test_an_older_record_without_kind_reads_as_a_display(env):
    env.p.put_template("old", {"id": "old", "name": "Old", "when": "w", "status": "approved", "data_schema": SCHEMA})
    assert env.m.list_template_summaries(env.p)[0]["kind"] == "display"


def test_a_reply_kit_template_docks_by_default(env):
    from hermes_iris.genui import surfaces

    kit = (
        'root = Stack([q, go])\nq = Text(data.question)\n'
        'go = ApproveReject("Go ahead", "Hold", "Ask me")\n'
    )
    schema = {"type": "object", "properties": {"question": {"type": "string"}}, "required": ["question"]}
    r = env.m.propose_template(
        env.p, env.lib, proposal(id="decide", kind="reply_kit", data_schema=schema, program=kit, sample_data={"question": "Deploy?"})
    )
    assert r["ok"], r
    env.m.put_template(env.p, env.lib, "decide", {"status": "approved"})
    args = {"surface_id": "k", "template": "decide", "data": {"question": "Ship it?"}, "fallback": "Ship it?"}
    assert surfaces.submit(env.p, env.lib, SID, args)["ok"]
    assert env.p.get_surface(SID, "k")["placement"] == "reply_kit"
    assert surfaces.submit(env.p, env.lib, SID, {**args, "surface_id": "k2", "placement": "inline"})["ok"]
    assert env.p.get_surface(SID, "k2")["placement"] == "inline", "an explicit placement wins"
