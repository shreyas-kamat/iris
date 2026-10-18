# Phase 7 probe note

Run 2026-10-17 against the user's server with `test/live/phase7_probe_live_test.dart` (read-only; writes use ids or
names that cannot exist). A bare `404` on a write means the route is missing; a `404` naming a job, task or profile
means the route exists.

## Results

| Call | Result |
|---|---|
| GET cron jobs | ok list(5) |
| GET delivery targets | ok object{targets} |
| PUT cron job (bogus id) | rejected 422 "" |
| POST cron pause (bogus id) | notFound 404 "Job not found" |
| POST cron resume (bogus id) | notFound 404 "Job not found" |
| POST cron trigger (bogus id) | notFound 404 "Job not found" |
| GET cron runs (bogus id) | ok object{runs,limit} |
| DELETE cron job (bogus id) | notFound 404 "Job not found" |
| GET kanban board | ok object{columns,tenants,assignees,latest_event_id,now} |
| GET kanban task detail | not read: no task on the board |
| PATCH kanban task (bogus id) | notFound 404 "task iris-probe not found" |
| GET profiles | ok object{profiles} |
| POST profile (invalid name) | rejected 400, name validation message |
| POST profile (invalid name, clone_from) | rejected 400, name validation message |
| POST profile (invalid name, clone_all) | rejected 400, name validation message |
| POST profile (invalid name, no_skills) | rejected 400, name validation message |
| PATCH profile (bogus name) | notFound 404 "No profile named 'iris-probe'" |
| GET profile soul (default) | ok object{content,exists} |
| DELETE profile (bogus name) | notFound 404 "No profile named 'iris-probe'" |
| GET search, no profile | ok object{results} |
| GET search, profile=default | ok object{results} |

Search hit keys: snippet, role, source, model, session_started, last_active, session_id, lineage_root, profile,
is_default_profile, id, title, started_at, ended_at, is_active, message_count, tool_call_count, input_tokens,
output_tokens, preview, parent_session_id, archived. Profiles seen in an unscoped search: `default` only.

## Decisions

| Question | Answer | What changes |
|---|---|---|
| Cron list, delivery targets, runs present? | yes, all three | Scheduled tab stays; the form offers Deliver to. |
| Cron PUT/pause/resume/trigger/DELETE present? | yes for all five (PUT answered 422 to a bare body, so the route exists and validates) | No control is disabled for a missing route. |
| Kanban board and detail present? | board yes; detail not confirmed (the board was empty, so no task id to read) | Tasks tab stays. Task detail keys are unverified; Task 1 must parse tolerantly. |
| Does a task carry a session link, and under which key? | unknown: the board has no tasks | Task 7 builds no Open session button until a real task shows a key. Revisit in Task 15 if it creates a task. |
| Kanban PATCH (move) present? | yes (404 names the task) | Move rows stay enabled. |
| Profile create/rename/soul/delete present? | yes for all four | No profile control is hidden. |
| Were `clone_from`, `clone_all`, `no_skills` accepted? | not proven: each answered with the name error, which comes before any field check, so an ignored field would look the same. `clone_from_default` was not probed. | All Start from options stay for now. Task 15's live write test must create a throwaway profile with each option and check it was really copied (skills or memory present), then delete it. |
| Does an unscoped search return hits from every profile (do hits carry a `profile`)? | hits carry `profile` and `is_default_profile`; only `default` was seen, so merging is unconfirmed | Task 12 uses one search per profile, as planned. |
