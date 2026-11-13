from __future__ import annotations

import json

import pytest

SID = "20261113_051659_b9bbb3"
CRON = "cron_job1_20261113_060000"


def _settings(plugin, **modes):
    from hermes_iris.push.devices import DEFAULT_SETTINGS, normalize_settings

    s = normalize_settings(DEFAULT_SETTINGS)
    for kind, mode in modes.items():
        s[kind]["mode"] = mode
        s[kind]["text"] = "Look!"
    return s


REPLY = {"id": "11", "kind": "reply", "session_id": SID, "title": "Trip plan", "outcome": "completed",
         "preview": "Here is the plan"}
FAILED = {"id": "12", "kind": "reply", "session_id": SID, "title": "Trip plan", "outcome": "failed", "preview": None}
APPROVAL = {"id": "13", "kind": "approval", "session_id": SID, "title": "Trip plan", "command": "rm -rf /tmp/x",
            "description": "recursive delete"}
DONE = {"id": "14", "kind": "approval_done", "session_id": SID}
JOB = {"id": "15", "kind": "job", "session_id": CRON, "job_id": "job1", "job_name": "Daily plan",
       "outcome": "completed"}
JOB_EMPTY = {**JOB, "id": "16", "outcome": "no_output"}


def test_reply_completed_content(plugin):
    from hermes_iris.push.render import notice

    assert notice(REPLY, _settings(plugin, reply="content")) == {
        "event_id": "11", "kind": "reply", "session_id": SID, "title": "Look!", "body": "Here is the plan",
        "category": None, "collapse": f"reply-{SID}",
    }


def test_reply_completed_falls_back_to_title(plugin):
    from hermes_iris.push.render import notice

    n = notice({**REPLY, "preview": None}, _settings(plugin, reply="content"))
    assert n["body"] == "Trip plan"
    assert notice({**REPLY, "preview": None, "title": None}, _settings(plugin, reply="content"))["body"] is None


def test_reply_failed_content(plugin):
    from hermes_iris.push.render import notice

    assert notice(FAILED, _settings(plugin, reply="content"))["body"] == "Reply failed: Trip plan"
    assert notice({**FAILED, "title": None}, _settings(plugin, reply="content"))["body"] == "Reply failed"


def test_reply_text_mode(plugin):
    from hermes_iris.push.render import notice

    assert notice(REPLY, _settings(plugin, reply="text")) == {
        "event_id": "11", "kind": "reply", "session_id": SID, "title": "Look!", "body": None,
        "category": None, "collapse": f"reply-{SID}",
    }


def test_approval_content(plugin):
    from hermes_iris.push.render import notice

    assert notice(APPROVAL, _settings(plugin, approval="content")) == {
        "event_id": "13", "kind": "approval", "session_id": SID, "title": "Look!", "body": "rm -rf /tmp/x",
        "category": "approval", "collapse": f"approval-{SID}",
    }


def test_approval_text_mode_keeps_category(plugin):
    from hermes_iris.push.render import notice

    n = notice(APPROVAL, _settings(plugin, approval="text"))
    assert n["body"] is None and n["category"] == "approval"


def test_approval_done_ignores_settings(plugin):
    from hermes_iris.push.render import notice

    s = _settings(plugin, approval="text")
    s["approval"]["on"] = False
    assert notice(DONE, s) == {"event_id": "14", "kind": "approval_done", "session_id": SID,
                               "collapse": f"approval-{SID}"}


def test_job_content(plugin):
    from hermes_iris.push.render import notice

    n = notice(JOB, _settings(plugin, job="content"))
    assert n == {"event_id": "15", "kind": "job", "session_id": CRON, "title": "Look!",
                 "body": "Daily plan finished", "category": None, "collapse": f"job-{CRON}"}
    assert notice(JOB_EMPTY, _settings(plugin, job="content"))["body"] == "Daily plan produced no output"


def test_job_text_mode(plugin):
    from hermes_iris.push.render import notice

    assert notice(JOB, _settings(plugin, job="text"))["body"] is None


def test_text_mode_leaks_no_content(plugin):
    from hermes_iris.push.render import notice

    secret = {
        "reply": {**REPLY, "preview": "SECRETPREVIEW", "title": "SECRETTITLE"},
        "approval": {**APPROVAL, "command": "SECRETCOMMAND", "description": "SECRETDESC", "title": "SECRETTITLE"},
        "job": {**JOB, "job_name": "SECRETJOB", "job_id": "SECRETJOBID"},
    }
    for kind, event in secret.items():
        out = json.dumps(notice(event, _settings(plugin, **{kind: "text"})), ensure_ascii=False)
        assert "SECRET" not in out, kind
        for key in ("preview", "command", "job_name", "description"):
            assert key not in out


def test_kind_off_renders_none(plugin):
    from hermes_iris.push.render import notice

    for event in (REPLY, FAILED, APPROVAL, JOB):
        s = _settings(plugin)
        s[event["kind"]]["on"] = False
        assert notice(event, s) is None


def test_unknown_kind_renders_none(plugin):
    from hermes_iris.push.render import notice

    assert notice({"id": "1", "kind": "wat", "session_id": SID}, _settings(plugin)) is None
