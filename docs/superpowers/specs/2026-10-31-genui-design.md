# GenUI — Personal generated displays and replies

**Date:** 2026-10-31. **Branch:** `feat/genui`, cut from `main` at `b3caf31` (gpt_markdown, #35).
**Status:** design + plan only. Nothing is built yet; Phase 0 (live probe) must run before any code.

## Goals

Hermes replies in Iris with native UI built for the kind of work the person does, not only Markdown.

1. **Iris + the Iris skill, together.** The feature exists only when the Iris app talks to a Hermes that has the
   `hermes-iris` plugin (which ships the `iris-genui` skill). Telegram, the CLI, the web dashboard and other clients see
   ordinary text replies, as today.
2. **It studies your work first.** When the person turns GenUI on, Hermes reads what it already knows about them
   (sessions, memory, skills in use, scheduled jobs, Kanban) and proposes a **work profile** and a set of **personal
   displays** (templates) — e.g. a deploy-status card for an engineer, a P&L strip for a trader, a reading-list card for a
   researcher.
3. **Personal displays in replies.** Each reply can carry one or more surfaces rendered with Iris's own design tokens:
   a template filled with data, or a one-off composition from the Iris catalog.
4. **Personal reply types.** The agent can attach a reply kit (choices, a short form, a slider, a date, approve/reject)
   and Iris shows it above the composer; tapping it replies for you.
5. **It keeps learning.** Which displays get used, expanded or dismissed feeds back; Hermes proposes refinements and new
   displays, which the person approves in Iris.
6. **Opt-in, reversible, safe.** Off by default, per server and profile. The agent can only use components Iris ships;
   it cannot run code on the phone.

## Research summary

### GenUI SDK for Flutter (`genui`)

- `genui` 0.10.4 on pub.dev (publisher labs.flutter.dev, BSD-3, **alpha**: "the API will change, sometimes
  drastically"). Requires Flutter ≥ 3.35.7; Iris is on 3.41.6. Depends on `a2ui_core` and `json_schema_builder`.
- Pieces: `SurfaceController` (applies A2UI messages, owns surfaces and their `DataModel`), `Catalog` / `CatalogItem`
  (name + JSON schema + widget builder; only catalog widgets can render), `Surface` (widget for one surface id),
  `A2uiTransportAdapter` (parses streamed text into text events and A2UI messages), `Conversation` (the request/response
  loop) and `PromptBuilder` (system prompt from a catalog, 3–5k tokens).
- `genui_a2a` connects to A2A servers; `genui_a2ui` is discontinued. Neither fits Hermes, which speaks its own
  dashboard JSON-RPC.
- **Fit for Iris:** use `SurfaceController`, `Catalog`, `DataModel` and `Surface`. Do **not** use `Conversation`,
  `PromptBuilder` or the transport adapter: Hermes owns the agent loop and prompting, and Iris already owns the chat
  socket. Iris feeds A2UI messages into `SurfaceController.handleMessage` itself.

### A2UI protocol (v0.9 / v0.9.1)

- Declarative JSON, Apache-2.0, by Google with CopilotKit. v0.9.1 is current, v1.0 is a release candidate (adds action
  ids and `actionResponse`). The Flutter SDK targets v0.9.
- Server → client: `createSurface {surfaceId, catalogId, theme?, sendDataModel?}`, `updateComponents {surfaceId,
  components[]}`, `updateDataModel {surfaceId, path, value}`, `deleteSurface {surfaceId}`. Every message carries
  `"version": "v0.9"`.
- Components are a **flat adjacency list**; exactly one has `id: "root"`; children are id arrays or a template
  `{path, componentId}` repeated per array item. Props are literals, `{path}` bindings (relative inside templates) or
  `{call, args}` functions.
- Client → server `action {name, surfaceId, sourceComponentId, timestamp, context}` with `context` resolved from
  bindings. Local-only actions use `functionCall`.
- `catalogId` is an opaque URI fixed per surface; the client advertises `supportedCatalogIds` in transport metadata.
- Security model: data, not code; only catalog components render.

### Hermes extension points (docs, to be confirmed on 0.18.x in Phase 0)

- **Skills** (`~/.hermes/skills/<name>/SKILL.md`, frontmatter + Markdown, optional `references/`, `templates/`,
  `scripts/`): loaded on demand via `skill_view`, every skill is also a slash command. Plugins can bundle skills
  (`ctx.register_skill`, named `plugin:skill`).
- **Plugins** (`~/.hermes/plugins/<name>/plugin.yaml` + `__init__.py` with `register(ctx)`), disabled by default,
  enabled with `hermes plugins enable`. They can register **tools** (`ctx.register_tool`), **hooks** and slash commands.
- **Hooks** used here: `pre_llm_call(session_id, user_message, platform, …)` → returned `{"context": …}` is added to
  the user message (never the system prompt); `pre_tool_call` → can `block`; `transform_tool_result` → replaces what the
  model sees from a tool; `post_llm_call` → observe the reply; `on_session_start`.
  `ctx.register_system_prompt_section()` exists but is frozen per session and capped at 4,000 chars.
- **Dashboard plugin API:** `dashboard/manifest.json` with an `api` field pointing at a FastAPI `router` in
  `plugin_api.py`, served under `/api/plugins/<name>/`. Iris already uses this shape for `conduit_push` and `kanban`.
  The docs say plugin API routes **bypass session-token auth because the dashboard binds localhost** — the user's
  dashboard is reverse-proxied publicly, so the plugin must enforce auth itself (see Security).
- **Memory:** `MEMORY.md` (2,200 chars) and `USER.md` (1,375 chars) frozen into the system prompt per session;
  `session_search` (SQLite FTS5) over past sessions. These are the raw material for "study your work".

## Decisions

Proposed by Claude on 2026-10-31; each is open for the user to overrule before Phase 1.

- **D1 — One server package, `hermes-iris`.** A Hermes plugin that bundles the `iris-genui` skill, its tools, its hooks
  and its dashboard routes. Kept in this repo under `server/hermes-iris/` (Python, pytest) so app and server version
  together; installable with `hermes plugins install shreyas-kamat/iris --subdir server/hermes-iris` or by copying the
  folder. A skill alone cannot do it: it cannot store surfaces, gate on the client, or serve Iris.
- **D2 — Surfaces travel as a tool call, not as text.** The agent calls `iris_ui(messages=[…A2UI…], fallback="…")`.
  The tool validates the messages against the Iris catalog, stores them under the session, and returns a short receipt
  (`{surface_id, rev}`); `transform_tool_result` keeps the model's copy small. Iris sees `tool.start`/`tool.complete`
  for `iris_ui`, and reads the full surface from `GET /api/plugins/iris/surfaces/{session}/{surface}` when the event's
  arguments are truncated. Why not fenced ```` ```a2ui ```` blocks in the text: they leak into every other client, break
  `message.complete` rendering on the web dashboard, and cannot be validated before the user sees them. Fenced blocks
  stay as a degraded fallback if Phase 0 shows tools cannot be registered on the user's build.
- **D3 — Only Iris turns it on.** When a chat opens with GenUI enabled, Iris calls
  `POST /api/plugins/iris/sessions/{id}/genui` (`{enabled, catalog_version, templates_rev}`). The plugin's hooks act
  only for flagged sessions: `pre_llm_call` adds the GenUI context, `pre_tool_call` blocks `iris_ui` everywhere else.
  The flag is per runtime session and is re-sent after every reconnect/`session.resume`, like Iris already does for
  resume (see memory: runtime ids belong to the socket).
- **D4 — Flutter side uses `genui` behind a seam.** `genui` pinned exactly, used only inside
  `lib/features/genui/render/`. The rest of Iris sees `GenUiSurfaceView(surface)` and an `IrisCatalog`. If the alpha
  API breaks or misbehaves in the Phase 2 spike, the seam lets us swap to a hand-written A2UI v0.9 renderer (the
  protocol is small: four messages, flat components, path bindings) without touching the chat.
- **D5 — The catalog is Iris's design system, not Material.** Every component is built from `lib/design/` tokens and
  primitives, light and dark, iOS and Android feel. `catalogId`: `https://iris.shreyaskamat.in/genui/catalog/v1`.
- **D6 — "Custom displays" are templates over the catalog.** The agent never ships widgets. A template is a named
  A2UI component tree with a data schema, a "when to use" line and sample data, authored by the agent during study and
  approved by the person. A reply that uses a template sends `{template, data}`; the plugin expands it to A2UI. This
  keeps replies cheap (no component tree per turn) and displays consistent.
- **D7 — Text stays complete.** The skill requires every reply to make sense as text alone; a surface adds structure,
  never information that exists only in the UI. `iris_ui` takes a `fallback` Markdown summary that other clients and
  exports show.
- **D8 — Approval before personal anything.** Profile and templates are proposals until approved in Iris. Nothing
  personal is injected into turns until then. Refinements from the learning loop are proposals too.
- **D9 — Actions are messages.** A button in a surface sends a normal `prompt.submit` whose visible text is a
  human sentence ("Approve deploy of api to prod") and whose body ends with a machine block
  `<iris-action>{…A2UI action…}</iris-action>` that Iris hides when rendering. Local-only interactions (tabs, expanders,
  toggles bound to the data model) never reach the server.

## Architecture

```
 Iris (Flutter)                                    Hermes (hermes.shreyaskamat.in)
 ───────────────                                   ────────────────────────────────
 Settings ▸ Generative UI ──POST sessions/{id}/genui──▶ hermes-iris plugin
                                                        ├─ pre_llm_call: GenUI context (catalog digest,
 Chat ── prompt.submit (WS JSON-RPC) ──────────────────▶│   approved templates index, rules) for flagged sessions
                                                        ├─ tool iris_ui(messages|template+data, fallback)
      ◀── event tool.start / tool.complete (iris_ui) ───│   → validate → store surface → receipt
      ── GET surfaces/{session}/{surface} ─────────────▶│
 TranscriptView: UiSurface item → GenUiSurfaceView      ├─ tools iris_profile_*, iris_template_*  (study)
   └ genui SurfaceController + IrisCatalog              ├─ pre_tool_call: block iris_* outside flagged sessions
 Composer: ReplyKit surface                             ├─ post_llm_call: usage log for the learning loop
 Study / Displays screens ─ GET/POST profile, templates ┤
                                                        └─ skill iris-genui (+ /iris-study, /iris-refine)
                                                           store: ~/.hermes/iris/{profile,templates,surfaces,usage}
```

### Server: `hermes-iris`

```
server/hermes-iris/
  plugin.yaml                 name: iris, version, description, requires Hermes ≥ 0.18
  __init__.py                 register(ctx): tools, hooks, skill
  catalog/v1.json             the Iris catalog as JSON Schema (generated from Dart, checked in; see Catalog)
  genui/validate.py           A2UI v0.9 validation against catalog/v1.json (ids, root, child refs, props)
  genui/templates.py          template expansion {template, data} → A2UI messages
  genui/store.py              file store under ~/.hermes/iris/ (per profile), atomic writes
  genui/context.py            the pre_llm_call context: ≤ 2,500 chars, digest + template index
  skills/iris-genui/SKILL.md  authoring rules, when to render, examples
  skills/iris-genui/references/{catalog.md,patterns.md,study.md}
  dashboard/manifest.json     api: plugin_api.py   (no frontend bundle needed)
  dashboard/plugin_api.py     FastAPI router (below)
  tests/                      pytest: validation, expansion, hooks, routes
```

**Tools** (toolset `iris`):

| Tool | Purpose |
|---|---|
| `iris_ui(surface_id, messages? , template?, data?, fallback, placement="inline"\|"reply_kit")` | Render or update a surface |
| `iris_profile_get()` / `iris_profile_propose(profile)` | Read / propose the work profile |
| `iris_template_list()` / `iris_template_propose(template)` | Read / propose a template (status `proposed`) |

**Routes** (`/api/plugins/iris/…`), all requiring the dashboard session cookie (see Security):

| Route | Use |
|---|---|
| `GET capabilities` | `{version, a2ui:"v0.9", catalog_ids, features}` — Iris's probe |
| `POST sessions/{id}/genui` | Flag / unflag a runtime session |
| `GET surfaces/{session}/{surface}` | Full A2UI messages for one surface (history replay, truncated args) |
| `GET surfaces/{session}` | All surfaces in a stored session, for history load |
| `GET profile` · `PUT profile` | Work profile; `PUT` is the person's approval or edit |
| `GET templates` · `PUT templates/{id}` · `DELETE templates/{id}` | Review, approve, rename, retire |
| `POST feedback` | `{surface_id, template?, signal: used\|expanded\|dismissed\|not_useful}` |

All routes take `?profile=` like the rest of the dashboard (memory: named profiles 404 without it).

**Context budget.** `pre_llm_call` adds, per turn, at most ~2,500 characters: the rule set (one paragraph), a catalog
digest (component names + one-line purpose), and the approved templates index (`id — when to use — data keys`). Full
schemas live in the skill's `references/` and are pulled with `skill_view` only when the agent composes something new.
Phase 0 measures whether the hook text is stored in the session history and therefore needs hiding in Iris, like the
compaction rows.

### Study: how Hermes learns the person's work

`/iris-study` (a skill procedure, started by Iris in a dedicated "Iris setup" session):

1. Gather: `USER.md`/`MEMORY.md` (already in context), `session_search` over the last ~90 days (topics, recurring
   entities, recurring questions), skills used, cron jobs, Kanban columns and cards, connected toolsets.
2. Infer a **work profile**: roles/domains (≤ 5), recurring entities (services, tickers, repos, clients…), recurring
   reply shapes (status checks, comparisons, schedules, approvals, summaries), preferred density.
3. Propose **3–8 templates**, each mapped to a reply shape it saw repeatedly, with sample data taken from real past
   turns (redacted of secrets), and **2–4 reply kits** (e.g. "approve / hold / ask why" for deploy requests).
4. Save as proposals (`iris_profile_propose`, `iris_template_propose`) and finish with a text summary.

Iris shows the proposals on a review screen: each template rendered live with its sample data, with Keep / Rename /
Drop, and the profile as editable chips. Only kept items become active. Re-running study replaces proposals, never
approved items.

### Learning loop

- Iris posts feedback signals (`used`, `expanded`, `dismissed`, a long-press "Not useful").
- `post_llm_call` records which templates the agent used per turn (`usage.jsonl`, capped).
- `/iris-refine` (manual, or an optional weekly cron the person can turn on in Iris) reads usage and feedback and
  proposes edits, new templates and retirements. They appear in Iris as a badge on the Displays screen.

### Iris (Flutter)

```
lib/data/genui/
  genui_api.dart            REST client for /api/plugins/iris/* (ApiClient, _scoped profile)
  genui_models.dart         UiSurfaceRef, SurfaceMessages, WorkProfile, DisplayTemplate, ReplyKit, FeedbackSignal
  genui_parser.dart         iris_ui tool event → surface ref; <iris-action> block strip/parse
lib/features/genui/
  genui_settings.dart       per server+profile toggle (PreferencesStore), "needs plugin" state
  genui_controller.dart     flags sessions on open/resume, fetches surfaces, owns SurfaceController per chat
  render/iris_catalog.dart  CatalogItems built from lib/design (the only file importing package:genui widgets)
  render/surface_view.dart  GenUiSurfaceView: error/loading/fallback states around genui's Surface
  reply_kit.dart            surface docked above the composer
  study_screen.dart         start study, progress, review proposals
  displays_screen.dart      approved templates, preview with sample data, rename/retire, refinement badge
```

Changes to existing code:

- `ServerCapability.irisGenui('/api/plugins/iris/capabilities', 'Generative UI')` in `capabilities.dart`.
- `chat_models.dart`: new `UiSurface extends TranscriptItem {surfaceId, placement, fallback, rev}`.
- `chat_controller.dart`: a `ToolStarted`/`ToolCompleted` named `iris_ui` becomes a `UiSurface` instead of a
  `ToolCall`; history load maps stored `iris_ui` tool rows the same way; user text strips `<iris-action>` blocks.
- `transcript_view.dart`: `UiSurface` → `GenUiSurfaceView` inside the assistant block; reply-kit placement goes to the
  composer instead.
- `chat_backend.dart` (`DashboardChat`): after `create`/`resume`/`reconnected`, flag the session when GenUI is on.
- `demo/`: scripted surfaces so demo mode and App Store review can see the feature without a server.
- Settings: "Generative UI" section — toggle, plugin status, "Study my work", "Displays", "Reset".

### The Iris catalog (v1)

Built on Iris tokens; each item has a JSON schema exported to `server/hermes-iris/catalog/v1.json` by a Dart test that
fails when the two drift.

- **Layout:** `Column`, `Row`, `Card`, `Section` (titled), `Divider`, `Tabs` (local), `Expander` (local).
- **Text & data:** `Text` (variants from Iris typography), `Markdown` (uses existing `IrisMarkdown`), `KeyValue`,
  `Stat` (value, delta, trend), `StatRow`, `Badge`/`StatusPill`, `Table` (≤ 6 columns, horizontal scroll),
  `List` (templated rows), `Timeline`, `Checklist`, `Progress` (bar/ring), `CodeBlock`, `Diff`, `Image` (through the
  existing image-host allow-list), `Link` (opens through the existing link confirmation).
- **Charts:** `Sparkline`, `LineChart`, `BarChart`, `Donut` — custom painters on Iris palette; no chart package unless
  Phase 2 shows painting is too slow.
- **Inputs (reply kits and forms):** `Button`, `ChoiceChips` (single/multi), `TextField`, `Slider`, `Toggle`,
  `DatePicker`, `Stepper`, `ApproveReject`, `Submit` (sends the bound data as one action).

Limits enforced on both sides: ≤ 60 components per surface, ≤ 16 KB per message set, ≤ 4 surfaces per turn, nesting
depth ≤ 8, list templates ≤ 100 rows rendered.

## Security & privacy

- **Plugin routes must authenticate.** Hermes docs say plugin API routes skip session-token auth because the dashboard
  binds localhost; behind a public reverse proxy that is not true. Phase 0 tests whether `/api/plugins/*` sits behind
  the dashboard's cookie auth on the user's build. If not, `plugin_api.py` checks the dashboard session itself (or a
  per-device token minted from an authenticated route). No route ships without this.
- A2UI is declarative and catalog-only; the plugin and Iris both validate. Unknown components render as a "can't
  show this" chip with the fallback text, never as raw JSON.
- Images only from the existing image-host allow-list; links only through `links.dart` confirmation; no auto-fetch.
- Actions are ordinary user messages — visible in the transcript and in Hermes history; nothing executes on device.
- Study stays on the person's own server; sample data is redacted of secrets/keys by the skill and reviewed by the
  person before it is kept. "Reset" deletes `~/.hermes/iris/` for that profile.
- Logs: never log surface data or action contexts unredacted (`IrisLog.redact`).

## Risks

| Risk | Mitigation |
|---|---|
| `genui` is alpha; API churn | Exact pin; only `render/` imports it; hand-written renderer is the fallback (D4) |
| Tool args truncated in `tool.start` events | Surfaces fetched by id from the plugin store (D2) |
| Hook context stored in history | Probe in Phase 0; strip in `history_parser.dart` if so |
| Slow agent (95–160 s per reply on this server) | Surfaces arrive with the reply; templates keep payloads small; no extra round-trips per turn |
| Model writes invalid A2UI | Plugin validates and returns the error to the model so it retries; Iris shows fallback text |
| Prompt budget | ≤ 2,500 chars per turn; full schemas only via `skill_view` |
| Plugin routes unauthenticated | Phase 0 gate; plugin-side auth (Security) |
| Other clients see `iris_ui` tool rows | Tool is blocked outside flagged sessions; in flagged sessions other viewers see the fallback text |

## Out of scope (v1)

- Surfaces in voice calls (the voice screen shows the fallback line). Phase 9 candidate.
- Home-screen widgets / Live Activities built from templates. Phase 9 candidate.
- Sharing templates between people or a template marketplace.
- A2UI v1.0 (`actionResponse`); revisit when the Flutter SDK moves to it.

## Sources

- GenUI SDK: https://pub.dev/packages/genui · https://docs.flutter.dev/ai/genui/get-started · https://github.com/flutter/genui
- A2UI: https://a2ui.org/ · https://a2ui.org/specification/v0.9-a2ui/
- Hermes: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills ·
  …/features/plugins · …/features/hooks · …/features/memory · …/features/dashboard-plugins
