# Push notifications: live probe findings (Task 1)

Probed 2026-11-13 against the user's Hermes (checkout `0e427d788d`, newer than the tag the plan read; the approval
and turn-finalizer code matches). Temporary hooks logged `{hook, pid, kwargs minus message bodies}` to
`~/.hermes/iris/probe-push.jsonl`; client side is `test/live/push_probe_live_test.dart`.

## Server facts that change the plan

1. **`approvals.mode` is `smart` on this server.** A guardian model judges each flagged command first. Its
   `pre_approval_request` fires with `surface: "smart"`, and on APPROVE `post_approval_response` follows with
   `choice: "smart_approve"`, `decided_by: "aux_llm"`. Nobody is asked. Only a guardian DENY (owner may override) or
   ESCALATE reaches a person, and that ask fires a **second** `pre_approval_request` with `surface: "gateway"` (2.6 s
   later in the probe). **Task 4: notify only when `surface != "smart"`.** Example: `rm -rf /tmp/x` was approved
   silently; `curl -s http://… | sh` was put to a person.
2. **The dashboard asks with a server request, not an event.** The approval reaches the client as a JSON-RPC request
   `method: "approval"` (`DashboardSession.serverRequests`), params `session_id, command, pattern_key, pattern_keys,
   description, allow_permanent, allow_session, request_id, choices` (`[once, session, always, deny]`). There is no
   `approval.request` event. Iris's chat screen already handles this; the plan's wording "`approval.request`" means
   this request.
3. **`on_session_end` fires once per dashboard turn** (the first run's "it doesn't" was an artefact of the model
   failing every turn). Task 4 stays on `on_session_end`; the `post_llm_call` change considered earlier is not needed.

## (a) session key

`pre_approval_request.session_key` == `session_id` == the dashboard chat's **stored** id (e.g.
`20261113_051659_b9bbb3`), not the runtime id. Approval rows also carry `turn_id`
(`<stored>:<stored>:<8 hex>`) and `tool_call_id`.

## (b) process

Every hook ran in pid 3094032 for dashboard chats, and a fresh pid per cron run (3324273, 3695430, …). The plugin's
dashboard routes run in the dashboard service's main process. As planned, hooks and routes share only files under
`<iris_root>`.

## (c) turn and cron `on_session_end`

Dashboard turn end:

```
session_id, task_id (= session_id), turn_id, completed, failed, interrupted,
turn_exit_reason ("text_response(finish_reason=stop)"), model, platform: "desktop", telemetry_schema_version
```

Closing or deleting the chat fires another `on_session_end` with **no `turn_id`**, `completed: false`,
`interrupted: true`. Task 4 must ignore rows without `turn_id`, or a closed chat looks like an interrupted reply.

Cron run end (two real scheduled runs):

```
session_id: "cron_<job id>_<YYYYMMDD_HHMMSS>", task_id: "cron:<job id>:<run uuid hex>",
turn_id, completed, failed, interrupted, turn_exit_reason, model, platform: "cron"
```

The job id is the second `:` field of `task_id` (or the middle of `session_id`). The name is not in the hook
payload. Read it from `<hermes home>/cron/jobs.json`, a dict whose `jobs` is a list of records with `id`, `name`,
`deliver`, `last_status`, `last_error`, `state`, … (e.g. `8ef733a147c7` → `daily-approved-plan`). A failed cron run
was not observed; `failed`/`completed: false` are the fields to read.

The probe's own one-off cron job could not be created: `POST /api/cron/jobs` timed out at 12 s with the server at
load ≈ 10. No probe job was left behind (checked `jobs.json`).

## (d) answering after a reconnect

Raised the approval, disposed the socket, opened a fresh `DashboardSession`, `session.resume`d the stored id (same
runtime id came back). The `approval` server request was **not** re-sent on the new socket within 3 s.
`approval.pending {session_id: <runtime id>}` returned `{approvals: [{command, pattern_key, pattern_keys,
description, allow_permanent, allow_session, request_id}]}`. `approval.respond {choice: "deny", session_id,
request_id}` returned `{resolved: 1}`; the turn then ended with the reply "denied". **The plan's answer path works.**

Timeout: unanswered, the `gateway` ask ended at 300 s with `post_approval_response` `choice: "timeout"`, and the turn
then completed normally. A notification tap has to land within that window; Task 4's approval notification should
carry `expires_at = raised + 300 s`.

## (e) runtime libraries

Hermes's Python 3.14.7 runtime has `httpx` 0.28.1, `cryptography` 50.0.1 and `pyjwt` 2.13.0 once
`hermes_bootstrap` loads; **`h2` is not installed**. System `curl` 8.5.0 has HTTP/2 (nghttp2). APNs needs HTTP/2, so
Task 6 needs the user's call: system `curl` or installing `h2`. **User's call (2026-11-13): system `curl`.**
Nothing is installed; Task 6 is amended to match.
