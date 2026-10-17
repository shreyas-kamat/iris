# Phase 7 progress log

Run book: `2026-10-17-phase7-run.md`. Plan: `2026-10-17-phase7.md`. Branch: `feat/phase7-tabs`.
Update the table when a status changes; append journal entries at the bottom, newest last.

## Status

| Task | Title | Segment | Model | Status | Last commit |
|---|---|---|---|---|---|
| 0 | Probe the user's server | S1 | Sonnet | done | b18907b |
| 1 | Data layer: models and three repositories | S1 | Sonnet | done | 07bd709 |
| 2 | Providers, polling and test fakes | S1 | Sonnet | done | 47d850a |
| 3 | `IrisSegmented` | S1 | Sonnet | done | 27b4f24 |
| 4 | Job form | S1 | Sonnet | done | 251b2e3 |
| 5 | Scheduled tab, job detail, delete | S1 | Sonnet | done | 3c74ba8 |
| 6 | Move sheet and New task form | S1 | Sonnet | done | 4a4636d |
| 7 | Board, task cards, task detail | S1 | Sonnet | done | 4572ff3 |
| 8 | Home tab host | S1 | Sonnet | done | 665b3a9 |
| 9 | ⋯ menu and Session info | S1 | Sonnet | done | 6cc2dca |
| 10 | Export as Markdown | S1 | Sonnet | done | 9a686b3 |
| 11 | Profiles | S1 | Sonnet | done | d586906 |
| 12 | Cross-profile search | S2 | Opus | done | 286a35e |
| 13 | Demo data | S3 | Sonnet | done | 54c5a0f |
| 14 | Goldens, changelog, README | S3 | Sonnet | done | 16547bf |
| 15 | Live write test | S3 | Sonnet | todo | |
| 16 | Device pass | S3 | Sonnet | todo | |
| 17 | Final review | S4 | Opus | todo | |

Segments: S1 tasks 0–11 Sonnet · S2 task 12 Opus · S3 tasks 13–16 Sonnet · S4 task 17 Opus.
Stop at every segment boundary and ask the user to continue in a new chat on the next model.

## Journal

### Setup — 2026-10-17
- Spec `d5836f9`, plan `0b32963`, run book and this log added on `feat/phase7-tabs` (cut from `main` at `07e8985`).
- Open items: none. Next: Task 0, Step 1.

### Task 0 — Probe the user's server — done — 2026-10-17 — Sonnet 5.5
- Commits: b18907b test(phase7): probe which routes the user's server has
- Verified: `flutter test test/data/api_client_test.dart` 10 passed (put test failed first, as expected); `flutter analyze` on the touched files clean; live probe passed and printed the results in [the probe note](2026-10-17-phase7-probe.md).
- Deviations: removed the unused `dart:convert` and `rpc_frame.dart` imports from the probe, as the plan allowed for the first; the second was unused too.
- Decisions for later tasks: every route exists (cron, kanban board/PATCH, profiles, soul). The kanban board was empty, so task detail keys and any session-link key are unknown: parse tolerantly and build no Open session button (Task 7) unless Task 15 finds a key. Hits carry `profile`; unscoped search showed only `default`, so Task 12 stays one search per profile.
- Next: Task 1, Step 1

### Task 1 — Data layer: models and three repositories — done — 2026-10-17 — Sonnet 5.5
- Commits: 07bd709 feat(phase7): cron, Kanban and profile repositories
- Verified: `flutter analyze` no issues; `flutter test test/data` 302 passed, including the three new repository test files (33 tests).
- Deviations: wrote the tests and code together, so there was no separate see-it-fail run (new files, the tests could not compile before). Added `import '../../core/failure.dart'` to the cron repository, as the plan said. Fixed two `use_null_aware_elements` lints in `kanban_models.dart` (`?name.stringOrNull`, and `?row['id'].stringOrNull: KanbanLink(...)` for the link map), an import-order lint, and an unused import in the cron test.
- Decisions for later tasks: `KanbanTask.sessionId` reads `session_id`/`stored_session_id` only; the probe found no task to confirm a key. `lib/data/models/cron_job.dart` is deleted.
- Next: Task 2, Step 1

### Task 2 — Providers, polling and test fakes — done — 2026-10-17 — Sonnet 5.5
- Commits: 47d850a feat(phase7): providers, polling and test fakes for the new tabs
- Verified: tests first: `flutter test test/app/automation_providers_test.dart` failed to compile (`deliveryTargetsProvider` undefined); after the providers, 10 passed. `flutter analyze` no issues.
- Deviations: added `// ignore: avoid_positional_boolean_parameters` on `CronEnabledOverrides.set` (the plan's tests call it positionally); removed the unused `flutter/widgets.dart` import from the test, as the plan allowed.
- Decisions for later tasks: none.
- Next: Task 3, Step 1

### Task 3 — `IrisSegmented` — done — 2026-10-17 — Sonnet 5.5
- Commits: 27b4f24 feat(phase7): IrisSegmented, and the effort track uses it
- Verified: `flutter test test/design/segmented_test.dart` failed to compile before the component, 7 passed after; `flutter analyze` no issues; `flutter test test/features/model_controls_test.dart test/design` 262 passed (no golden changed).
- Deviations: none.
- Decisions for later tasks: none.
- Next: Task 4, Step 1

### Task 4 — Job form — done — 2026-10-17 — Sonnet 5.5
- Commits: 251b2e3 feat(phase7): the new and edit job form
- Verified: `flutter test test/features/job_form_test.dart` failed to compile before the screen; with it, 8 of 9 passed, then 9 passed after the fix below. `flutter analyze` no issues; `flutter test test/design` plus the form tests 263 passed.
- Deviations: the plan's `late final String _initial = _signature();` is lazy, so the form's dirty check compared the text with itself and "Discard changes?" never showed. It is now assigned in `initState`. Also removed the unused `chat_models.dart` import, split the `options == null || !mounted` guard (a `use_build_context_synchronously` lint), and dropped a redundant default argument in the test.
- Decisions for later tasks: `IrisField` now takes `focusNode`. The plan's note about popping the only route did not bite (`themed()` handled it), so no host helper was added.
- Next: Task 5, Step 1

### Task 5 — Scheduled tab, job detail, delete — done — 2026-10-17 — Sonnet 5.5
- Commits: 3c74ba8 feat(phase7): the Scheduled tab, job detail and delete
- Verified: `schedule_text_test` failed to compile first, then 12 passed; `scheduled_test` failed to compile first, then 13 passed after the fixes below; `delete_flow_test` still passes with the new `message` parameter; `flutter analyze` no issues.
- Deviations: the plan's test fixture had two jobs ('a' and 'e') on the default schedule `0 7 * * *`, so `find.text('0 7 * * *')` found two; 'e' now has `every 5m`. The detail tests use a tall test surface (800x2400) because the detail list builds lazily and the Delete button and Past runs sat off screen. `IrisLabel` uppercases its text, so the "Past runs" and "Last error" finders use `bySemanticsLabel` (the plan's fallback); the "Last error" absence check would otherwise have passed vacuously. Two lint ignores/removals: `avoid_positional_boolean_parameters` on `toggleJob`'s `enabled`, an unused `sheet.dart` import. `dart format` was run on the new test file.
- Decisions for later tasks: `toggleJob`, `withOverride`, `statusOf`, `statusLine`, `durationText` exist as the plan says. `showDeleteSheet` takes an optional `message`. The `IrisPressable.semanticLabel`, `IrisOrb.glow`, and `clockProvider` the plan hedged on all exist.
- Next: Task 6, Step 1

### Task 6 — Move sheet and New task form — done — 2026-10-17 — Sonnet 5.5
- Commits: 4a4636d feat(phase7): the Move sheet and the New task form
- Verified: `move_sheet_test` failed to compile first; with both files, 12 of 13 tests passed, then 13 passed after the fix below. `flutter analyze` no issues.
- Deviations: the assignee sheet was empty in the test because `profilesProvider` was only read when the sheet opened (never watched, so not loaded). The form now `ref.watch(profilesProvider)` in `build` so the list is ready before the sheet asks for it.
- Decisions for later tasks: `showMoveSheet(context, task:, columns:)` returns the column id or null; `TaskFormScreen(initialColumn:)` pops `true` on create and invalidates `kanbanBoardProvider`.
- Next: Task 7, Step 1

### Task 7 — Board, task cards, task detail — done — 2026-10-17 — Sonnet 5.5
- Commits: 4572ff3 feat(phase7): the Tasks board, cards and task detail
- Verified: `tasks_test` failed to compile first; after the screens, 5 of 14 failed, then 14 passed after the fixes below. With `move_sheet_test` and `task_form_test` together, 27 passed. `flutter analyze` no issues.
- Deviations: (1) Real bug found by the 320 pt test: on a system-set column the header "Running · set by Hermes" label plus the New task button overflowed by 11 pt; the label is now in an `Expanded` so it wraps. (2) The task card's semantic label now includes the block kind ("needs input"), because the card's label hid the chip from screen readers. (3) Tests: the detail tests use a tall surface (the list builds lazily); chips are painted uppercase, so they are found as `NEEDS INPUT`/`DEPENDENCY`; the Move sheet's "Done" is found inside `IrisSheet` (the subtask row also says Done); the "Open session" test tears the first screen down before building the second (the cached detail was reused). (4) The refused-move test now also checks the rollback (the header chip still says Review, not Done). (5) Removed the unused `task_card.dart` import and an unused `type` local, as the plan allowed.
- Decisions for later tasks: `kanbanTaskDetailProvider` is in `automation_providers.dart`. No Open session button appears unless the task carries `session_id`/`stored_session_id` (the probe could not confirm a key). `TasksTab` and `ScheduledTab` are ready for Task 8's host.
- Next: Task 8, Step 1

### Task 8 — Home tab host — done — 2026-10-17 — Sonnet 5.5
- Commits: 665b3a9 feat(phase7): home gets Scheduled and Tasks tabs when the server has them
- Verified: `home_tabs_test` first run: 2 passed, 4 failed (no control yet); after the host, `home_tabs_test`, `conversation_list_screen_test`, `pinned_live_test`, `delete_flow_test` 57 passed. Whole suite `flutter test`: 1074 passed, 7 skipped. `flutter analyze` no issues.
- Deviations: none in behaviour. The `NotificationListener` block was moved into a local `sessions` by script and `dart format` re-indented it, so the diff of `conversation_list_screen.dart` is larger than the logic change.
- Decisions for later tasks: with tabs, the hero is not built and `_HomeBar` gets a fixed `collapse` of 1 (compact link shown). A server with no extra tab takes the unchanged old path.
- Next: Task 9, Step 1

### Task 9 — ⋯ menu and Session info — done — 2026-10-17 — Sonnet 5.5
- Commits: 6cc2dca feat(phase7): the chat menu and session info (export lands next)
- Verified: controller tests failed to compile first (`compress`/`rename` undefined), then 81 passed; menu and session-info tests failed to compile first, then 14 passed; `chat_menu_flow_test` 5 passed. Whole suite: 1098 passed, 7 skipped. `flutter analyze` no issues.
- Deviations: (1) Real bug in the plan's `rename`: with no previous title (null) a refused rename left the new title on screen. `ChatState.copyWith` gained `clearTitle` so the rollback can restore null. (2) The ⋯ button changes every chat header, so 16 existing goldens changed (14 `screen_chat_*`, 2 `screen_demo_chat_*`); I looked at the diff image (only the new circular button at the header's right and a small title shift) and regenerated them with `--update-goldens` on those two test files; they are in this commit. (3) Session info leaves the Messages row out when the conversation reports 0 (the summary default), rather than showing "0". (4) `_menuHooks` in home matches the long-press delete: no delete while the chat is replying, `Could not delete` toast. (5) The Delete flow test uses a tall surface (the last row is below a 600 pt viewport; the real sheet scrolls). (6) Reformatted new files with `dart format` but restored an accidental reformat of existing code in `chat_controller_test.dart` (the block is appended unformatted-as-plan).
- Decisions for later tasks: Export is a toast stub (`_export` in `chat_screen.dart`: "Export is coming in this phase"); Task 10 replaces it. The `connect_screen_test` failed twice in one full-suite run under load and passed alone and in the next full run (flaky, unrelated).
- Next: Task 10, Step 1

### Task 10 — Export as Markdown — done — 2026-10-17 — Sonnet 5.5
- Commits: 9a686b3 feat(phase7): export a conversation as Markdown
- Verified: `chat_export_test` failed to compile first, then 9 passed; `fullTranscript` tests failed to compile first, then (after one test fix below) the controller file passed 83; `chat_menu_flow_test` + `chat_export_test` 15 passed; whole suite 1110 passed, 7 skipped; `flutter analyze` no issues. The `share_plus` call (`SharePlus.instance.share(ShareParams(...))`) compiled as written against 13.3.1.
- Deviations: (1) `flutter pub add share_plus` wrote `^13.3.1`; the other dependencies are pinned exactly, so it is pinned `13.3.1`. (2) `flutter pub get` regenerated the macOS and Windows plugin registrants (tracked, adding only `share_plus`); they are committed here so the tree stays clean. (3) The "stops when an earlier page fails" test: the failed page leaves a plain "Could not load earlier messages" notice in the transcript, so the test compares only the `UserTurn` ids (the exporter drops plain notices, so the notice never reaches the Markdown). (4) `RegExp(r'[^a-z0-9]+')` became a non-raw string (a lint).
- Decisions for later tasks: a branched chat opened from `_branch`/`_openParent` keeps `shareMarkdown` but not the menu hooks (as the plan says).
- Next: Task 11, Step 1

### Task 11 — Profiles — done — 2026-10-17 — Sonnet 5.5
- Commits: d586906 feat(phase7): create, rename, edit and delete profiles
- Verified: `profiles_test` failed to compile first; after the screens 13 of 15 passed, then 15 passed after the fix below; the two new settings tests failed first (no row), then `profiles_test` + `settings_screen_test` 25 passed; whole suite then regenerated goldens (below) and `flutter test test/design` 254 passed; `flutter analyze` no issues. Last whole-suite run before the golden update: 1125 passed, 7 skipped, 2 settings goldens failing (the new row), now updated.
- Deviations: (1) Step 0 (the probe note): the note's "clone_* accepted" answer was weaker than it read: the invalid-name error comes before any field check, so an ignored field gives the same answer, and `clone_from_default` was never probed. Nothing was hidden; the probe note now says so and Task 15 must verify the options for real. (2) A real a11y gap: the "Switch to <name>" circle's semantics merged into the row's button, so a screen reader could not reach it on its own; it is now `Semantics(container: true, ...)`. (3) The Profiles row changes the Settings screen, so `screen_settings_dark.png` and `screen_settings_light.png` changed; I checked the image (only the new row) and regenerated them in this commit. (4) Removed an unused `primitives.dart` import.
- Decisions for later tasks: Task 12 reads `profilesProvider`; a deleted current profile already falls back to `default` in `ProfileFormScreen._delete`.
- Next: Task 12, Step 1 (segment S2, needs Opus)

### Segment S1 complete — 2026-10-17 — Sonnet 5.5
- Tasks 0–11 are done and committed. Next segment: S2, task 12 (cross-profile search), model **Opus**.
- Open items for later: Task 15 must verify `clone_from`, `clone_all`, `clone_from_default` against the real server (see the probe note); the kanban board was empty, so a task's detail keys and any session-link key are unconfirmed.
- Next: Task 12, Step 1 (start a new chat on Opus)

### Task 12 — Cross-profile search — done — 2026-10-17 — Opus 5.5
- Commits: 286a35e feat(phase7): search across profiles from home
- Verified: `search_merge_test` failed to compile first, then 4 passed; `chat_backend_test` + `search_merge_test` 65 passed (3 new `searchAcross` tests); `cross_profile_search_test` failed first (6 of 7: no scope bar), then 8 passed after the fixes below; with `conversation_list_screen_test` and `home_tabs_test` 58 passed; whole suite 1142 passed, 7 skipped (after the golden update below); `flutter analyze` no issues.
- Deviations: (1) The plan's test had `home(profiles: const [two.first])`, which does not compile (not a constant); `const` dropped. (2) Real a11y gap: the profile heading's label merged into the neighbouring semantics node, so `bySemanticsLabel('default')` found nothing and a screen reader would hear it run into the next row; the heading is now `Semantics(container: true, header: true, ...)`. (3) Added a guard the plan did not have, for Review Focus 6: while a tapped hit is switching profile, another hit tap is ignored (`_switchingProfile`), and if the active profile is no longer the target when the new backend resolves, nothing opens. New test "a second hit tapped while a profile switch builds is ignored" (tall surface: the second hit sat under the floating new-chat bar at 600 pt, so the first version of the test tapped nothing); it fails without the guard (ends on `default`) and passes with it. (4) The scope bar and the "Searching default only…" note change the home-search goldens: `screen_home_usage_search_dark.png` and `_light.png`; I checked the images (only the new bar and note) and regenerated them in this commit. (5) `use_null_aware_elements` lint: `name: ?result.valueOrNull` in `searchAcross`; dates in the new tests moved off day 1 (a redundant-argument lint). (6) The focus listener became `_onSearchFocus` with a `mounted` check at the top (it reads `ref`).
- Decisions for later tasks: `DemoChatBackend.searchAcross` merges `_world.search(name, query)` per profile, so Task 13's demo data needs hits in more than one profile for the demo to show the grouping. `SearchHit.profile` is only set by `searchAcross`; single-profile hits stay null.
- Next: Task 13, Step 1 (segment S3, Sonnet)

### Segment S2 complete — 2026-10-17 — Opus 5.5
- Task 12 is done and committed. Next segment: S3, tasks 13–16, model **Sonnet** (the current model, Opus, is higher; the run book says stop and ask once).
- Next: Task 13, Step 1

### Task 13 — doing — 2026-10-18 — Sonnet 5.5
- Started on Sonnet 5.5 (S3's model; branch and log agree with git). Next: Step 1.

### Task 13 — Demo data — done — 2026-10-18 — Sonnet 5.5
- Commits: 54c5a0f feat(phase7): the demo shows jobs, tasks and profiles
- Verified: `demo_automation_test` failed to compile first (no `DemoAutomation`); after the code, 1 of 10 failed (below), then `flutter test test/demo` 39 passed; `demo_flow_test` 8 passed after the fixes below; `flutter analyze` no issues; `test/demo test/features/demo_flow_test.dart test/app` and the demo golden file 85 passed. Whole suite before the golden update: 2 demo-home goldens failing (plus one knock-on `welcome, light` that passes alone).
- Deviations: (1) The plan's demo schedule check refused `every 2h` (its own test creates one); the `every` rule now also accepts a short unit (`every 2h`, `every 5m`), while `every blursday` is still refused. (2) The plan's flow test looked for `needs input`/`capability`; chips are painted uppercase (as in Task 7), so it finds `NEEDS INPUT`/`CAPABILITY`. (3) The existing "no server switcher" demo test tapped the hero's `demo.iris` text; with tabs the hero is not built (Task 8), so it taps the compact link by its `Connection…` semantics label. (4) The demo home now shows the Sessions/Scheduled/Tasks control, so `screen_demo_home_dark.png` and `_light.png` changed; I looked at the image (only the new control; the hero's gone as Task 8 intended) and regenerated them in this commit. (5) Removed an unused `result.dart` import and a needless `!` in the plan's test. (6) `dart format` touched unrelated files once; I restored them.
- Decisions for later tasks: the demo has 3 profiles (default, homelab, research); the demo world's profiles are now mutable per visit. Task 14 should expect the demo home goldens to be already updated.
- Next: Task 14, Step 1

### Task 14 — doing — 2026-10-18
- Started on Sonnet 5.5. Next: Step 1.

### Task 14 — Goldens, changelog, README — done — 2026-10-18 — Sonnet 5.5
- Commits: 16547bf test(phase7): goldens for the new screens, and the changelog
- Verified: first generation: 4 of 38 tests failed (below), then `flutter test test/design/screens_golden_test.dart --update-goldens` 38 passed; `flutter test test/design` 262 passed; `flutter analyze` no issues; whole suite 1163 passed, 7 skipped. `git status` showed only the 8 new PNGs as new, no existing `screen_*.png` modified (the demo-home ones were already updated in Task 13). I looked at the dark Scheduled, Tasks, chat-menu and Profiles images and the light Tasks image: the control sits under the header, schedule chips are mono, the switch is on the right, the failed job's line is in the failed colour, the Running cards show the orb and clock, nothing overflows. I did not open the design HTML side by side, so frame-for-frame fidelity to A2/B1/C1/D1 is an eyeball check only.
- Deviations: (1) `_sharedOverrides` already overrides `profilesProvider`, so the plan's Profiles capture overrode it twice and failed; `_sharedOverrides` now takes an optional `profiles`. (2) The Tasks capture could not find the Running chip after a 400 ms pump (the polled board had not arrived); the `after` steps use the file's `settle` instead. (3) Import order and one redundant-argument lint fixed. (4) README: three bullets (Scheduled and Tasks, Chat menu, an extended Profiles bullet) instead of four; search-across-profiles went into the Profiles bullet.
- Decisions for later tasks: none.
- Next: Task 15, Step 1 (needs the user's yes first: it writes to the real server)
