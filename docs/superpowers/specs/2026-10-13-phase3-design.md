# Phase 3 — history paging, Markdown, models, slash commands, profiles

**Date:** 2026-10-13. Builds on Phase 2 (`2026-10-13-chat-design.md`).

## Goals

1. **Fix history paging** so a conversation opens on its newest messages, and add **Show earlier messages**.
2. Render the agent's replies as **Markdown**.
3. Show the conversation's **model** and switch it.
4. **Slash commands**, with suggestions while typing.
5. **Profiles**: pick which agent profile the conversation list and new chats belong to.

## Verified on the user's server (Hermes 0.18.2, read-only probes, 2026-10-13)

### History paging (a Phase 2 bug)

`GET /api/sessions/{id}/messages?limit&offset&order=latest&include_compacted=true` **ignores `order=latest` and pages
from the oldest row.** The echoed `pagination` is `{limit, offset, returned}` with no `order` key. In a 184-message
conversation, `offset=0` returned ids 24267–24386 and `offset=120` returned 24387–24450. So Phase 2 opened long
conversations on their *oldest* 120 messages.

Conduit handles both kinds of server:
- If the echo includes `order: "latest"`, offsets count back from the newest row.
- If it doesn't, offsets count from the oldest row. The newest page then starts at `message_count − limit`, read from
  `GET /api/sessions/{id}` (which returns `message_count` among ~40 other fields). Verified: `offset = 184 − 120 = 64`
  returned ids 24331–24450, the newest 120.

An offset beyond the end returns `returned: 0`.

### Profiles

- `GET /api/profiles` returns `{profiles: [{name, is_default, model, provider, gateway_running, skill_count,
  description, ...}]}`. The names are default, ananta, asturii, indra and sully.
- The `profiles.list` RPC does **not** exist ("unknown method").
- The `session.list` RPC **ignores** a `profile` param: it returned the same 200 default-profile rows for `ananta`.
- `GET /api/profiles/sessions?profile=<name>&limit&offset&min_messages=1&archived=exclude&order=recent` returns
  `{sessions: [...rows with `profile`, `preview`, `title` (may be null)], total, limit, offset}`. That's 256 for
  default and 12 for ananta. **Without** `profile` it merges all profiles (512).
- A named profile's `GET /api/sessions/{id}` and `/messages` return **404 without `?profile=<name>`**, and work with
  it. Per Conduit, `session.resume` and `session.create` take a `profile` param, omitted for `default`.

### Models

- `model.options {explicit_only: true[, session_id]}` returns
  `{model, provider, providers: [{slug, name, is_current, is_user_defined, authenticated, models: [<id string>],
  total_models, source, pricing, capabilities}]}`. There are 7 providers. The current model is `gpt-6.1-sol` via
  `openai-codex`.
- Switching uses `config.set {key: "model", session_id, value: "<model> --provider <slug> --session"
  [, confirm_expensive_model: true]}` and returns `{value, confirm_required, confirm_message | warning, deferred}`
  (Conduit). If `confirm_required` is set, nothing changed: ask the person, then repeat the call with
  `confirm_expensive_model`. `deferred` means the switch takes effect after the current turn.
- The model in use arrives in `session.info {model, provider, ...}`, in `model.update {model, provider}`, and in the
  resume result's `info`.

### Slash commands

- `commands.catalog` returns `{pairs: [[name, description]] (189), categories: [{name, pairs}], canon: {alias: canonical},
  sub: {command: [subcommands]}, skill_count, warning}`.
- `slash.exec {session_id, command: <without the leading "/">}` returns `{type, output | message | notice, target}`.
  How Iris handles each type (from Conduit):
  - `exec` and `plugin`: show the output.
  - `send` and `skill`: send the message as a prompt.
  - `prefill`: put the message in the composer, and show any notice.
  - `alias`: run `target` (plus the original arguments), at most 3 levels deep.
  - If `slash.exec` returns an RPC error, try `command.dispatch {session_id, name, arg}` before giving up.
- Not verified live: running a command would act on a real session.

## Design

- `DashboardChat` is **scoped to one profile** (`DashboardChat(session, profile: 'default')`). The controller and
  screens never handle profiles. `activeChatProvider` builds one backend per active profile.
- `ChatBackend` changes:
  - `history(storedId, {HistoryCursor? before})` returns a `HistoryPage {items, earlier}`.
  - `conversations(int offset)` returns a `ConversationPage {items, total}` from the REST route.
  - New methods: `profiles()`, `modelOptions(...)`, `switchModel(...)`, `commands()` and `runSlash(...)`.
- Markdown uses `package:markdown` (Dart team, pure Dart) with Iris's own renderer, `IrisMarkdown`, built from
  design-system tokens, plus `url_launcher` for links. Only http, https and mailto links open.
- The chosen profile lives in memory per server and resets to `default` when the server changes.

## Out of scope

- Remembering the chosen profile across launches.
- Creating or editing profiles.
- Reasoning and fast toggles.
- Searching conversations.
- Cron and archived views.
- Images in Markdown (the alt text is shown instead).
- Syntax highlighting.
