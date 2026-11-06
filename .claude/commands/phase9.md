---
description: Run or resume the next Phase 9 subphase (starts with GenUI) from its progress log
---

Work on Phase 9 for Iris, following the run book exactly.

1. Read `docs/superpowers/plans/2026-11-06-phase9-run.md` in full, then
   `docs/superpowers/plans/2026-11-06-phase9-progress.md`. Read the current subphase's plan header only (for 9.1:
   `docs/superpowers/plans/2026-10-31-genui.md`, Global Constraints and file map).
2. Follow "Starting or resuming a chat" in the run book: find the first row that is not `done`, check the branch and git
   against the log, and check that the model you are running as is not lower than the one that segment needs. If it is
   lower, stop and tell the user which model to switch to; do not edit code.
3. If the next row is a Spec stage, invoke `superpowers:brainstorming` and do not write product code. If it is a Plan
   stage, invoke `superpowers:writing-plans`. Otherwise carry on task by task, logging after each one, until the next
   segment boundary or a blocker. Then stop and say what the run book tells you to say.

$ARGUMENTS
