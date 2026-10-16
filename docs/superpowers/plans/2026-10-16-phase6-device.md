# Phase 6 device pass

## Live write test — 2026-10-16

`flutter test --tags live_write --run-skipped test/live/phase6_write_live_test.dart` against the user's Hermes
(passed, 22 s: replies were fast this time, not the 95-160 s the plan expected).

```
first turn -> done
busy mode -> interrupt
queued submit -> queued
undo -> removed 2
branchWhole -> ok
active sessions -> 4
delete while live -> accepted
cleanup -> deleted
cleanup -> deleted
```

Findings:
- The server's busy mode is `interrupt`; the test set it to queue and restored it.
- A `queued: true` submit while a turn ran answered `queued`, and both turns completed.
- **Delete while live was accepted, not refused**, on this server. The "Stop the reply" toast path
  (device checklist item 2) therefore comes from the app's own check, not the server's refusal.
- Both throwaway chats (original and branch) were deleted; nothing left over.
