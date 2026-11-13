---
description: On the Mac, complete every deferred iOS task in one run (reads docs/superpowers/plans/ios-deferred.md)
---

You are on the user's Mac. Complete all deferred iOS work in one run.

1. Read `docs/superpowers/plans/ios-deferred.md` in full, then the tail of `docs/superpowers/plans/2026-11-06-phase9-progress.md`.
2. Say what you found: which items are `todo`, their branches, and whether the model you run as meets the file's minimum
   (Sonnet; Opus for design-changing Swift fixes). If lower, stop and tell the user which model to switch to.
3. Check `git status -sb`. Check out each item's branch (ask before discarding or stashing anything). Run the setup.
4. Do the items in order, task by task: run the stated commands, fix failures (test first where Dart is involved), commit
   under the user's name only (no `Co-Authored-By`, no `Claude-Session` line; add files by name; never `git add -A`).
   Where an item needs the user (iPhone in hand, a key placed on the server, a tap), say exactly what to do and wait.
5. After each item, set it to `done` in `ios-deferred.md` with a one-line result and the commit sha, add a journal
   entry in the Phase 9 progress log, and commit. Never record a step as done unless its command ran and held.
6. Work inline; no subagents. Stop at the end of the list and summarise what passed, failed, and is still open.

$ARGUMENTS
