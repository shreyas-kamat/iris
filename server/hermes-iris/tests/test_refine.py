from __future__ import annotations

import json

import pytest

SID = "20261106_193512_ab12cd"
OTHER = "20261106_200000_ff00aa"

BASE = {
    "id": "deploy-status",
    "name": "Deploy status",
    "when": "When reporting the state of a deploy",
    "kind": "display",
    "data_schema": {
        "type": "object",
        "properties": {"service": {"type": "string"}, "state": {"type": "string", "enum": ["good", "warn", "bad"]}},
        "required": ["service", "state"],
    },
    "program": 'root = Card([pill], data.service)\npill = StatusPill(data.state, data.state)\n',
    "sample_data": {"service": "api", "state": "good"},
}

BETTER = BASE["program"].replace("[pill]", "[pill, since]") + 'since = KeyValue("Since", data.since)\n'
BETTER_SCHEMA = {
    "type": "object",
    "properties": {**BASE["data_schema"]["properties"], "since": {"type": "string"}},
    "required": ["service", "state", "since"],
}
BETTER_SAMPLE = {"service": "api", "state": "good", "since": "09:12"}


@pytest.fixture
def env(plugin, hermes_home):
    from hermes_iris.genui import catalog, personal, usage
    from hermes_iris.genui.store import Store

    usage.reset()
    p = Store(hermes_home / "iris").profile("default")
    p.flag_session(SID)
    return type("Env", (), {"p": p, "lib": catalog.v1(), "per": personal, "u": usage})


@pytest.fixture
def approved(env):
    assert env.per.propose_template(env.p, env.lib, BASE)["ok"]
    assert env.per.put_template(env.p, env.lib, "deploy-status", {"status": "approved"})["ok"]
    return env


def refine(env, **args):
    args.setdefault("id", "deploy-status")
    args.setdefault("reason", "It was opened in full 6 times; it needs the time it started.")
    return env.per.propose_refinement(env.p, env.lib, args)


# ---- propose_refinement -----------------------------------------------------------------------------------------------


def test_a_refinement_is_stored_beside_the_approved_version(approved):
    r = refine(approved, program=BETTER, data_schema=BETTER_SCHEMA, sample_data=BETTER_SAMPLE)
    assert r == {"ok": True, "id": "deploy-status", "status": "approved", "proposal": "refine"}
    t = approved.p.get_template("deploy-status")
    assert t["status"] == "approved" and t["program"] == BASE["program"], "the version in use is untouched"
    prop = t["proposal"]
    assert prop["program"] == BETTER and prop["data_schema"] == BETTER_SCHEMA and prop["sample_data"] == BETTER_SAMPLE
    assert prop["name"] == "Deploy status" and prop["reason"].startswith("It was opened")
    assert not prop.get("retire")


def test_fields_left_out_are_kept_from_the_approved_template(approved):
    refine(approved, name="Deploy check", when="When a deploy finishes")
    prop = approved.p.get_template("deploy-status")["proposal"]
    assert prop["name"] == "Deploy check" and prop["when"] == "When a deploy finishes"
    assert prop["program"] == BASE["program"] and prop["data_schema"] == BASE["data_schema"]


def test_a_refinement_is_checked_like_a_proposal(approved):
    r = refine(approved, program="root = Nonsense(data.service)\n")
    assert r["ok"] is False and r["errors"]
    r = refine(approved, sample_data={"service": "api", "state": "on fire"})  # not in the schema's enum
    assert r["ok"] is False and r["errors"]
    assert "proposal" not in approved.p.get_template("deploy-status")


def test_a_reason_is_required_and_short(approved):
    assert refine(approved, reason="")["ok"] is False
    assert refine(approved, reason="x" * 301)["ok"] is False
    assert refine(approved, reason=None)["ok"] is False


def test_only_an_approved_template_can_be_refined(env):
    assert refine(env)["ok"] is False  # none at all
    env.per.propose_template(env.p, env.lib, BASE)
    r = refine(env, name="Other")
    assert r["ok"] is False and "approved" in r["errors"][0]


def test_a_second_refinement_replaces_the_first(approved):
    refine(approved, name="First")
    refine(approved, name="Second")
    assert approved.p.get_template("deploy-status")["proposal"]["name"] == "Second"


def test_retiring_is_a_proposal_too(approved):
    r = refine(approved, retire=True, reason="Dismissed 5 times, never used.")
    assert r["ok"] and r["proposal"] == "retire"
    t = approved.p.get_template("deploy-status")
    assert t["status"] == "approved"
    assert t["proposal"] == {"retire": True, "reason": "Dismissed 5 times, never used.", "created": t["proposal"]["created"]}


def test_retire_and_changes_do_not_mix(approved):
    assert refine(approved, retire=True, program=BETTER)["ok"] is False


def test_a_proposal_over_an_approved_id_points_at_refine(approved):
    r = approved.per.propose_template(approved.p, approved.lib, BASE)
    assert r["ok"] is False and "iris_template_refine" in r["errors"][0]


def test_a_refinement_that_changes_nothing_is_refused(approved):
    assert refine(approved)["ok"] is False


# ---- the person decides ------------------------------------------------------------------------------------------------


def test_applying_a_refinement_replaces_the_template_and_bumps_the_revision(approved):
    refine(approved, program=BETTER, data_schema=BETTER_SCHEMA, sample_data=BETTER_SAMPLE)
    before = approved.p.get_template("deploy-status")["rev"]
    r = approved.per.put_template(approved.p, approved.lib, "deploy-status", {"proposal": "apply"})
    assert r["ok"], r
    t = approved.p.get_template("deploy-status")
    assert t["program"] == BETTER and t["status"] == "approved" and t["rev"] == before + 1
    assert "proposal" not in t


def test_applying_a_retirement_retires(approved):
    refine(approved, retire=True, reason="Never used.")
    assert approved.per.put_template(approved.p, approved.lib, "deploy-status", {"proposal": "apply"})["ok"]
    t = approved.p.get_template("deploy-status")
    assert t["status"] == "retired" and "proposal" not in t


def test_discarding_keeps_the_template_as_it_was(approved):
    refine(approved, name="Other")
    assert approved.per.put_template(approved.p, approved.lib, "deploy-status", {"proposal": "discard"})["ok"]
    t = approved.p.get_template("deploy-status")
    assert t["name"] == "Deploy status" and "proposal" not in t


def test_deciding_with_nothing_waiting_is_refused(approved):
    for decision in ("apply", "discard"):
        r = approved.per.put_template(approved.p, approved.lib, "deploy-status", {"proposal": decision})
        assert r["ok"] is False and "waiting" in r["errors"][0]


def test_an_unknown_decision_is_refused(approved):
    refine(approved, name="Other")
    assert approved.per.put_template(approved.p, approved.lib, "deploy-status", {"proposal": "maybe"})["ok"] is False


def test_a_rename_by_the_person_keeps_a_waiting_proposal(approved):
    refine(approved, when="When a deploy ends")
    assert approved.per.put_template(approved.p, approved.lib, "deploy-status", {"name": "Deploys"})["ok"]
    t = approved.p.get_template("deploy-status")
    assert t["name"] == "Deploys" and t["proposal"]["when"] == "When a deploy ends"


def test_retiring_by_hand_drops_a_waiting_proposal(approved):
    refine(approved, name="Other")
    approved.per.put_template(approved.p, approved.lib, "deploy-status", {"status": "retired"})
    assert "proposal" not in approved.p.get_template("deploy-status")


def test_summaries_say_when_a_proposal_waits(approved):
    assert approved.per.list_template_summaries(approved.p)[0]["has_proposal"] is False
    refine(approved, name="Other")
    assert approved.per.list_template_summaries(approved.p)[0]["has_proposal"] is True


def test_the_route_decides(client, hermes_home):
    from hermes_iris.genui import catalog, personal
    from hermes_iris.genui.store import Store

    p = Store(hermes_home / "iris").profile("default")
    personal.propose_template(p, catalog.v1(), BASE)
    personal.put_template(p, catalog.v1(), "deploy-status", {"status": "approved"})
    personal.propose_refinement(p, catalog.v1(), {"id": "deploy-status", "name": "Deploys", "reason": "Shorter."})
    r = client.put("/api/plugins/iris/templates/deploy-status", json={"proposal": "apply"})
    assert r.status_code == 200 and r.json()["template"]["name"] == "Deploys"
    assert client.get("/api/plugins/iris/templates/deploy-status").json()["template"].get("proposal") is None


# ---- iris_usage_summary ------------------------------------------------------------------------------------------------


def test_the_summary_counts_shown_and_signals_per_template(approved):
    from hermes_iris.genui import surfaces

    code = 'root = Text("hi")\n'
    for _ in range(3):
        surfaces.submit(approved.p, approved.lib, SID, {"surface_id": "a", "template": "deploy-status", "data": BASE["sample_data"], "fallback": "x"})
        approved.u.on_post_llm_call(session_id=SID)
    surfaces.submit(approved.p, approved.lib, SID, {"surface_id": "plain", "code": code, "fallback": "x"})
    approved.u.on_post_llm_call(session_id=SID)
    for sig in ("used", "used", "expanded", "dismissed", "not_useful"):
        approved.p.append_usage({"kind": "signal", "ts": 1.0, "signal": sig, "template": "deploy-status"})
    approved.p.append_usage({"kind": "signal", "ts": 1.0, "signal": "used", "session": SID, "surface": "plain"})

    out = approved.per.usage_summary(approved.p)
    assert out["ok"] and out["turns"] == 4 and out["turns_with_display"] == 4
    [t] = out["templates"]
    assert t["id"] == "deploy-status" and t["shown"] == 3
    assert (t["used"], t["expanded"], t["dismissed"], t["not_useful"]) == (2, 1, 1, 1)
    assert out["plain_displays"]["shown"] == 1 and out["plain_displays"]["used"] == 1


def test_a_signal_without_a_template_is_traced_through_its_surface(approved):
    from hermes_iris.genui import surfaces

    surfaces.submit(approved.p, approved.lib, SID, {"surface_id": "a", "template": "deploy-status", "data": BASE["sample_data"], "fallback": "x"})
    approved.p.append_usage({"kind": "signal", "ts": 1.0, "signal": "expanded", "session": SID, "surface": "a"})
    out = approved.per.usage_summary(approved.p)
    assert out["templates"][0]["expanded"] == 1
    assert out["plain_displays"]["expanded"] == 0


def test_templates_never_used_are_listed_with_zeros(approved):
    out = approved.per.usage_summary(approved.p)
    assert out["templates"][0]["shown"] == 0 and out["turns"] == 0


def test_retired_and_proposed_templates_are_not_in_the_summary(env):
    env.per.propose_template(env.p, env.lib, BASE)
    assert env.per.usage_summary(env.p)["templates"] == []


def test_the_summary_holds_no_content(approved):
    refine(approved, name="Other")
    raw = json.dumps(approved.per.usage_summary(approved.p))
    assert "StatusPill" not in raw and "sample" not in raw


def test_damaged_usage_rows_are_skipped(approved):
    approved.p.append_usage({"kind": "signal", "signal": "used", "template": 5})
    approved.p.append_usage({"nonsense": True})
    approved.p.append_usage({"kind": "use", "ts": "x", "templates_used": "nope", "surfaces": None})
    assert approved.per.usage_summary(approved.p)["ok"]


# ---- the tools ---------------------------------------------------------------------------------------------------------


def test_the_tools_are_registered_in_the_iris_toolset(plugin):
    tools = {}

    class Ctx:
        def register_tool(self, **kw):
            tools[kw["name"]] = kw

        def register_hook(self, *a):
            pass

        def register_skill(self, *a, **kw):
            pass

    plugin.register(Ctx())
    for name in ("iris_usage_summary", "iris_template_refine"):
        assert tools[name]["toolset"] == "iris" and callable(tools[name]["handler"])
    assert "reason" in tools["iris_template_refine"]["schema"]["parameters"]["properties"]


def test_the_refine_handler_answers_in_json(approved):
    from hermes_iris.genui import personal_tools

    out = json.loads(personal_tools.handle_template_refine({"id": "deploy-status", "name": "Deploys", "reason": "Shorter."}))
    assert out["ok"] and out["proposal"] == "refine"
    assert json.loads(personal_tools.handle_usage_summary({}))["ok"]
    assert json.loads(personal_tools.handle_template_refine("junk"))["ok"] is False
