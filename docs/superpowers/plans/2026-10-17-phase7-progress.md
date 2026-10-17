# Phase 7 progress log

Run book: `2026-10-17-phase7-run.md`. Plan: `2026-10-17-phase7.md`. Branch: `feat/phase7-tabs`.
Update the table when a status changes; append journal entries at the bottom, newest last.

## Status

| Task | Title | Segment | Model | Status | Last commit |
|---|---|---|---|---|---|
| 0 | Probe the user's server | S1 | Sonnet | done | b18907b |
| 1 | Data layer: models and three repositories | S1 | Sonnet | done | 07bd709 |
| 2 | Providers, polling and test fakes | S1 | Sonnet | todo | |
| 3 | `IrisSegmented` | S1 | Sonnet | todo | |
| 4 | Job form | S1 | Sonnet | todo | |
| 5 | Scheduled tab, job detail, delete | S1 | Sonnet | todo | |
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
