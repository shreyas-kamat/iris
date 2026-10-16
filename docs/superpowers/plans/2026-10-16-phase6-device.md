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

## Device pass, second round — 2026-10-16

Run on the real server (item 5) and the demo (items 2, 7, 8) after the first round. The emulator hung once and was
cold-booted. Animations were off (`animator_duration_scale 0`) for the demo steps, so those double as a reduced-motion
pass for the surfaces they touched.

| # | Item | Result |
|---|---|---|
| 5 | Queue / Steer / Interrupt, real server | **Pass.** Queue: "Queued for after this reply" toast, tray shows `1 second`, `2 third`, "held on this phone", drains in order. Steer: "Steered" toast, dashed bubble "WAITING FOR NEXT STEP", then "STEER · PICKED UP AT STEP 2". Interrupt: the cut reply is marked "stopped · redirected" and the new message is answered. The server's busy mode was `interrupt` at the start and was put back to it |
| 7 | Demo "Deploy the docs site" | **Pass.** Unlock, six-cell code (auto-sent), save login, then the connection card: Open sign-in opens Chrome and the row reads "Waiting for sign-in… Reopen", the desktop-only row has Skip, Continue ends the script. Each vault prompt leaves a settled line with "value hidden"; no typed text appears anywhere. Stopping mid-prompt leaves the dashed "1Password request withdrawn · expired" line |
| 8 | Dictation | The mic asks for permission, then the bar shows Cancel, the live orb, a timer and a stop button; stopping in the demo returns a canned transcript. "Didn't catch that" needs the real server and was **not walked** |
| 2 | Delete a chat | **Found a bug the first round missed** (below), fixed, re-checked: sheet, row leaves, "Deleted ‘…’" toast. The "Stop the reply" toast for a replying chat was **not reached** (the demo reply finishes before the menu opens) |

### Found and fixed in this round

1. **The delete confirmation had no surface.** It returned bare padding from `showIrisSheet`, so "Delete ‘…’?" and the
   buttons were drawn straight over the conversation list (the first round's screenshot `d2-confirm` shows it; it was
   wrongly marked a pass). It now uses `IrisSheet` with a grabber and the sheet buttons, and a test asserts the sheet
   exists. Every other sheet in the app was checked and already used `IrisSheet`.
2. **A sheet opened over a pushed page moved the page left** (`IrisPageRoute` drifted its page for any route pushed over
   it, so Settings slid 28% left with a black strip showing behind the scrim). Only another page does that now.

### Not walked, and why

- Attachment chips and "5 / 5 FILES": needs the system file picker on the emulator.
- Context ring at ≥50 / ≥90 / the 95% strip, usage bars at ≥85%: the demo tops out at 31% context and 61% usage, the
  real server was at 31–41%. Covered by the Task 15 goldens and widget tests only.
- "Didn't catch that" with Try again; the "Stop the reply" delete toast; an older message having no Undo.
- Reduced motion beyond the demo steps above (system "Remove animations" toggle not used).

### Still open

- Model sheet shows no effort or fast controls for `gpt-6.1-sol` while the chip says "medium" (see the first round).
- In the demo, Enable and Skip on a connection row do nothing visible: the real server answers with a
  `connection.update`, the demo backend never sends one. Continue still works.
