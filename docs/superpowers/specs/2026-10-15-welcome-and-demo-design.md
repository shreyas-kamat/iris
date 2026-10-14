# Welcome, connection modes and the demo

**Date:** 2026-10-15. **Branch:** `feat/welcome-and-demo`, cut from `main`.
Builds on Phase 4 (`2026-10-14-phase4-design.md`). Part of the 1.0 store release.

## Why

Iris needs a Hermes server to do anything. That stops two groups:

- **Store reviewers.** Apple and Google must be able to use the app. Hermes Conduit, the iOS app Iris is
  compared with, has no demo mode: its listing says "A working Hermes installation is required", so it
  almost certainly gives Apple a login to a live server. Iris will not do that. Running a server and a model
  for reviewers costs money, and a Hermes login drives an agent that can run commands.
- **People without a server yet.** They should be able to see what Iris is like before setting one up.

First run also opens on a single address field whose later steps talk about Cloudflare, although most people
reach their server on the same Wi-Fi or over Tailscale.

## Goals

1. A **welcome screen** on first run with four choices: Same Wi-Fi, Tailscale, Cloudflare, Try the demo.
2. A **connection mode** that tailors the connect screen's wording and example address. The connect flow
   itself (probe, Access token only when Access is detected, sign in) is unchanged.
3. **Plain `http` works for private addresses** in release builds on Android and iOS, and is refused for
   public ones.
4. A **demo mode**: offline, scripted, no network and no model. Every main screen works in it: the
   conversation list, a chat with streamed replies, reasoning, tool calls, approval and sudo cards, steer,
   stop, retry, the context ring, usage, rename, archive, the Archived screen, search and profiles.
5. The demo is good enough to **show to prospective users** and to take store screenshots from, not only to
   satisfy a reviewer.

## Decisions made with the user

- The demo is for reviewers and prospective users alike (option B).
- Picking a mode changes guidance only. The probe-driven flow stays (option A, "keep current flow").
- In a demo chat, three or four suggested prompts play rich scripted turns. Anything typed freely gets one
  honest reply saying replies are pre-written, with a link to connect a real server.
- The demo is a temporary session: never saved, a fresh launch returns to the welcome screen, and it is not
  offered once a real server is connected.
- Demo content is about self-hosting and developer work.
- Architecture: a `DemoChatBackend` behind the existing `ChatBackend` seam, switched in by providers.
  Rejected: an in-app fake Hermes server (too much protocol to imitate, breaks with it), and replaying
  recorded sessions (tied to one protocol version, risks shipping real data).

## Design

### Shape

```
First launch, no servers
  ServerGate ──► WelcomeScreen
                   ├─ Same Wi-Fi ─┐
                   ├─ Tailscale  ─┼─► ConnectScreen(mode)   the current flow; mode changes the words
                   ├─ Cloudflare ─┘
                   └─ Try the demo ──► demoModeProvider = true ──► home, in demo
```

"Add server" in the server switcher and in `ServerGate` opens the welcome screen without the demo row, then
`ConnectScreen(mode)`.

### Connection modes

- `enum ConnectionMode { lan, tailscale, cloudflare }` in `lib/data/net/`.
- `ServerConfig.mode` (nullable). Servers added before this change have none and look and behave as today.
- Database schema 3 → 4: a nullable `connection_mode` text column on `servers`, written when a server is
  added. The migration only adds the column.
- `ConnectScreen` takes a required `mode`. It changes:

| Mode | Example address | Help under the field |
|---|---|---|
| Same Wi-Fi | `http://192.168.1.20:9119` | The server's address on your network and the dashboard's port, usually 9119. Your router's device list or `ip addr` on the server shows it. |
| Tailscale | `http://100.101.102.103:9119` or `https://box.tail1234.ts.net` | Open the Tailscale app and copy your server's address. |
| Cloudflare | `https://hermes.example.com` | The address you open in a browser. If Cloudflare Access protects it, Iris asks for a service token next. |

- A "Change" text button above the form returns to the welcome screen.
- The link status screen shows the mode's name beside the address when the server has one.

### Plain http on private addresses

An `http` address is allowed only when its host is private:

- IPv4 in `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, or Tailscale's `100.64.0.0/10`
- IPv6 loopback or unique-local (`fc00::/7`)
- a name ending in `.local` or `.ts.net`, `localhost`, or a single-label name (no dots)

A function `isPrivateHost(Uri)` in `lib/data/net/` decides this, and `ConnectScreen` refuses any other `http`
address before probing, with: "Use https for an address on the internet." The existing rule that the Access
token is sent only over https stays.

Platform policy:

- **First, verify** whether a release build can reach an `http` address at all. Iris uses Dio over `dart:io`,
  which opens its own sockets and may not be subject to Android's cleartext policy or iOS App Transport
  Security. The check: run a plain HTTP server on the development machine and point a release build on the
  emulator at `http://10.0.2.2:<port>`. A probe that reports "not Hermes" means the request went through; an
  error naming cleartext means it was blocked.
- **Android**, only if blocked: `android:usesCleartextTraffic="true"` on `<application>`. Android's domain
  rules cannot express IP ranges, so `isPrivateHost` is the real guard.
- **iOS**, always: `NSLocalNetworkUsageDescription` ("Iris connects to your Hermes server on your local
  network."), which iOS requires before any connection to the local network. If ATS turns out to apply,
  also `NSAllowsLocalNetworking`. If a Tailscale `100.x` address is still blocked on iOS, the Tailscale help
  text recommends the `https://….ts.net` address, which needs MagicDNS with HTTPS certificates turned on.

### Welcome screen

`lib/features/servers/welcome_screen.dart`. The orb, "Connect to your agent", one line of explanation, then
four large rows (an icon, a title and one line):

| Row | Line |
|---|---|
| Same Wi-Fi | Your phone and server are on the same network |
| Tailscale | Reach your server from anywhere over your tailnet |
| Cloudflare | Your dashboard is published through Cloudflare Access |
| Try the demo | Sample conversations. No server needed. |

The demo row is set apart below the other three with a little space and a quieter style, so it does not read
as a fourth way to connect. Iris design rules apply: tokens, `IrisPressable`, the platform's page transition,
reduced motion respected, and semantics labels on each row.

`ServerGate` shows the welcome screen where it showed `ConnectScreen` when there are no servers.

### Demo mode switch

- `demoModeProvider`: a `NotifierProvider<DemoMode, bool>`, false by default and never persisted.
- These providers return demo values first when it is true, and are otherwise unchanged:
  - `activeServerProvider`: a fixed `ServerConfig(id: 'demo', baseUrl: 'https://demo.iris', label: 'Demo')`
  - `activeLinkProvider`: a single `LinkState(LinkPhase.live)`
  - `activeCapabilitiesProvider`: a fixed `ServerCapabilities` naming what the demo supports, with
    `probedAt` set
  - `activeChatProvider`: one `DemoChatBackend` for the session, created when demo starts and disposed
    when it ends
- `activeSessionProvider` is not read in demo, so no socket or HTTP client is created.
- `ServerGate`, when demo is on, shows home whatever the server list holds.
- The home bar shows a small "Demo" pill next to the profile pill.
- Settings, in demo, replaces the Server section with one row, "Leave demo". It sets the switch off, which
  cancels any running script, disposes the backend and returns to the welcome screen.
- The Iris link handler (`lib/features/chat/links.dart`) treats `iris://leave-demo` as "Leave demo" and
  opens no browser.

### DemoChatBackend

`lib/demo/demo_chat_backend.dart` implements `ChatBackend`. Its state is in memory and starts from
`lib/demo/demo_content.dart`, which holds only data:

- Profiles `default` and `homelab`. Conversations belong to one or the other.
- About eight stored conversations with full transcripts, newest first; two archived.
- `ModelOptions` with three models, the provider in use, and usage windows for two providers.
- A short slash-command list (`/retry`, `/model`, `/help`).
- The suggested prompts and their scripts.

Behaviour, call by call:

- `conversations(offset)`, `archivedConversations(offset)`: pages of the active profile's rows, honouring
  archive state.
- `history(id)`: the whole transcript in one page.
- `create()`: a new conversation with no title, added to the top of the list.
- `resume(id)`: returns a runtime id, `demo-run-<id>`.
- `submit(runtimeId, text)`: if `text` is one of the suggested prompts, plays its script; otherwise plays
  the fallback script. A `TitleChanged` names a new conversation from the prompt.
- `interrupt`: cancels the running script and emits `TurnInterrupted`.
- `steer`: returns `accepted` and adds a short acknowledgement to the reply being written.
- `runSlash('/retry')`: replays the last script in that conversation. Other commands return
  `SlashOutcome(kind: SlashKind.exec, text: 'Not available in the demo.')`.
- `answerApproval`, `answerInput`, `answerClarify`: resume the paused script.
- `rename`, `setArchived`: change the in-memory rows.
- `search(query)`: matches titles and message text across the active profile, case-insensitive, and returns
  `SearchHit`s whose snippet marks the matched words.
- `modelOptions`, `switchModel`: from the content; a switch changes the in-memory model and emits
  `ModelChanged`.
- `events`: a broadcast stream. `reconnected` never emits.
- Nothing returns `Err`, except that a script may emit `TurnFailed` on purpose to show the failure card and
  retry.

### Scripts

A script is a list of steps, played in order on timers by `lib/demo/script_player.dart`:

| Step | Emits |
|---|---|
| `think(text)` | `ReasoningDelta` in chunks |
| `tool(name, input, output, duration)` | `ToolStarted`, then `ToolCompleted` after `duration` |
| `approval(command, ifApproved, ifDenied)` | `ApprovalAsked`, waits for the answer, then plays the matching branch |
| `secret(prompt)` | `InputAsked`, waits for any answer, then continues. The value is never stored or shown. |
| `say(markdown)` | `MessageStarted`, `TextDelta` in chunks, `MessageCompleted` |
| `context(used, limit)` | `ContextChanged` with a `ContextUsage` |
| `fail(message)` | `TurnFailed` |

Every turn starts with `BusyChanged(busy: true)` and ends with `BusyChanged(busy: false)`. Text streams at
about 40 characters per 30 ms tick. A whole turn takes 6 to 12 seconds. The player takes a clock and a timer
factory, so tests run it in fake time.

The suggested prompts:

1. **"Check disk space on my server"**: a `df -h` tool call, reasoning, an approval to run
   `docker image prune -a`, a sudo prompt, the prune's output, then a short report of the space freed.
   Denying the approval gives a reply listing what could be removed instead.
2. **"Why did last night's backup fail?"**: reasoning, a tool reading the backup log, a diagnosis (an
   expired B2 key) and a fixed `restic` command and config in code blocks.
3. **"Summarise this week's GitHub issues"**: a tool call to list issues, then a Markdown table of issues by
   label with a short note on what needs attention.
4. **"Restart the media server"**: an approval that fails on the first run (`fail`), so retry is shown; the
   retry succeeds.

The fallback reply: "This is a demo, so replies are pre-written and I can't act on that. Try one of the
suggestions, or [connect your own Hermes server](iris://leave-demo) to talk to your agent."

The content uses made-up hosts, names and keys. Nothing from the user's own server.

### Suggested prompts in the chat screen

An empty chat shows the prompts as tappable chips above the composer, only when demo mode is on. Tapping one
sends it like typed text. They disappear once the chat has a message.

## Errors

- The demo cannot fail by accident: its methods return `Ok`. The only failure shown is the scripted one.
- Leaving the demo during a turn cancels the script before the backend is disposed.
- Leaving a demo chat during a turn: the script keeps playing, as a real server would; reopening the chat
  shows the finished reply from the backend's transcript.
- No demo leaks into real use: the switch is never persisted, and only the providers listed above branch on
  it.
- An `http` address that is not private is refused before any request, with the message above.

## Testing and verification

- **Unit:**
  - the script player: event order, chunking, approval branches, the secret step not keeping its value,
    interrupt, steer, retry, `fail`, all in fake time
  - `DemoChatBackend`: paging, profiles, archive and rename, search snippets, create and title, the fallback
    for free text, model switch
  - `isPrivateHost`: each private range, Tailscale, `.local`, `.ts.net`, single-label, public IPv4 and names,
    IPv6
  - the provider branches: with demo off, each returns what it does today
- **Database:** migration 3 → 4 keeps existing rows with no mode.
- **Widget:**
  - the welcome screen's four rows and where each leads
  - each mode's example address and help, and "Change"
  - a public `http` address refused with the message
  - entering the demo, the Demo pill, "Leave demo"
  - the suggested prompts start a turn and disappear
  - `iris://leave-demo` leaves the demo
- **Goldens (light and dark):** the welcome screen, demo home with the pill, and a demo chat mid-turn with a
  tool card and an approval card.
- **Device (emulator, release build):**
  - the whole demo with the emulator in airplane mode, to show nothing is contacted
  - the cleartext check described above
  - a LAN `http` sign-in to the user's server, if it can be reached from the emulator's network

## Related, done separately

`mobile_scanner` is a dependency, but no screen scans a QR code, and the Hermes dashboard does not generate
pairing codes. For 1.0 it is removed, with the iOS camera usage string and the QR wording in the privacy and
support pages. QR pairing can return later as its own feature.

## Out of scope

- QR pairing.
- Saving the demo, or reaching it after a real server is connected.
- A demo that talks to a real model.
- Strict modes that restrict which addresses each mode accepts.
- Changing the probe, sign-in or Access logic.
- Localising the demo content.
