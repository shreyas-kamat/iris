# Phase 6 device pass

## Live write test � 2026-10-16

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

## Device pass — 2026-10-16

Pixel 9 emulator, release APK, cold-booted (the first boot had gone offline). Light theme unless noted. The demo
does not survive an app restart, so anything that needs persistence was walked against the real server (signed
in with the live credentials; every chat created was a throwaway and was deleted afterwards, 273 → no change).
Screenshots were taken during the pass and are not committed; names below are the files kept locally.

| # | Item | Result |
|---|---|---|
| 1 | Long-press a chat: sheet with Pin, Rename, Branch, Archive, Delete; pin shows a Pinned section above Recent; unpin removes it | **Pass** (demo, light: d1-menu, d1-pinned-light) |
| 2 | Delete: confirm sheet, the row leaves, toast | **Pass** in the demo (d2-confirm, d2-deleted). The "Stop the reply" toast for a replying chat was **not walked** |
| 3 | Branch from the menu; the new chat opens with "Branched from …"; still there after a kill and reopen | **Pass** on the real server (d3-opened, d3-persist). The branch copies the transcript and ends with "Branched here · 18:18". In the demo the branch opens empty and the line is gone after a restart (demo state is in memory) |
| 4 | Reply menu: Copy, Select text, Branch from here. Latest user message: Copy, Select text, Undo. Undo collapses the exchange, restores the prompt, toast "Undid the last turn" | **Pass** (d4-reply-menu, d4-user-menu, d4-undone). The older-message-has-no-Undo case was not walked |
| 5 | Busy mode Queue / Steer / Interrupt in a running reply | **Not walked** (replies finish in seconds on this server, so the tray is hard to catch by hand; covered by the widget tests and the live test) |
| 6 | Model sheet | Opens with a filter and a long list (d6-model). Neither effort nor fast showed for `gpt-6.1-sol` although the composer chip reads "· medium" — the sheet follows the gateway's capabilities, the chip follows the session. **Open question**, not changed |
| 7 | Demo "Deploy the docs site" prompt cards | **Not walked** |
| 8 | "+" menu: Photos, Files, "up to 5 files · 20 MB each" | **Pass** (d8-plus). Chips, dictation, context ring and usage thresholds **not walked** |
| 9 | 200% font on a 320 dp window | **Found three problems, all fixed** (below) |
| 10 | Permissions | **Pass**: `INTERNET` and `RECORD_AUDIO` only; `RECORD_AUDIO` arrived in Phase 5 (merge base `1d9f1e7`) |

Dark theme was checked on the chat screen only (clean). Reduced motion was **not** run.

### Found and fixed at 200% text on 320 dp

1. The "Branched from …" line was clipped: it was a fixed 44 high. Now `minHeight: 44`.
2. The model chip pushed the mic/Send button off the right edge. The left cluster is now an `Expanded` row, and the
   chip shrinks with an ellipsis inside it. (A first attempt with a `Flexible` beside the `Spacer` shrank the
   chip on a normal phone and pulled Send next to it; caught on the device, and a test now guards it.)
3. The home usage card squeezed "ChatGPT or Codex Subscription" to one letter per line. At a large text size
   the name and the figure now each take a line; at normal sizes the single-row header is unchanged.

Each has a widget test that fails on the old code (the branched-header test passes on both, so it only guards
against a regression of the new behaviour).

### Other observations

- The Hermes dashboard dropped connections twice during the pass (the app showed "Reconnecting"; the live probe
  from this machine failed too) and recovered within a couple of minutes. Not caused by the app.
- A small spinner sits beside the model chip in a chat for a while after it opens ("context ring loading").
