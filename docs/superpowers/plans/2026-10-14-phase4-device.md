# Phase 4 on the emulator, against the real server (2026-10-15)

Release build on the Pixel 9 emulator, signed in to the user's own Hermes server (`hermes.shreyaskamat.in`, behind
Cloudflare Access). The user signed in on the emulator themselves. The build was `feat/welcome-and-demo`, so it
**does not include the archive, rename and search fixes in PR #3**; those are covered by widget tests only.

## Live tests (run from the development machine)

- Read-only (`--tags live`): 5 of 5 pass. 50 conversations read, 5 profiles, usage on `openai-codex` and `anthropic`,
  30 search hits with titles, 0 archived.
- Write (`--tags live_write`, on a throwaway conversation): steer accepted; `/retry` returns `SlashKind.send` with
  text; rename visible; archive hides it from the list and shows it under archived; unarchive restores it.
- **Finding:** no `context_*` event arrived after a turn on this server, so the composer's context ring has no live
  data source here. It is drawn when the event arrives and absent otherwise.

## On the device

| Check | Result |
|---|---|
| Connects to the server and reaches home: 263 conversations, usage strip (ChatGPT/Codex, 7% used, reset time) | Pass |
| Collapsible header: scrolled, the bar shows a compact Connected link; Show more and Archived at the end | Pass |
| Search: server full-text hits with the matched words highlighted | Pass |
| Archived screen, empty | Pass |
| Long-press a conversation: Rename and Archive sheet | Pass |
| Archive: the row folds out, "Archived" toast with Undo, count falls to 262 after the list refreshes | Pass |
| Archived screen lists it with an Unarchive button; Unarchive empties the list again | Pass |
| Brightness set to Dark and profile set to `ananta`; force-stop and relaunch: both kept, `ananta` shows its 12 conversations | Pass |
| Reduced motion (animation scales 0): relaunch, Settings and both sheets open at once, nothing broken | Pass |
| Settings restored afterwards (profile `default`, brightness System, animation scales 1.0) | Done |

## Not checked on the device

- Sending a real prompt: steer, retry and the context ring were exercised through the live write test, not the UI.
- Rename from the UI, the sudo and secret card against a real agent, syntax highlighting in a real reply.
- The usage settings screen's choices surviving a restart (the theme and profile choices did).
- The fixes in PR #3 (the count dropping at once, Show more after an archive, undo after a refresh): covered by
  widget tests that fail without the fixes, not yet seen on the device.

## Things seen

- With animations on, the page behind a bottom sheet (Brightness) was drawn shifted left with a black strip on the
  right while the sheet was open, and returned to normal when it closed. With animations off the page stayed put.
  It may be the sheet's intended recede effect, but it looks like a glitch and is worth a look.
- Twice a tap landed on a conversation row instead of the intended target, because the list had been refreshed
  after the screenshot the tap was based on. Nothing was sent; the conversations were only opened to read.

The throwaway conversation was archived and unarchived, leaving the server as it was. Screenshots were deleted
(they showed real conversation titles).
