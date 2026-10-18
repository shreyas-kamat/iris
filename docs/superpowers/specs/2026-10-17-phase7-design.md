# Phase 7 — Scheduled, Tasks, the chat ⋯ menu, profiles and cross-profile search

**Date:** 2026-10-17. **Branch:** `feat/phase7-tabs`, cut from `main` at `07e8985`.
Builds on Phase 6 (`2026-10-16-phase6-design.md`).
**Design:** the claude.ai/design project "Iris Chat App Design", file `Iris Phase 3.dc.html`, checked in at
`design/Iris Phase 3.dc.html` (frames A1–A6, A2·L, B1–B5, B1·B, B1·L, B1·320, B2·N, C1, C1·B, C2, C3, D1–D5, D1·L).
It is the source of truth for sizes, radii, springs, copy and states. This spec says what each frame needs from the code
and where the code differs from the design. It does not repeat the design's numbers.

## Goals

What Hermes does while you are away, and the menus and profile tools around it.

1. **Home tabs.** A Sessions | Scheduled | Tasks segmented control on home (A1).
2. **Scheduled.** List, pause/resume, run now, past runs, create, edit and delete cron jobs (A2–A6).
3. **Tasks.** The Kanban plugin's board: browse by column, open a task, move it, create one (B1–B5).
4. **The chat ⋯ menu.** The existing row actions plus Export, Session info, Compress and Undo (C1–C3).
5. **Profiles.** Create, rename, edit the SOUL, and delete profiles (D1–D4).
6. **Cross-profile search.** A "This profile | All profiles" scope on home search (D5).

## Decisions

Made by the user on 2026-10-17:

- **One phase, one branch, one spec, one plan, one PR, one device pass**, built in slices so the branch can be cut after
  Tasks if it runs long.
- **Scheduled is full management:** list, pause/resume, run now, past runs, create, edit, delete.
- **Tasks is board + move + create:** column browsing, detail, moving a card, creating a card. No edit, delete,
  assign-after-creation, comments, attachments or boards admin.
- **The ⋯ menu carries all four groups:** the home long-press actions, Export, Session info, Compress and Undo.
- **Profiles are create + rename + SOUL + delete.** A profile has no editable model: the model is read from its config.
- **Design comes from the Phase 3 file.** Where the code has no matching part, the screen is built from existing
  components, as the frame notes name them.
- **15 s polling** while a tab is visible. No Kanban event stream.

Made while writing the spec (change any of them by saying so):

- **A tab is offered only when the probe confirmed its capability** (`ServerCapabilities.confirmed`). With neither
  confirmed, home looks as it does today and no control is drawn. This is frame B2·N.
- **Tasks uses the server's current board.** There is no board switcher; the `board` query parameter is never sent.
- **The tab choice lasts for the app session.** A cold start opens on Sessions.
- **Demo mode reports both capabilities** and carries sample jobs, tasks and profiles so a reviewer sees every new
  screen. Demo writes change in-memory state only.
- **Export is Markdown through the system share sheet**, which needs one new dependency (`share_plus`).

## Verified in the Hermes source (upstream `main`, read 2026-10-17)

Not yet probed on the user's server (0.18.2); task 0 does that. Everything below is REST, so no new RPC plumbing.

| Area | Wire |
|---|---|
| Cron list | `GET /api/cron/jobs[?profile=]` |
| Cron write | `POST /api/cron/jobs {prompt, schedule, name?, model?, provider?, deliver?, repeat?}`; `PUT /api/cron/jobs/{id}` with any of `{name, prompt, schedule, enabled, model, provider, deliver}` |
| Cron actions | `POST /api/cron/jobs/{id}/pause`, `/resume`, `/trigger`; `DELETE /api/cron/jobs/{id}` |
| Cron runs | `GET /api/cron/jobs/{id}/runs?limit=` returns sessions (the same row shape as session rows) |
| Delivery targets | `GET /api/cron/delivery-targets` → `[{id, name, home_env_var, home_target_set}]` |
| Job shape | `{id, name?, prompt?, schedule: {kind, expr, display}, schedule_display?, enabled, state?, next_run_at?, last_run_at?, last_error?, model?, provider?, deliver?}` |
| Schedules | Hermes parses them: `30m`, `every 2h`, `every monday 9am`, 5-field cron, or an ISO date. Iris sends the text as typed |
| Kanban board | `GET /api/plugins/kanban/board` → `{columns: [{name, tasks: [KanbanTask]}], assignees, now, …}` |
| Kanban task | `GET /api/plugins/kanban/tasks/{id}` → `{task, comments, events, links: {parents, children}, link_tasks?, runs, attachments?}` |
| Kanban write | `POST /tasks {title, body?, status?, assignee?, priority?}`; `PATCH /tasks/{id} {status: …}` moves a card |
| Locked columns | `review`, `running`, `scheduled` are set by Hermes; a person does not move a card into them |
| Profiles | `GET /api/profiles`; `POST /api/profiles {name, soul?, clone_from?, clone_all?, no_skills?}`; `PATCH /api/profiles/{name} {new_name}`; `DELETE /api/profiles/{name}` (default refused); `GET`/`PUT /api/profiles/{name}/soul` |
| Search | `GET /api/sessions/search?q=&limit=[&profile=]`; each hit has `session_id, title?, snippet, source?, model?, last_active?, lineage_root?` |

A task's columns are the ids `triage, todo, ready, running, blocked, review, done`; an unknown column from a newer
server is shown by its name and treated as system-set.

## Design

### Data layer

New repositories under `lib/data/automation/`, each taking the existing `ApiClient` and returning `Result`. They follow
`ChatBackend`'s rule that the profile goes in the query (`profile`) and, for writes that name a body, in the body.
`ApiClient` gains `put` beside `patch`; nothing else about it changes.

| Repository | Methods |
|---|---|
| `CronRepository` | `jobs()`, `job(id)`, `runs(id)`, `deliveryTargets()`, `create(JobDraft)`, `update(id, JobDraft)`, `setEnabled(id, bool)` (pause or resume), `trigger(id)`, `delete(id)` |
| `KanbanRepository` | `board()`, `task(id)`, `create(TaskDraft)`, `move(id, column)` |
| `ProfileRepository` | `list()`, `create(ProfileDraft)`, `rename(name, newName)`, `soul(name)`, `setSoul(name, text)`, `delete(name)` |

- **Models.** `CronJob` is rewritten against the real shape (`enabled`, `schedule.expr/display`, `last_error`,
  `next_run_at`, `last_run_at`); the forgiving `json.any` parsing stays. `CronOutput` is removed, since runs are
  sessions. New: `JobDraft`, `CronRun` (a session row), `DeliveryTarget`, `KanbanBoard`, `KanbanColumn`, `KanbanTask`,
  `KanbanTaskDetail`, `TaskDraft`, `ProfileDraft`, `BlockKind`. Unknown values are kept as strings and rendered
  verbatim, never dropped.
- **Providers.** `cronJobsProvider`, `kanbanBoardProvider` and `profileListProvider` are profile-scoped, autoDispose,
  and refreshed every 15 s while their tab or screen is visible and the app is foregrounded. They pause when hidden
  (see `riverpod3-paused-providers`: tests listen before awaiting `.future`). Each write invalidates its list.
- **Optimistic writes.** The enable switch and Move apply immediately and roll back with a toast naming the failure.
- **Missing endpoints.** A 404 on a write gives "Not supported on this server". A 404 on a list hides its tab, the same
  way the probe would have.
- **Search.** `ChatBackend.search` gains an `allProfiles` flag. If an unscoped call merges profiles, Iris uses it. If
  the server answers for the default profile only, Iris searches every profile from `profileListProvider`, merges by
  `last_active`, and labels each hit with its profile. Task 0 decides which.
- **Session info** needs no new call: it reads the resumed `info` and `usage` the chat already holds.
- **Export.** The transcript is rendered to Markdown from the loaded messages (user and assistant text, tool calls as a
  one-line note), written to a temp file, and handed to `share_plus`. Pages not yet loaded are fetched first, with a
  "Preparing…" state.

### Behaviour

**Home tabs (A1, B2·N).** The segmented control sits right under the header, in the greeting's old place, and is the
same on every tab. Sessions keeps the usage strip, search and Live/Earlier. The Ask bar stays on all tabs. Two tabs show
two equal segments; three show three. `IrisSegmented<T>` is a new component, extracted from the effort track in
`model_sheet.dart` (which switches to it); the thumb slides with a spring and snaps under reduced motion, and wraps at
large text sizes as the effort track does today.

**Scheduled list (A2, A3).** One card per job: the name (else the first line of the prompt), the schedule verbatim in a
mono chip (`schedule.display` if present, else `schedule.expr`; never translated), and a status line: "next in 9h 12m",
"paused", "running…" with the tool orb, or "failed 2h ago" in the failed colour from `last_error`. The switch pauses or
resumes. Pull-to-refresh uses the loading orb. Empty: "No scheduled jobs on {profile}" with New job.

**Job detail (A4).** Opened from a card. Shows the status, the Enabled switch, Last error (only when set), the full
prompt, Model and Delivers to (only when set), then Run now, Edit and Delete. Run now calls `/trigger`, shows "Started",
and the run appears in Past runs on the next refresh. Past runs are `runs(id)` rows; tapping one opens that chat like
any stored session.

**Job form (A5, A5·E).** Name (optional), Schedule (required, with the hint line), Prompt (required, multi-line), Model
(opens the model sheet; "Profile default" when unset), Deliver to (a picker over the delivery targets, hidden when the
call fails or returns none). Save is disabled until Schedule and Prompt are non-empty. A server rejection is shown
verbatim under Schedule with the failed border and focus returns there. Cancel with unsaved changes asks first.

**Delete job (A6).** The existing centred confirm, unchanged. Past runs' chats stay.

**Board (B1, B1·B, B1·L, B1·320).** A row of column chips with counts, then the selected column's cards. The first
non-empty column is selected on open. A card shows the title, the id, and only the fields the server sent: assignee,
priority as `pN`, `latest_summary`, comment count, warning count. Running cards show the tool orb and a mono elapsed
clock from `started_at`; "n of m subtasks" appears only when `progress` is sent. Blocked cards show `block_kind`
verbatim as a chip ("needs input" uses the needs-you colour, the others the neutral chip). No percentage bars and no
due dates. System-set columns are labelled "Set by Hermes".

**Empty column (B2).** "Nothing in {Column}". System-set columns say Hermes moves tasks there and show no New task.
Person-movable columns keep New task.

**Task detail (B3).** Title, status pill, assignee, priority, body (Markdown), latest summary, result, last failure,
subtasks, parent link, read-only comments and runs. Move and, only when the task links to a session, Open session.
Subtasks and the parent link open their own detail.

**Move (B4).** A sheet listing the columns. The current one is checked. `running`, `review` and `scheduled` are locked
and do not respond to taps. The move is optimistic; a refusal rolls back with the server's message.

**New task (B5).** Title (required), Body (optional Markdown), Column (Triage | To do), Assignee (optional, a profile
picker), Priority (optional stepper). Create stays disabled until there is a title. The new card appears in its column
and the board refreshes.

**⋯ menu (C1, C1·B, C2, C3).** The chat header's ⋯ opens one sheet in five groups:
Conversation (Rename, Pin/Unpin, Branch, Archive), Context (Compress, Undo last turn), Share (Export as Markdown),
Info (Session info), then Delete last. It is the Phase 6 conversation sheet extended; the home long-press keeps its own
smaller list. While the agent replies, Undo, Compress, Branch, Archive and Delete are dimmed with a one-line reason
instead of hidden. Delete from inside a chat ends on home, with the usual confirm. Rename is the existing sheet (C2).
Session info (C3) lists profile, model, created, last active, message count, tokens in/out, context %, and the session
id with a Copy button ("Copied session id"). Rows with no data are left out.

**Profiles (D1–D4).** Settings gains a Profiles row. The list shows each profile with its model (read-only, mono) and a
Default tag. The current profile has a check; tapping the check switches to that profile (its own 44 pt target), and
tapping the row opens Edit.
- *New (D2):* the name validates as you type (lowercase letters, digits, `-`, `_`). Start from is Blank, Copy of
  {profile} (config and skills) or Full copy of {profile} (also memory and sessions). SOUL is optional.
  Create stays disabled while the name is invalid.
- *Edit (D3):* Name, Model (read-only), SOUL with a Monospace switch, and Delete. The default profile shows its name as
  text and has no Delete. Save sends only what changed: a rename, a SOUL write, or both.
- *Delete (D4):* the user types the profile name; Delete stays disabled until it matches exactly. Deleting the current
  profile switches to the default first. Autocorrect is off.

**Cross-profile search (D5).** The scope control appears under the search field while it has focus or text. "This
profile" is the default and resets when search closes. "All profiles" groups results under profile headers; a hit under
another profile switches to it first (the pill updates) and then opens the chat. The footer note says which profiles were
searched.

### UI

The design supplies the geometry. New and changed components:

| Frame | Component |
|---|---|
| A1, B2·N | `IrisSegmented<T>`, the tab host in `conversation_list_screen.dart` (header and switch only) |
| A2, A3 | `ScheduledTab`, `JobCard` |
| A4–A6 | `JobDetailScreen`, `JobFormScreen`, the delete confirm reused from Phase 6 |
| B1–B2 | `TasksTab`, `ColumnChips`, `TaskCard`, `BlockKindChip` |
| B3–B5 | `TaskDetailScreen`, `MoveSheet`, `TaskFormScreen` |
| C1–C3 | `ChatMenuSheet` (extends `conversation_actions.dart`), `SessionInfoSheet`, the Markdown exporter |
| D1–D4 | `ProfilesScreen`, `ProfileFormScreen`, `DeleteProfileSheet` |
| D5 | the scope control in `conversation_search.dart`, profile section headers |

New screens live under `lib/features/scheduled/`, `lib/features/tasks/` and `lib/features/profiles/`.
`conversation_list_screen.dart` (already 1,487 lines) only gains the header and the tab switch; the Sessions body is not
refactored.

- Every colour is a palette role or an `AgentState` colour; no widget holds a design hex value. Contrast tests are never
  loosened.
- Light variants are required for Scheduled, the board and Profiles (A2·L, B1·L, D1·L).
- Reduced motion has an instant or cross-fade alternative for every new animation. Under `disableAnimations` no new
  ticker runs.
- 44 pt targets, and no overflow at 320 pt wide (B1·320) or 200% text, for every new surface.

## Design and wire differences

| The design shows | Iris does |
|---|---|
| B3 "Open session" | Only if the task detail carries a session link. If the wire has none (task 0), the button is not built |
| D2 "Blank / Copy / Full copy" | Maps to `no_skills`, `clone_from`, `clone_all`. If task 0 shows the server rejects them, the options it rejects are hidden |
| D5 "All profiles" | Uses the server's merged search if there is one, else one search per profile (above) |
| C1 "Archive" | Uses the Phase 6 archive action; hidden for an already-archived chat |
| D1 profile "model" | Read from `GET /api/profiles`. Shown only when the server sends it |
| A4 "next in 21h 40m" | Computed from `next_run_at` and the device clock |
| A2 "REFRESHING" | The loading orb during a pull or a poll that takes longer than 600 ms |

## Platform and release

One new dependency, `share_plus`, for Export. No new permissions on either platform. The privacy policy and
`docs/release.md` need no change, because Export only shares text the user chose to share. The CHANGELOG and the README
feature list get the new features.

## Testing

- **Task 0, a read-only probe of the user's server:** `GET` the cron list, delivery targets, kanban board, profiles and
  an unscoped search; record each as present or "not found". Write calls use an id that does not exist
  (`PUT`/`DELETE /api/cron/jobs/x`, `PATCH /api/plugins/kanban/tasks/x`, `POST /api/profiles` with an invalid name) and
  record which answer "not found" for the route versus a validation error. Also record whether a task detail carries
  a session link, whether an unscoped search merges profiles, and whether `clone_from`/`clone_all`/`no_skills` are
  accepted. The result is recorded in the plan.
- **Unit tests:** every repository call (fake HTTP); the job, task and profile parsers including unknown values; the
  draft builders (a profile name validator, a schedule field's server-error mapping); the Markdown exporter; the
  merged search; optimistic rollback for the switch and Move.
- **Widget tests:** the segmented control (two and three segments, reduced motion); each tab's loading, empty, error and
  data states; the job form and its server error; the Move sheet's locked rows; the ⋯ menu idle and replying; Session
  info; the profile forms including the type-to-confirm delete; the scope control; 320 pt and 200% text reflow of each
  new surface.
- **Goldens:** home Scheduled, the board, the ⋯ menu and the Profiles list, each in dark and light. Existing goldens are
  regenerated only where the model sheet's effort track changes, and each change is looked at.
- **Live write test:** against the real server, using a throwaway profile: create it, create a cron job in it, pause and
  resume it, trigger it, delete the job; create a task and move it between Triage and To do; rename the profile and
  delete it. Agent runs are slow, so "trigger" waits at least 240 s for its run row. Nothing touches the default profile.
- **Demo backend:** gains the sample jobs (four, one of each state), tasks across the seven columns (including a Blocked
  one with each `block_kind`), and three profiles, so the device pass sees every screen.
- **Device pass:** one pass on the Pixel 9 emulator with a release APK, recorded in
  `docs/superpowers/plans/2026-10-17-phase7-device.md`. Cover each tab, creating and deleting a job, moving a task,
  the ⋯ menu including Export, creating and deleting a profile, cross-profile search, light and dark, 320 pt and
  reduced motion.

## Execution split

The plan will carry the final task list. This is the intended split of work across models, by how much judgement a
task needs. A task that fails its tests on the first model is retried on the next one up.

| Task | Model |
|---|---|
| 0 Probe the server | haiku |
| 1 Data layer: `ApiClient.put`, models, three repositories, providers with polling | sonnet |
| 2 `IrisSegmented` and the home tab host | sonnet |
| 3 Scheduled list, detail and the delete confirm | sonnet |
| 4 Job form, delivery picker, server-error mapping | sonnet |
| 5 Board, cards, column chips, empty states | sonnet |
| 6 Task detail, Move sheet, New task | sonnet |
| 7 ⋯ menu, Session info, Rename reuse | sonnet |
| 8 Markdown exporter and share | haiku |
| 9 Profiles list, forms, delete | sonnet |
| 10 Cross-profile search | opus |
| 11 Demo backend data | haiku |
| 12 Goldens, analyze, CHANGELOG and README | haiku |
| 13 Live write test | sonnet |
| 14 Device pass | sonnet |
| 15 Final review of the whole diff | opus |

Opus is for the cross-profile search (profile switching racing a result tap, a merge across profiles, and the
fall-back path) and for the final review.

## Out of scope

- Kanban: boards and a board switcher, editing or deleting tasks, comments, attachments, reassigning, bulk edits, worker
  logs, orchestration settings, the event stream.
- Cron: blueprints, the `repeat` count and the no-agent/script jobs.
- Profile avatars, bot mode, profile export/import, and a profile's model or provider (Settings rows for default model
  and approvals stay deferred from Phase 6).
- Notifications for finished jobs or tasks (Phase 8, with push).
- Live voice mode, push, offline cache, widgets, localisation (Phase 8).
