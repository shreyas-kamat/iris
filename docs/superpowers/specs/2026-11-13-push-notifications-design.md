# Push notifications — design (Phase 9.2)

Status: approved by the user 2026-11-13. Branch `feat/push` (cut from `feat/genui` at `3750bda`, because the
`hermes-iris` plugin lives there; retarget to `main` once PR #42 merges).

## Intent

When something happens on the user's Hermes server and they are not looking at Iris, their phone gets their attention
with words they chose. The three moments: a reply they were waiting for has landed, the agent is waiting for their
approval, a scheduled job has finished. Today they only find out by opening the app.

Success: the user sends a long request, locks the phone, and is pinged when it is done; an approval can be answered from
the notification after unlocking; a cron job tells them when it finishes. No Google service is involved.

## Decisions the user made (2026-11-13, in chat)

1. **Three events**, all wanted: reply finished, approval waiting, scheduled job finished.
2. **The user writes the wording**, in Iris. Not the agent.
3. **Per event, a display mode:** *show what's happening* or *show only my text*. Approval defaults to showing the
   command waiting. (Defaults for the other two are my call; see below.)
4. **No Google.** No Firebase / FCM, no Google Play services dependency.
5. **Android and iOS both.** The user has an Apple developer account.
6. **Android: Iris holds its own connection** to the server in the background (foreground service with a permanent
   "connected" notification; some battery cost accepted). Not UnifiedPush / the ntfy app.
7. **Approve and Deny on the approval notification**, and **the phone must be unlocked** to act on them.
8. **Only active chats notify:** a chat where the user sent something and is waiting for the answer. Chats left idle,
   and chats started from other platforms (Telegram etc.), stay quiet. Scheduled jobs follow their own switch.

## Goals

- Reliable, timely alerts for the three events on Android and iOS, in the user's words.
- Answer an approval (once / deny) from the notification, behind device unlock.
- Tap opens the chat or job the alert is about.
- Self-hosted end to end except Apple's push service on iOS.

## Non-goals (v1)

- Notifications chosen or worded by the agent.
- Other platforms' chats (Telegram, Discord, CLI), kanban, group rooms.
- "Session" and "always" approval answers from the notification (in-app only).
- Rich content (images, reply previews beyond one line), notification grouping beyond the platform default, quiet
  hours, per-chat mute. (Candidates for later.)
- Web push, desktop.

## Anti-goals (a failure even if it works)

- Any Google dependency, including transitively through a push library.
- A lock-screen tap that approves a command without unlocking.
- Private content on the lock screen when the user chose "only my text".
- A third-party relay holding the user's tokens or content (Conduit-style relay). The server talks to Apple directly.
- Being pinged for a chat the user is already looking at.
- An Android connection that silently dies and leaves the user believing they are covered (it must show when it is
  disconnected).

## Constraints

- Server: user's Hermes at `hermes.shreyaskamat.in`, release 2026.9.24 (hermes-agent `f97608f`), behind Cloudflare
  Access + dashboard login. Plugin code goes in `server/hermes-iris/` (the existing plugin, now 0.3.0); bump its
  version.
- App: Flutter, Riverpod 3, existing design system. App id `com.iflotech.iris`.
- Run book rules: test-first, inline work, commits under the user's name only.
- Opus for the security-sensitive parts (APNs signing and key handling, the approval action path, the Android
  background service); Sonnet for the rest.

## What the recon found (verified in hermes-agent `f97608f` and this repo)

- **Reply finished:** `on_session_end` fires at the end of **every turn** (`agent/turn_finalizer.py`) with
  `session_id` (stored id), `turn_id`, `completed`, `failed`, `interrupted`, `turn_exit_reason`, `platform`.
- **Approval waiting:** `pre_approval_request` fires for dashboard (gateway-notify) approvals
  (`tools/approval_gateway_wait.py`) with `command`, `description`, `pattern_key(s)`, `session_key`, `surface`.
  Observer only: plugins cannot answer. `post_approval_response` fires with the choice.
- **Scheduled job finished:** no cron hook, but a cron run is an agent turn with `platform="cron"`
  (`cron/scheduler.py`), so `on_session_end` fires for it. The scheduler also books `cron_complete` /
  `cron_incomplete_no_output` on the session row.
- **Auth for background work:** Iris already keeps the Cloudflare Access service token and dashboard login in secure
  storage (`lib/data/net/credentials.dart`), so a background connection or an action handler can authenticate
  without the user.
- **Answering an approval:** Iris already answers with JSON-RPC `approval.respond` over the dashboard WebSocket
  (`lib/data/chat/chat_backend.dart`).

## Design

### Server: `hermes-iris` plugin

- **Devices registry** (per profile, in the plugin's store, atomic 0600 writes as today): each Iris install registers
  `{device_id, platform: android|ios, apns_token?, app_version, settings}`. Routes under `/api/plugins/iris/push/...`
  (behind dashboard login like every plugin route): register / update settings / unregister / send test.
- **Active-chat tracking:** a chat becomes *active* when the user sends a turn to it from Iris (the plugin already sees
  `pre_llm_call` with platform `desktop` from Iris sessions) and stops being active when the turn's
  `on_session_end` alert has been sent (or after a timeout, builder's choice). Only Iris-originated sessions count.
- **Event sources:**
  - Reply finished: `on_session_end` for an active chat, `completed` or `failed` (not `interrupted` by the user).
  - Approval waiting: `pre_approval_request` for an active chat. Cancel or replace the alert on
    `post_approval_response` (answered elsewhere).
  - Job finished: `on_session_end` with `platform == "cron"`; include success vs no-output.
- **Payload** carries what each display mode may need: event kind, stored session id (or job id), chat title / job
  name, first line of the reply, the approval's command and description, and the approval id needed to answer.
  Content fields are left out entirely for a device whose setting is "only my text".
- **Delivery:**
  - iOS: the plugin sends directly to APNs (HTTP/2, token-based `.p8` auth) using the user's key, team id and key id,
    kept on the server outside the repo and outside any log. No relay.
  - Android: the plugin exposes a long-lived stream (SSE or WebSocket, builder's choice) that the Iris background
    service holds open; events go down it. Missed events while disconnected are replayed on reconnect (short
    retention window, e.g. the last few minutes or N events).
- Hooks must be fast and never raise into the agent: queue the send, deliver off the hook thread.

### App: Iris

- **Settings → Notifications** (per server/profile): a switch per event, the user's text per event, the display mode
  per event, a "send test" button, and on Android the state of the background connection.
- **Android:** a foreground service (type fit for messaging; it must survive Android 14/15 rules and Doze as well as
  any non-Google app can), started when notifications are on, with a permanent low-importance "Iris is connected"
  notification that changes to "disconnected" when it cannot reach the server. It reconnects with backoff and
  re-authenticates from stored credentials. Notification channels per event.
- **iOS:** request permission, register for APNs, send the token to the plugin. Notification categories with
  actions; the approval actions require authentication (`authenticationRequired`).
- **Approval actions:** Approve once / Deny. On Android the action runs only after the device is unlocked
  (`setAuthenticationRequired` or equivalent). The handler authenticates and sends the answer for that approval id
  (via `approval.respond` or a plugin route; see open items), then updates the notification with the outcome
  (approved / denied / already answered / expired).
- **Suppression:** if Iris is in the foreground on the chat in question, no alert (checked on the device).
- **Tap:** opens the chat (stored session id) or the job.
- **Off switch:** turning notifications off unregisters the device and stops the Android service.

### Defaults (my calls, for the user to check)

- Reply finished: on, mode "only my text"; job finished: on, mode "show what's happening" (shows the job's name, which
  the user wrote); approval: on, mode "show what's happening" (the user's stated default).
- Default text for each event: "Attention!" until the user changes it. "Show what's happening" puts the user's text as
  the title and the content as the body.
- Approve button = **once**. "Session" and "always" stay in the app.
- Multiple phones: every registered device gets the alert; each has its own settings.
- A failed reply still notifies (as a failure), an interrupted one does not.

## Open items for the builder (verify before building on them)

1. **Session ids:** the approval hook gives `session_key`, not `session_id`. Confirm on the server that, for dashboard
   sessions, it equals the stored session id the other hooks give (it looks like the key `tui_gateway` registers), or
   find the mapping.
2. **Where the hooks run:** an earlier probe found the dashboard API module loads separately from the agent. Confirm
   that hooks firing in the agent process can reach the delivery queue and the Android stream (likely via the
   plugin's on-disk store, as GenUI does). This decides the server architecture; probe it first.
3. **Answering an approval in the background:** `approval.respond` needs a live WebSocket session; check whether a
   fresh connection + `session.resume` can answer a pending approval, and the approval's timeout (the action must arrive
   before it). If not, a plugin route that settles it is the fallback.
4. **Android foreground-service type** and Play policy for it (the app is headed to Play): pick the type that is
   allowed for a persistent server connection without the 6-hour `dataSync` cap.
5. **APNs key setup** steps for the user (create key in the Apple developer portal, place it on the server), and the
   iOS entitlement / provisioning change.
6. Dashboard login session expiry during long background runs: re-login from stored credentials.

## Left to the builder

Stream protocol, retention window, store layout, settings UI layout (within the design system), package choices
(must have no Google dependency; check transitive deps), backoff numbers, and the plan's segment table.

## Testing

- Plugin: unit tests for registry, active-chat tracking, event mapping per hook payload, payload redaction per mode,
  APNs request building (signed JWT, headers) against a fake.
- App: settings, payload → notification mapping, suppression, tap routing, action handler (fake backend), service
  reconnect logic.
- Live: a probe on the user's server for open items 1–3 (tell the user first), then a device pass on the Moto G45 and
  on the user's iPhone (the user has one for testing, 2026-11-13). This machine is Windows, so an iOS build needs a Mac
  or a cloud build; the plan must name which before the iOS segment.
