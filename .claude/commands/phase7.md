---
description: Run or resume the Phase 7 implementation plan from its progress log
---

Execute the Phase 7 plan for Iris, following the run book exactly.

1. Read `docs/superpowers/plans/2026-10-17-phase7-run.md` in full, then
   `docs/superpowers/plans/2026-10-17-phase7-progress.md`, then the header of
   `docs/superpowers/plans/2026-10-17-phase7.md` (Global Constraints, Review Focus, file map).
2. Follow "Starting or resuming a chat" in the run book: check the branch and git against the log, find the first task
   that is not `done`, and check that the model you are running as is not lower than the one its segment needs. If it
   is lower, stop and tell the user which model to switch to; do not edit code.
3. Otherwise carry on task by task, logging after each one, until the next segment boundary or a blocker. Then stop and
   say what the run book tells you to say.

$ARGUMENTS
