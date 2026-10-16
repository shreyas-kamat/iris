# Phase 6 — chat controls, in-turn prompts, and the Phase 2 design

**Date:** 2026-10-16. **Branch:** `feat/phase6-chat-controls`, cut from `main` at `1d9f1e7`.
Builds on Phase 5 (`2026-10-15-phase5-design.md`).
**Design:** the claude.ai/design project "Iris App", file `Iris Phase 2.dc.html` (frames A1–A8, B1–B10, Motion).
It is the source of truth for sizes, radii, springs, copy and states. This spec says what each frame needs from the
code and where the code differs from the design. It does not repeat the design's numbers.

## Goals

Chat controls and in-turn prompts, then the restyle of features that were built without a mockup.

1. **Delete** a conversation (home, and the Archived screen).
2. **Pin** conversations, with a Pinned section on home.
3. **Undo** the last turn (`/undo`, or the menu on your latest message).
4. **Branch** a conversation: whole (home menu, `/branch`) or from any reply (long-press).
5. **Busy policy.** Sending while a reply runs follows a Hermes setting (Queue, Steer, Interrupt). Queued messages wait
   in a tray. `/queue` and `/steer` always do their one thing.
6. **Reasoning effort and Fast mode** in the model sheet.
7. **Password-manager prompts** (`vault.unlock_prompt`, `vault.code`, `vault.save_login`).
8. **A minimal connection card** (`connection.request`) for connectors and MCP servers.
9. **Restyle** steering, the failed turn, rename/archive/Archived, search, sudo/secret, the context ring, provider
   usage, attachments, dictation and rich replies to frames B1–B10.

## Decisions

Made by the user on 2026-10-16:

- **One phase, one branch, built in feature slices.** One spec, one plan, one PR, one device pass.
- **Queued messages are held in Iris**, not by Hermes. The tray can remove and renumber; the cost is that the tray is
  lost if the app is killed, and the tray says so.
- **Branching starts from any reply**, not only the whole chat.
- **Busy policy follows Hermes's setting** (`display.busy_input_mode`), edited from Settings.
- **Connection card is minimal.** Installs, catalog tiers, security scans and the directory card are a later phase;
  those targets say "Finish this on Hermes Desktop" and can be skipped.
- **The 95% context strip's Branch is "branch, then compress".**
- **Kept from Phase 5:** attachments are Photos and Files only, at most 5 per message and 20 MB each. The design's
  Camera row and 25 MB figure are not built; the "+" menu has two rows and its footnote says 20 MB.
- **Deferred:** the Settings rows "Model — default model and effort" and "Approvals — mode" that appear in frame A5.
  Both write server-wide config. They are not drawn or built this phase.

Made while writing the spec (change any of them by saying so):

- **Pins, branch links, recent searches and image hosts are stored on the device**, in the Preferences table. None of
  them syncs.
- **A "Live" section on home** (frame A1) lists conversations that are replying right now, from the read-only
  `session.active_list`, read when home opens and every 15 s while it is visible. This is the one addition the design
  needs that no earlier phase has. If the call is missing on a server, the section is hidden.
- **Where the design assumes data the wire does not carry**, Iris shows less rather than inventing it (see
  "Design and wire differences").

## Verified in the Hermes source (current `main`, read 2026-10-16)

Not yet probed on the user's server; task 0 does that.

- **Delete:** `session.delete {session_id: <stored id>, profile?}` exists as an RPC, and Hermes refuses it for a live
  session with error 4023. Iris uses REST `DELETE /api/sessions/{id}`, the route Conduit and Desktop use, in the same
  family as rename and archive. A 4023 or "active" refusal is shown as "Stop the reply before deleting this chat".
- **Undo:** `session.undo {session_id, intent?}` returns `{removed}`. It refuses a running session with 4009.
- **Branch:** `session.branch_stored {parent_session_id, profile?, cwd?, idempotency_key?}` copies a stored parent's
  whole transcript server-side. `session.branch` and `session.branch_whole` need a live session. Branching from an
  older reply uses `session.create {parent_session_id, messages: [{role, content}], title, profile?}` with the
  visible prefix. `session.branch`'s `count` is not used: it counts Hermes's display projection, whose rows do not
  line up with `/messages` rows.
- **Busy:** `prompt.submit` on a running session applies `display.busy_input_mode` (`queue`, `steer`, `interrupt`) and
  answers `status: streaming | queued | steered | redirected`. `queued: true` forces queue mode. The mode is read and
  written with `config.set {key: "busy", value}`; `value: "status"` reads it.
- **Reasoning and Fast:** `config.set {key: "reasoning", session_id, value}` and `{key: "fast", session_id, value:
  "fast" | "normal"}`. The accepted efforts are `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, `ultra`.
  The design shows None, Low, Medium, High and Max. Both appear in `session.info`.
- **Server requests:** `vault.unlock_prompt {backend, display_name}`, `vault.code {site?, hint?}` and
  `vault.save_login {origin, site}` are answered with a response frame `{value: string}`, `''` meaning skip. The
  `save_login` answer is a JSON string `{"identifier", "password"}`. `request.cancel` withdraws any of them.
- **Connection:** the `connection.request` event carries `{op_id, seq, deadline_at, timeout_seconds, targets,
  display?}`. Each target has `name, kind (connector|mcp|plugin|skill), action (authorize|connect|enable|install|
  reconnect), state, detail, instructions, connect_url, required_env: [{name, required, secret, default, prompt}]`.
  `connection.update` carries new target states and `settled`. The answer is `connection.respond {owner: {type:
  "session", session_id}, op_id, result: {targets: [{name, status: approved|skipped, detail?, env?}], settled_by?,
  said?}}`. `pending_connection` on resume restores a card that was open.

## Design

### Data layer

All of these return `Result`. `DashboardChat` stays scoped to one profile; `profile?` follows the existing `_scoped`
rule.

| `ChatBackend` method | Wire |
|---|---|
| `delete(storedId)` | `DELETE /api/sessions/{id}` |
| `undo(runtimeId) → int` | `session.undo` |
| `branchWhole(storedId) → NewConversation` | `session.branch_stored` |
| `branchFrom(storedId, List<SeedMessage>, title) → NewConversation` | `session.create` with `parent_session_id`, `messages`, `title` |
| `compress(runtimeId)` | `session.compress` (for the 95% strip) |
| `submit(runtimeId, text, {queued}) → SubmitOutcome` | `prompt.submit`; `status` becomes `SubmitOutcome {started, queued, steered, redirected}` |
| `busyMode() / setBusyMode(BusyMode)` | `config.set busy` |
| `setReasoning(runtimeId, Effort)` / `setFast(runtimeId, bool)` | `config.set` |
| `answerLogin(LoginRequest, identifier, password)` | response frame `{value: '<json>'}` |
| `answerConnection(ConnectionRequest, List<TargetAnswer>, {settle})` | `connection.respond` |
| `activeSessions() → List<LiveStatus>` | `session.active_list` |

Events and parsing:

- `presentedServerRequests` adds `vault.unlock_prompt`, `vault.code` and `vault.save_login`.
  - The first two become `InputAsked` with new `InputKind.vaultUnlock` and `InputKind.vaultCode`, carrying
    `displayName`, `site` and `hint`.
  - `save_login` becomes `LoginAsked(LoginRequest {requestId, sessionId, origin, site})`.
  - **Typed values never persist.** They go straight into the reply frame and are not held in state, logs or
    analytics, the same rule as `secret`.
- `ConnectionAsked(ConnectionRequest)` from the event and from `pending_connection` on resume; `ConnectionChanged`
  from `connection.update`. Unknown `kind`, `action` and `state` values are kept as strings and rendered as the
  desktop-only row, never dropped (tolerant decoding).
- `session.info` and the resume `info` also carry `reasoning_effort` (or `reasoning`) and `fast` (or `fast_mode`).
  `model.options` per-model `capabilities` say whether a model supports each, so the sheet can hide a control.
- A conversation's replying state for the Live section comes from `session.active_list` rows
  `{id, session_key, status: working | waiting | starting | idle}`; only `working` and `waiting` count.

Device-local stores, all on the Preferences table, written through like the existing keys and never blocking the UI
when a write fails:

| Key | Scope | Value |
|---|---|---|
| `pins` | `serverId/profile` | JSON list of stored ids, newest first |
| `branch.<childId>` | `serverId/profile` | JSON `{parent, parentTitle, count}` |
| `search.recent` | server id | JSON list of up to 6 queries, newest first |
| `images.hosts` | server id | JSON list of hosts to load without a tap |

A pinned id missing from the loaded page is fetched once with `GET /api/sessions/{id}`; a 404 drops the pin quietly.

### Behaviour

**Delete.** A confirm sheet comes first ("Delete ‘title’? This removes it from Hermes for good."). On success the row,
its pin and its branch record are removed. A refusal because the chat is live gives the toast with an "Open" action
that jumps to it. Any other failure gives the usual `describe(failure)` toast. Delete is not offered from inside the
open chat. Archived rows get the same sheet from a long-press.

**Pin.** Pin and Unpin write straight away. A pinned chat shows only in Pinned, never twice. Archiving or deleting a
chat unpins it. Pins follow the profile. Pinned is hidden at zero.

**Undo.** `/undo` is caught before `slash.exec`. It needs an idle chat with a runtime.
- `removed > 0`: the transcript is trimmed from the last `UserTurn` onward, that turn's text goes back to the composer
  through `onPromptReturned` (beside the existing `onSteerReturned`), and the toast says "Undid the last turn".
- `removed == 0`: "Nothing to undo". A 4009 refusal: "Stop the reply first to undo", with a Stop action.
- The menu offers Undo only on your most recent message.

**Branch.**
- From home, from `/branch`, and from the newest reply while idle: `branchWhole(storedId)`. `/branch` and the home menu
  show the same "Branching…" state.
- From an older reply: load earlier pages until the whole prefix is present, then `branchFrom` with the user and
  assistant text up to and including that reply, titled "Branch of ‹title›". Tool calls are not carried.
- The new chat opens in place of the current one. The branch record is stored, so the "Branched from ‹parent›" line
  and the "Branched here" divider persist on this device. Tapping the line opens the parent; a deleted parent gives a
  toast.
- The 95% strip's Branch is `branchWhole`, then `compress` on the new runtime. If compress fails, the chat still
  opens and a toast says "Branched, but couldn't summarise".

**Sending while running.** Replaces today's "text while running steers".

| Setting | Plain text while a turn runs |
|---|---|
| Queue | Goes into the tray. Nothing is sent. |
| Steer | `submit`; a steer bubble at the current point, tagged "Waiting for next step", becoming "Picked up at step n" on the next `tool.start`. |
| Interrupt | `submit`; the cut reply drops to muted with "stopped · redirected" and the new turn starts at thinking. |

- `/queue text` always goes to the tray while running, and is a normal send when idle. `/steer text` is the steer path
  while running, and a normal send when idle.
- **Tray rules.** Numbered; each item removable; with 4 or more it shows the first 2 plus "+N more", which expands
  upward. On `turn.done` the oldest item is sent, lifting out of the tray into a normal bubble with a "From queue"
  tag that fades after 2 s. If the turn failed, the tray pauses and offers "Send next" and "Clear". The tray is in
  memory only and is cleared on leaving the chat. Its footer says "Queued messages are held on this phone".
- A gateway answering 4009 to a steer or interrupt falls back to today's steer path, so nothing gets worse.
- A `submit` that comes back `queued` (Hermes applied its own policy, as an older client might have set it) is
  treated as accepted: a toast "Queued for after this reply".
- The mode is read once per profile when a chat opens. The send button's glyph and the mode tag follow it while a turn
  runs and text is typed; with an empty field the button stays Stop.
- **Settings:** "While Hermes is replying" reads `busyMode()` and writes `setBusyMode()`. It is profile-wide. A failed
  write shows a toast and keeps the old value.

**Model sheet.** Reasoning and Fast show only when the selected model supports them, with no disabled state. A change
calls `setReasoning` or `setFast`, creating a session first if there is no runtime, as model switching does. Mid-turn,
the change waits for the next turn and the sheet shows the "Applies after this reply" note, which clears when the
reply ends. The composer's model chip shows the effort ("opus-4.5 · high").

**Needs-you prompts (vault, sudo, secret).** One card. The chat orb is needs-you until it is answered. Settled cards
collapse to a single line: answered, skipped, or expired (withdrawn by `request.cancel`). Values are cleared from
memory on send.
- Unlock and the code card use the existing input path. The code card uses six cells when the hint names 6 digits,
  with auto-send on the sixth; otherwise it is one plain field with Send enabled when non-empty.
- `save_login` has Username and Password fields with a reveal toggle, and Skip answers `''`.

**Connection card.** One card per open `op_id`, kept in `state.connections`, with a mono countdown to `deadline_at`.
- Per target, by action and kind:
  - `authorize`, `connect`, `reconnect` with a `connect_url`: "Open sign-in" opens the system browser. The row then
    shows "Waiting for sign-in…" with Reopen, and follows `connection.update`. No polling.
  - `enable`: Enable or Skip.
  - `mcp` with `required_env`: one field per value, masked when `secret`, with the `prompt` as hint; Approve or Skip.
    A `detail` error from an update (for example a rejected token) shows under the field.
  - Everything else (plugin or skill installs, anything with a security scan): "Finish this on Hermes Desktop" and
    Skip.
- Approve and Skip send `connection.respond` for that one target. Continue sends `settled_by: "continue"` and counts
  anything still open as skipped. Continue is a ghost button while anything is pending and filled once settled.
- The card closes when Hermes reports `settled`, and shows "Hermes stopped waiting. Ask again to restart setup." when
  the deadline passes.
- Credential values go straight into the response; they never enter state, logs or persistence.

**Restyle (B frames).** Behaviour is unchanged except as listed:
- *Steering (B1):* the steer bubble sits at the point Hermes picked it up (above).
- *Failed turn (B2):* adds a Details control and an "attempt n" counter, counted locally. The code line shows the
  failure text Hermes gives; nothing is invented.
- *Rename, archive, Archived (B3):* as designed, plus Delete on a long-press in Archived.
- *Search (B4):* results are grouped per conversation ("3 CHATS · 7 MATCHES") from the per-message hits; the search
  button morphs into the field; queries debounce at 200 ms; recent searches show as chips when the field is empty.
- *Context ring and usage (B6, B7):* the ring's label hides under 50%, switches to needs-you from 90%, and shows the
  95% strip with Branch. Tapping the ring opens a popover with tokens used and the limit. The usage strip and
  provider rows follow the frame; bars switch to needs-you from 85%.
- *Attachments and dictation (B8, B9):* the "+" menu has Photos and Files. The listening orb is the level meter, from
  the recorder's amplitude, throttled to 4 updates a second under reduced motion. A "Didn't catch that" note offers
  Try again for 6 s.
- *Rich replies (B10):* the Markdown image card gains "Always load from this host" in its long-press menu. Code blocks
  keep the detected-language header and use accent for keywords and muted for comments only.

### UI

The design supplies the geometry. New and changed components, mostly under `lib/design/components/` and
`lib/features/chat/`:

| Frame | Component |
|---|---|
| A1 | `PinnedSection`, the Live section, the long-press lift with scrim, the conversation action sheet (Pin, Rename, Branch, Archive, Delete), delete confirm, "Branching…" state |
| A2 | `MessageMenu` (lifted plate, anchored menu that flips above the composer), `BranchedHeader`, the "Branched here" divider |
| A3 | Undo collapse (spring 300/30), the prompt returning to the composer, the undo toasts |
| A4 | `QueueTray`, `SendGlyph` ×4 (send, queue, steer, interrupt) and the mode tag, the slash list rows for `/queue`, `/steer`, `/undo`, `/branch`, toasts at the top under the header |
| A5 | The "While Hermes is replying" row and picker, with the iris radio |
| A6 | The effort segmented control, the Fast switch, the mid-turn note card |
| A7, B5 | `NeedsYouCard` for unlock, code, login, sudo and secret, and its settled lines |
| A8 | `ConnectionCard`, state chips, countdown, Continue |

- Every colour is a palette role or an `AgentState` colour. No widget holds a design hex value. The new tints (the
  needs-you colour at 45%, 10% and 8%) are derived from the role. Contrast tests are never loosened; adjust the
  colour.
- Light variants are required for home, the message menu, the model sheet and the unlock card.
- Reduced motion has an instant or cross-fade alternative for every new animation, as drawn in the Motion frame. Under
  `disableAnimations` no new ticker runs.
- 44 pt targets, and no overflow at 320 pt wide or 200% text, for every new surface.

## Design and wire differences

| The design shows | Iris does |
|---|---|
| sudo: "Password for jamie on hermes.local" | The request has no username, so: "Password for sudo on hermes.local" |
| secret: a destination path and the key's prefix | Not sent by Hermes. The variable name and the server's `prompt` or `metadata` text are shown |
| One-time code: always six digits | Six cells only when the hint says 6 digits (see Behaviour) |
| Camera in the "+" menu, 25 MB | Not built (decision above): Photos and Files, 20 MB |
| Settings rows Model and Approvals | Deferred (decision above) |
| "Limits … refresh every 5 minutes" | The footnote says the limits come from each provider; the interval is the server's |
| Failed card "502 · after 30s on read_logs" | Shows the failure text Hermes provides |

## Platform and release

No new permissions on either platform. The privacy policy and `docs/release.md` need no change. The CHANGELOG and the
README feature list get the new features.

## Testing

- **Task 0, a read-only probe of the user's server:** call each new method with an invalid id and record which answer
  "unknown method" (`session.undo`, `session.branch_stored`, `session.compress`, `session.active_list`,
  `connection.respond`, `config.set` for `busy`, `reasoning` and `fast`). A missing method hides its control and shows
  "not supported on this server" where the control was reachable by a slash command. The result is recorded in the
  plan.
- **Unit tests:** the new `ChatBackend` calls (fake socket and HTTP); the parsers for vault, connection and
  `session.info`; `PinStore`, the branch store, recent searches and image hosts; the queue tray logic including the
  failed-turn pause; the steer step counter; the undo trim; the branch prefix builder.
- **Widget tests:** every new card, sheet and menu; the long-press flows; the composer's glyph and mode tag per mode;
  the tray (overflow, remove, drain); the connection card's states; the 320 pt and 200% text reflow of each new
  surface. A fake recorder and a fake picker are reused from Phase 5.
- **Goldens:** home with pins and Live, the lifted message menu, the queue tray, the needs-you card and the connection
  card, each in dark and light. Existing goldens are regenerated only where the restyle changes them, and each change
  is looked at.
- **Live write test:** against the real server, on a throwaway chat: pin, branch, undo, queue two messages, then
  delete it. Replies are slow, so each turn waits at least 240 s. The vault and connection cards cannot be triggered
  on demand, so they are covered by unit tests and the demo backend.
- **Demo backend:** gains scripted vault, sudo and connection prompts so the device pass can see them.
- **Device pass:** one pass on the Pixel 9 emulator with a release APK, recorded in
  `docs/superpowers/plans/2026-10-16-phase6-device.md`. Cover the delete, pin, undo and branch flows, all four
  composer modes, the model sheet, each card from the demo backend, light and dark, and reduced motion.

## Execution split

The plan will carry the final task list. This is the intended split of work across models, by how much judgement a
task needs. A task that fails its tests on the first model is retried on the next one up.

| Task | Model |
|---|---|
| 0 Probe the server | haiku |
| 1 Data layer: models, events, parsers, backend methods | sonnet |
| 2 Device-local stores: pins, branch records, recent searches, image hosts | haiku |
| 3 Design foundation: needs-you tints, `NeedsYouCard`, `SendGlyph`s | sonnet |
| 4 Delete (home, Archived) | sonnet |
| 5 Pin, Pinned and Live sections, the action sheet and lift | sonnet |
| 6 Undo | sonnet |
| 7 Branch (menus, header, divider, `/branch`, compress) | sonnet |
| 8 Busy policy: controller state machine, queue tray, steer steps, settings picker | opus |
| 9 Reasoning and Fast | sonnet |
| 10 Needs-you prompts: vault, login, and the sudo and secret restyle | sonnet |
| 11 Connection card | opus |
| 12 Restyle B1–B10 | sonnet |
| 13 Search grouping and recent searches, image hosts menu | sonnet |
| 14 Demo backend scripts | haiku |
| 15 Goldens, analyze, CHANGELOG and README | haiku |
| 16 Live write test | sonnet |
| 17 Device pass | sonnet |
| 18 Final review of the whole diff | opus |

Opus is for the two tasks with real concurrency and state-machine risk: sending while running (queue, steer,
interrupt, drain, failure pause, reconnect) and the connection card (deadlines, updates racing responses, credential
handling), and for the final review.

## Out of scope

- The full connector and MCP card: installs, catalog tiers, security scans, plugin phases and the directory card.
- Settings rows for default model and effort, and for approval mode.
- Camera capture, and a 25 MB limit.
- Server-side deletion of queued messages, and a queue that survives the app closing.
- Syncing pins, branch links, recent searches or image hosts across devices.
- Branching with tool calls carried over; branching by `session.branch`'s `count`.
- Scheduled and Tasks tabs, live voice mode, push, widgets, localisation (Phases 7 and 8).
