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
| 6 | Move sheet and New task form | S1 | Sonnet | todo | |
| 7 | Board, task cards, task detail | S1 | Sonnet | todo | |
| 8 | Home tab host | S1 | Sonnet | todo | |
| 9 | ⋯ menu and Session info | S1 | Sonnet | todo | |
| 10 | Export as Markdown | S1 | Sonnet | todo | |
| 11 | Profiles | S1 | Sonnet | todo | |
| 12 | Cross-profile search | S2 | Opus | todo | |
| 13 | Demo data | S3 | Sonnet | todo | |
| 14 | Goldens, changelog, README | S3 | Sonnet | todo | |
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
