# Phase 4 — the everyday loop: memory, prompts, steering, retry, managing and finding chats, usage

**Date:** 2026-10-14. **Branch:** `feat/phase4`, cut from `feat/iris-design` at `337b3cf`.
Builds on Phase 3 (`2026-10-13-phase3-design.md`) and the Iris design (`../plans/2026-10-14-iris-design.md`).

## Goals

Close the gaps someone hits in a normal day of using Iris. No new tabs or surfaces such as Cron or Tasks.

1. **Remember** the appearance choice and the chosen profile across launches.
2. **Answer `sudo` and `secret` prompts** instead of declining them.
3. **Steer** a running turn from the composer.
4. **Retry** a failed turn.
5. **Rename, archive and unarchive** conversations, with an Archived view.
6. **Search** conversations from home.
7. **Syntax highlighting** in code blocks.
8. A **context ring** in the composer.
9. **Provider usage** on home, configurable in Settings.

Every feature follows the Iris design language. **UI and motion** below is part of the requirement, not a polish
pass to be done later.

## Verified on the user's server (Hermes, latest, read-only probes, 2026-10-14)

- **Provider usage.** `model.options {explicit_only: true}` adds `usage` to signed-in providers that can report it.
  - The first call returned none. A second call six seconds later returned `usage.windows` for `openai-codex`
    (`Session` 73% used, `Weekly` 48%) and `anthropic` (`Current session` 11%, `Current week` 87%).
  - Each window is `{label, used_percent, resets_at (ISO 8601), scope: "account" | "model"}`.
  - The top-level `provider` is the provider in use (`openai-codex`).
  - Hermes source (`hermes_cli/inventory.py::_apply_usage`) adds that a provider with a multi-account credential
    pool reports `usage.accounts: [{id, label, windows, state: ready|limited|unavailable|unknown, resets_at}]`
    instead. User-defined and signed-out providers never carry `usage`.
  - The values come from a server cache that refreshes in the background, and a snapshot older than 15 minutes is
    omitted.
- **Context.** Resuming an idle conversation returns `info` with `lazy` and **no** `context_*` fields, because no
  agent has been built yet. `session.usage {session_id}` returns `{calls, input, output, total, account_lines}`,
  also without `context_*`.
  - Hermes source and Conduit both read `context_percent`, `context_used` and `context_max` from `session.info`
    and from the `session.usage` event that the gateway emits after a turn.
  - Which event carries them on this server is checked in the live write test (see Testing and verification).
  - `context_percent` has been sent both as a fraction from 0 to 1 and as a percentage from 0 to 100.
- **Search.** `GET /api/sessions/search?q&limit[&profile]` returns `{results: [...]}`, one row per **matching
  message**. Each row has `session_id, title, snippet, role, last_active, started_at, message_count, preview,
  profile, archived, lineage_root, …`. Matched words in `snippet` are marked `>>>like this<<<`.
- **Slash commands.** The catalog has `/retry` ("Retry the last message (resend to agent)"), `/steer` and
  `/title`.
- **Archived list.** `GET /api/profiles/sessions?…&archived=only` returned `total: 0`. That means either there
  are no archived chats or the value is unsupported. The live write test archives a throwaway chat to find out.

From the reference clients (Hermes Desktop `apps/desktop`, Hermes Conduit). These involve writes, so they are not
probed read-only:

- **Steer:** `session.steer {session_id, text}`. A result of `{status: "rejected"}` means not applied. Hermes
  stores the steer as a user row with `display_kind: "steer"` once the agent reaches its next tool boundary.
- **Rename:** `PATCH /api/sessions/{id} {title, profile?}`. **Archive:** `PATCH /api/sessions/{id}
  {archived, profile?}`. The owning profile goes **in the body**. Desktop notes that without it, the write lands
  on the default profile's database.
- **sudo / secret:** these are server requests. `sudo` carries `{session_id, command}` and `secret` carries
  `{session_id, env_var, prompt}`. Both are answered with a response frame `{value}`, where `''` means cancel or
  skip. `request.cancel {id, reason}` withdraws one.

## Design

### Data layer

**Preferences.**
- New Drift table `Preferences(scope TEXT, key TEXT, value TEXT)` with primary key `(scope, key)`.
  - `scope` is `''` for app-wide keys and the server id for per-server keys.
  - Schema v3, migrated with `createTable`.
- `PreferencesStore` (`lib/data/prefs/preferences_store.dart`) has `Future<Map<(String, String), String>>
  loadAll()` and `Future<void> write(String scope, String key, String? value)`, where null deletes.
- `main()` loads everything before `runApp` and overrides `initialPreferencesProvider`, the same way
  `databaseProvider` is wired. The theme is therefore right on the first frame.

| Key | Scope | Value |
|---|---|---|
| `theme.skin`, `theme.mode`, `theme.followServerSkin` | `''` | enum name / bool |
| `profile` | server id | profile name |
| `usage.providers` | server id | JSON list of provider slugs, or `["@profile"]` (the default) |

- `ThemeController.build()` starts from the stored values, and each setter writes through.
- `ActiveProfile.build()` reads the stored profile for the active server, and `select()` writes it. When
  `profilesProvider` resolves without that profile, Iris falls back to `default` and deletes the key.
- A failed write is logged and never blocks the UI.

**`ApiClient`** gains `patch(path, body)`.

**`ChatBackend`** additions. All return `Result`. `DashboardChat` stays scoped to one profile.

| Method | Wire |
|---|---|
| `steer(runtimeId, text) → SteerOutcome {accepted, rejected}` | `session.steer` |
| `answerInput(InputRequest, String value)` | response frame `{value}` via `replyToServerRequest` |
| `rename(storedId, title)` | `PATCH /api/sessions/{id} {title, profile?}` |
| `setArchived(storedId, bool archived)` | `PATCH /api/sessions/{id} {archived, profile?}` |
| `archivedConversations(int offset) → ConversationPage` | `GET /api/profiles/sessions?…&archived=only` |
| `search(String query) → List<SearchHit>` | `GET /api/sessions/search?q&limit=30&profile` |

- `profile?` follows the existing `_scoped` rule: it's omitted for `default` and sent otherwise, in the query for
  `GET` and in the body for `PATCH`.
- Retry uses the existing `runSlash(runtimeId, 'retry')`.
- `modelOptions()` is unchanged on the wire. `CatalogParser.modelOptions` now also parses `usage` into
  `ProviderUsage {windows, accounts}`, where `UsageWindow {label, usedPercent, resetsAt, scope}` and `UsageAccount
  {label, state, windows, resetsAt}`.
- `SearchHit {storedId, title, snippet: List<SnippetRun{text, matched}>, role, lastActive, archived}`. The
  `>>>…<<<` markers are parsed into runs. A hit without a `session_id` is dropped.

**Events.**
- `presentedServerRequests` becomes `{approval, clarify, sudo, secret}`.
- New `InputAsked(InputRequest {requestId, sessionId, kind: sudo|secret, command, envVar, prompt})`. Requests
  still open when a conversation is reopened come back through `open_requests` on resume, which is already
  parsed.
- `request.cancel` already becomes `RequestWithdrawn`.
- New `ContextChanged(session, percent, used, max)`, parsed from `session.info`, the `session.usage` event and
  the resume result's `info`. The percent is normalised:
  - a value from 0 to 1 is multiplied by 100
  - if the percent is missing, it's computed from `used / max`
  - the result is clamped to 0–100
  - with no usable numbers, no event is emitted
- **Secrets never persist.** The typed value goes straight into the reply frame. It is not stored in state, not
  logged (the reply frame is excluded from frame logging), and not kept in the widget after it's sent: the field
  is cleared on submit.

### Chat screen

**Steer.** `ChatController.send(text)` stays the single entry point:
- If no turn is running, it calls `submit`, as today.
- If a turn is running, it calls `steer`:
  - **accepted:** the composer clears, and a local `UserTurn(steered: true)` is appended. Once Hermes stores the
    row, the next history load replaces it with the stored `display_kind: steer` row.
  - **rejected, and the turn has ended meanwhile:** the text is submitted as a prompt.
  - **rejected, and still running:** the text goes back into the composer, with the notice "Hermes couldn't take
    that mid-turn — send it when the turn ends."

**Retry.**
- The newest `Notice` created from `TurnFailed` gets `retryable: true`. It's only actionable while no turn is
  running and a runtime id exists.
- `ChatController.retry()` runs `runSlash(runtimeId, 'retry')` and handles the outcome like any slash command.
- When the turn settles, the newest history page is reloaded, so the failed exchange Hermes replaced isn't shown
  twice.

**Input prompts.**
- `ChatState.decisions` gains `InputRequest`, and `ChatController.answerInput(request, value)` answers it.
- After answering, the card shows "Sent" (or "Skipped" for an empty value) and collapses.
- On `RequestWithdrawn` it shows "Hermes stopped waiting for that" and collapses.
- Phase 2's limitation stands: a prompt for a conversation that isn't open waits until it is opened, or until the
  gateway's deadline.

**Context ring.** `ChatState.context` is `ContextUsage? {percent, used, max}`. The composer shows it once it's
non-null.

**Syntax highlighting.**
- `_CodeBlock` uses `re_highlight` (pure Dart, highlight.js v11 grammars) when the fence names a language
  `re_highlight` knows, after an alias map: `sh`, `zsh`, `shell` and `console` map to `bash`; `py` to `python`;
  `ts` to `typescript`; `js` to `javascript`; `yml` to `yaml`; `md` to `markdown`; `kt` to `kotlin`; `rs` to
  `rust`; `golang` to `go`.
- There is no automatic language detection: a block with no language, or an unknown one, renders plain.
- Highlighting runs only once the message is complete and the block is at most 20,000 characters. A streaming
  block is plain and cross-fades to highlighted once on completion. Highlighted spans are cached per `(language,
  code)`.
- Colours come from a new `IrisCodeColors` token set, derived from the active palette in both light and dark:
  `keyword`, `string`, `number`, `comment`, `title` (functions and classes), `type`, `attr`, `meta`, `addition`,
  `deletion`. Every role clears the existing contrast floor against `surfaceSunken`, and `contrast_test.dart`
  gains these roles.

### Home

The layout, from top to bottom:

1. **Orb hero.** Unchanged.
2. **Usage strip.** One row per configured provider. It's hidden when nothing reports usage.
   - **Rows:** the configured list is `["@profile"]` by default. `@profile` resolves to `model.options`'
     top-level `provider` for the active profile. Duplicates are dropped, and so is any provider without usage.
   - **Collapsed row:** the provider name, an `IrisGauge` for its tightest window (the highest `used_percent`)
     stretched to the row width, and the caption "**27% left** · resets in 2h 36m". A pooled provider shows its
     best account (the lowest used) in the collapsed row.
   - **Expanded row (tap):** every window, labelled as the server labels it, and for pooled providers one
     sub-row per account with its `state`.
   - **Data:** `providerUsageProvider` calls `modelOptions()` when home appears and on pull-to-refresh. If a wanted
     provider has no usage yet, it asks once more after 5 s, which covers the server's cold cache.
3. **Search field**, revealed by pulling the list down and hidden again when the list scrolls up while the field
   is empty.
   - Typing filters the loaded rows by title and preview straight away.
   - After 250 ms of quiet, `search(query)` replaces those results. Hits are grouped by `storedId`, keeping each
     conversation's best snippet in server order. Archived hits are left out.
   - A failed server search keeps the local matches and adds a quiet "Couldn't search the server" line.
   - Clearing the field restores the list.
4. **Conversation rows.**
   - A long press (Android), or the context menu (iOS) through `design/platform/adaptive.dart`, offers **Rename**
     and **Archive**.
   - **Rename** opens an `IrisSheet` with an `IrisField` holding the current title, selected. Saving updates the
     row optimistically and rolls it back with a notice if the server refuses.
   - **Archive** removes the row optimistically and shows a snackbar with **Undo**, which unarchives it.
5. **"Archived"** at the end of the list (shown only when the archived total is above zero, or always when that
   total is unknown).
   - It opens `ArchivedScreen`, paged through `archivedConversations`, with an **Unarchive** action per row.
   - An archived conversation opens normally. Sending in it first asks "Unarchive this chat?" and unarchives on
     confirmation.

### Settings

- **Appearance** rows are unchanged, but now remembered.
- New **Usage on home** row, showing a summary such as "Profile's provider" or "OpenAI Codex + 1". It opens
  `UsageSettingsScreen`:
  - **Main:** "Profile's provider" (the default) or any provider that reports usage.
  - **Secondary:** "None" (the default) or a provider.
  - **+ Add provider:** further rows, each removable by swiping (Android) or with an edit mode (iOS).
  - The picker lists only providers whose `model.options` row carries `usage`, plus "Profile's provider" for
    Main. Choices are saved to `usage.providers` per server.

## UI and motion

The design file (`design/Iris App.dc.html`) and the tokens are the source of truth.
- Widgets read palette **roles** (`context.palette`), `context.type`, `IrisSpace`, `IrisRadius` and `IrisStroke`.
  No widget holds a hex value.
- Taps go through `IrisPressable`, so they get the press scale on `IrisSprings.snappy`.
- Motion through **space** uses a spring (`SpringBuilder` or `springTo`), and changes of **appearance** use
  `IrisDurations` with `IrisCurves`.
- Haptics come from `IrisHaptics` and are named by meaning.
- **Reduced motion** (`MediaQuery.disableAnimationsOf`) jumps every animation to its end state and runs no
  ticker, so tests that use `disableAnimations: true` settle.

| Feature | Look | Motion | Haptic |
|---|---|---|---|
| Steer | When the composer has text during a run, a round **steer** button (arrow-turn icon, the `thinking` hue) appears beside the stop orb, using `IrisCircleButton`. A steered bubble carries a small "Steered" caption in `inkMuted`. | The steer button scales and fades in on `snappy` as text appears, and leaves on `IrisCurves.exit`. The bubble enters like any user turn: rising 8 pt and fading in on `standard`. | `commit` on send; `failed` on rejection |
| Retry | The design's failed-turn card: a rounded (`IrisRadius.lg`) wash of the `failed` hue at low alpha with a hairline border, a title such as "Gateway timed out" and a monospace detail line, plus a pill **Retry** button filled with the `failed` hue. | While retrying, the pill becomes a small spinner and the header orb takes the `loading` state, cross-fading over `IrisDurations.hue`. The card collapses on `standard` when the retry starts streaming. | `commit` |
| sudo / secret card | An `IrisCard` in the decision-card slot: a lock glyph, the title, the sudo `command` in a sunken monospace well, a masked `IrisField` with a show/hide eye toggle (autocorrect, suggestions and autofill off), **Cancel** (quiet) and **Submit** (accent). | It arrives like the approval card (rising and fading in on `standard`). The field takes focus as it arrives. The answered and withdrawn states cross-fade, then the card collapses its height on `gentle`. | `gate` when it arrives; `commit` on submit |
| Context ring | A 20 pt ring with a `IrisStroke.ring` stroke, a track in `surfaceSunken`, and a fill tinted by the same rule as `IrisGauge` (neutral below 70%, shading through `working` to `failed`). It shares that tint function with `IrisGauge`. | The fill springs to each new value on `standard`. It fades in on first data. | — |
| Context sheet | `IrisSheet`: the large figure "18%" in the serif role, "48,210 of 272,000 tokens" and the model name. | The standard sheet spring (`gentle`). | `selection` on open |
| Usage strip | Rows on `surface` with hairline separators. The provider name in `ink`, the caption in `inkMuted` with the "left" figure in `ink` and medium weight, and a full-width `IrisGauge` (6 pt). A pooled account's `limited` or `unavailable` state shows as an `IrisChip`. | Gauges spring from 0 on first appearance and to new values on refresh. Tapping expands the height on `gentle`, and the windows stagger in 30 ms apart on `standard`. Skeleton shimmer (`IrisSkeleton`) shows while loading. | `selection` on expand |
| Search | A pill `IrisField` with a magnifier and a clear button, on `surfaceSunken`. Hit rows show the title and a two-line snippet with matched runs in `ink` and medium weight, the rest in `inkMuted`. | Pulling past 56 pt reveals the field, which springs to rest on `standard`. Results cross-fade over `IrisDurations.normal` when the server replaces the local matches. A thin indeterminate line runs under the field while a search is in flight. | `selection` when the field locks open |
| Rename | `IrisSheet` titled "Rename", with the field pre-selected and `IrisSheetActions` (Cancel / Save). | The standard sheet spring. The row's title cross-fades to the new one. | `commit` on save |
| Archive / undo | A snackbar on `surfaceRaised` with an "Undo" text button in the accent. | The row slides out to the leading edge and its height collapses on `standard`. Undo springs it back into place. | `commit` on archive |
| Archived screen | The same row style as home, under a page title. **Unarchive** is a trailing quiet button. An empty state uses `IrisEmptyState` ("Nothing archived"). | Pushed with `IrisPageRoute`. An unarchived row collapses out on `standard`. | `commit` |
| Usage settings | `IrisSettingsGroup` sections Main / Secondary / Others, with each choice made in an `IrisSheet` list (`IrisListRow`) that shows a checkmark for the selection. | Rows insert and remove with a height animation on `standard`. | `selection` |
| Highlighted code | The existing `_CodeBlock`, with only the text colours changing. | A single cross-fade from plain to highlighted over `IrisDurations.normal`, on completion. | — |

**Friendliness rules:**
- Every destructive or surprising action can be undone (archive), or asks first (sending in an archived chat).
- Errors say what happened and what to do, in Iris's voice, with no raw codes in the primary line. The code can
  go in the card's monospace detail line.
- Every icon-only control has a semantics label: "Steer", "Context window, 18 percent", "Show password" and so
  on.
- Tap targets are at least `IrisSize.minTapTarget`.

## Errors

- Every server call returns `Result`.
- Optimistic edits (rename, archive, unarchive) roll back on failure, with a notice.
- If usage fails, the strip is hidden rather than showing an error, because usage is ambient information.
- If the server search fails, the local matches stay.
- If a preference write fails, it's logged only.

## Testing and verification

- **Unit:**
  - `PreferencesStore` and the v3 migration.
  - The parsers: `InputRequest`, `SearchHit` snippet runs, `ProviderUsage` windows and accounts, context percent
    normalisation for fractions, percentages, values derived from `used`/`max`, and absent values.
  - Every new `DashboardChat` method against the scripted socket and HTTP stubs.
  - Steer/submit routing and rejection fallback in `ChatController`.
  - Retry outcome handling.
  - `@profile` resolution.
- **Widget:**
  - The steer button appearing and disappearing.
  - The retry card.
  - `InputCard` submit, cancel and withdrawn, including the field being cleared after send.
  - Rename and archive with undo.
  - Search, local then server, and its failure path.
  - The usage strip collapsed, expanded and empty.
  - The context ring and its sheet.
  - Usage settings choices persisting.
  - The theme and profile surviving a rebuilt `ProviderContainer` built from stored preferences.
- **Contrast:** the `IrisCodeColors` roles, in light and dark.
- **Goldens (light and dark):**
  - home with the usage strip and the search field open
  - a search result list
  - a chat with a highlighted code block, the context ring and a sudo card
  - the failed-turn card
  - the archived screen
  - usage settings
- **Live, read-only:** model-options usage on a second call, the search row shape, and the archived list.
- **Live write** (`live_write`, run explicitly):
  - a steer during a real turn
  - `/retry` after an interrupted turn, recording what `slash.exec` returns
  - rename and archive/unarchive on a throwaway conversation, checking it appears under `archived=only`
  - which event carries `context_*` after a turn
- **Device** (Pixel 9 emulator):
  - the whole flow
  - a cold restart keeping the theme, profile and usage choices
  - reduced motion turned on, where everything should still work and nothing should animate

## Out of scope

- Deleting conversations.
- Pinning, branching and `/undo`.
- Queueing a prompt for after the turn (`/queue`) and the `busy` policy setting.
- `vault.*` prompts and MCP setup prompts, which are still declined.
- Usage alerts or notifications.
- Redeeming Codex reset credits.
- Searching across all profiles at once.
- Automatic language detection for code blocks.
