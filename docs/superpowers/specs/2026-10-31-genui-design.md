# GenUI — Personal generated displays and replies

**Date:** 2026-10-31, revised 2026-11-04 (OpenUI Lang replaces A2UI + the `genui` package). **Branch:** `feat/genui`.
**Status:** design + plan. Phase 0 (live probe) ran 2026-11-06/07: **go** for OpenUI Lang; findings in
[Phase 0 findings](#phase-0-findings-2026-11-07). Nothing else is built yet.

## Goals

Hermes replies in Iris with native UI built for the kind of work the person does, not only Markdown.

1. **Iris + the Iris skill, together.** The feature exists only when the Iris app talks to a Hermes that has the
   `hermes-iris` plugin (which ships the `iris-genui` skill). Telegram, the CLI, the web dashboard and other clients see
   ordinary text replies, as today.
2. **It studies your work first.** When the person turns GenUI on, Hermes reads what it already knows about them
   (sessions, memory, skills in use, scheduled jobs, Kanban) and proposes a **work profile** and a set of **personal
   displays** (templates), e.g. a deploy-status card for an engineer, a P&L strip for a trader.
3. **Personal displays in replies.** Each reply can carry surfaces rendered with Iris's own design tokens: a template
   filled with data, or a one-off composition from the Iris catalog.
4. **Personal reply types.** The agent can attach a reply kit (choices, short form, slider, date, approve/reject) shown
   above the composer; tapping it replies for the person.
5. **It keeps learning.** Which displays get used, expanded or dismissed feeds back; Hermes proposes refinements and new
   displays, which the person approves in Iris.
6. **Opt-in, reversible, safe.** Off by default, per server and profile. The agent can only use components Iris ships;
   it cannot run code on the phone.

## Research summary

### OpenUI (openui.com, `thesysdev/openui`) — what it is and how it generates UI

OpenUI is an open, compact, **streaming-first language** that an LLM writes to describe a UI from *your* components.
The flow has four steps, and every one maps to something we can own in Dart/Python:

1. **Component library** — the host defines components (name, positional props, description). In the React SDK this is
   `defineComponent` + Zod schemas; in the spec it is a language-neutral **LibrarySpec** JSON (`id`, `version`, `root`,
   JSON Schema per component, `signature`, `description`, `componentGroups`, custom `functions`, custom `actions`).
   **Key order of `properties` is the positional argument order.**
2. **Prompt generation** — one deterministic function, `generateSystemPrompt({library, promptOptions})`, turns the
   LibrarySpec into the system-prompt text: syntax rules, one line per component
   (`Button(label: string, action?: ActionExpression, variant?: "primary" | "secondary") — A clickable button`),
   built-ins, hoisting/streaming guidance. Same inputs → byte-identical prompt. The prompt only teaches features the
   client supports.
3. **Model output** — the model writes OpenUI Lang, one statement per line:
   ```
   root = Stack([header, stats])
   header = CardHeader("Deploys", "last 24 h")
   stats = StatRow([Stat("api", "ok", "up"), Stat("web", "degraded", "down")])
   ```
   Positional args (no repeated JSON keys → "up to 67 % fewer tokens", the project's own claim, unverified by us),
   `null` skips an optional arg, forward references allowed (hoisting), `root` is the entry, `$state` variables with
   two-way binding on inputs, `@Builtin` functions (`@Count`, `@Sum`, `@Filter`, `@Sort`, `@Each`, …) and actions
   (`@Run`, custom ones), `Query`/`Mutation` bound to host tools. Comments `//` and `#`.
4. **Client parse + render** — a streaming parser takes the *full text so far* on every chunk, closes open
   strings/brackets implicitly, and returns a tree plus `meta {incomplete, unresolved, statementCount,
   validationErrors}`. Rule: **every partial program is a valid page**; an invalid argument degrades its prop, an
   invalid component is dropped, nothing crashes. Structured errors carry `code`, `statementId`, `message` and a `hint`
   (the component signature) — which is exactly what a retry-to-the-model loop needs.

**Why this matters for Iris.** The spec (`spec/language.md`, `prompt.md`, `overview.md`) is language-neutral and ships
**conformance fixtures** (`spec/fixtures/1.0/`: plain-text cases + expected JSON) "so a client in any language can
check it parses, streams, evaluates and runs actions the same way as the reference". There is no Flutter/Dart
implementation (React, Vue, Svelte, and a React Native integration are the documented targets; an unofficial Elixir one
passes the 1.0 suite). So "OpenUI native to Flutter" = **write the Dart implementation of the 1.0 spec and run the
fixtures against it**. Not needed: OpenUI Gateway/Autofix (hosted; we validate in our own plugin), the Agent Interface
(React chat UI), or any JS runtime in the app.

### Why OpenUI Lang beats A2UI/`genui` for Iris (the previous design)

| | A2UI v0.9 + `genui` 0.10.4 (old D2/D4) | OpenUI Lang 1.0 (new) |
|---|---|---|
| Payload | JSON messages, flat adjacency list, repeated keys | Positional lines, ~⅓–½ the tokens (matters at 95–160 s/reply) |
| Streaming | Whole message set must parse | Every prefix renders; skeleton → data |
| Errors | Reject whole payload | Drop smallest unit, render the rest; hints for the model |
| Dependency | `genui` alpha ("API will change drastically"), Material-leaning `Surface`, `Conversation` we can't use | Our own ~1.5k-line pure-Dart package; no alpha dependency |
| State/logic | `DataModel` + paths + function calls | `$vars`, ternaries, `@Each`/`@Filter`, 2-way binding — displays compute locally |
| Conformance | A2UI schemas | Language-neutral fixtures to port Python + Dart against |
| Theming | Catalog widgets still ours | Same: catalog is ours |

Cost: we own a parser, a prompt generator, a validator and a renderer. All four are small and fixture-tested, and the
old plan already budgeted a hand-written fallback renderer.

### Hermes extension points (docs; confirmed on release 2026.9.24 in Phase 0, see findings below)

- **Skills** (`~/.hermes/skills/<name>/SKILL.md`): loaded on demand via `skill_view`; plugins can bundle skills
  (`ctx.register_skill`, named `plugin:skill`).
- **Plugins** (`~/.hermes/plugins/<name>/plugin.yaml` + `__init__.py` `register(ctx)`), disabled by default; register
  **tools**, **hooks**, slash commands.
- **Hooks:** `pre_llm_call` → `{"context": …}` is appended to the user message (not the system prompt);
  `pre_tool_call` can `block`; `transform_tool_result` rewrites what the model sees; `post_llm_call`; `on_session_start`.
  `ctx.register_system_prompt_section()` is frozen per session, capped at 4,000 chars.
- **Dashboard plugin API:** `dashboard/manifest.json` + FastAPI `router` in `plugin_api.py` under
  `/api/plugins/<name>/` (Iris already uses this for `conduit_push` and `kanban`). Docs say plugin routes bypass
  session-token auth because the dashboard binds localhost; on this server they sit behind the dashboard login
  (Phase 0.2).
- **Memory:** `MEMORY.md` (2,200 chars), `USER.md` (1,375 chars) frozen per session; `session_search` (FTS5) over past
  sessions — the raw material for "study your work".

## Phase 0 findings (2026-11-07)

Measured on the user's server (Hermes release 2026.9.24, source tag `v2026.9.24`) with the throwaway `iris-probe`
plugin (`server/hermes-iris-probe/`) and `test/live/genui_probe_live_test.dart`, `genui_fluency_live_test.dart`. Model
`claude-sonnet-5`, provider anthropic.

**Hermes (0.1–0.8)**

- **Plugin shape confirmed.** `register(ctx)` with `ctx.register_tool(name, toolset, schema, handler)` (handler
  `(args: dict, **kw) -> str`) and `ctx.register_hook(name, cb)`. Dashboard routes mount at `/api/plugins/<name>/` only
  when the plugin is in `plugins.enabled`, and the API module is imported separately from the plugin package, so the
  two share state only through files (the real plugin's store must be file-based, which D1 already assumes).
- **0.2 Auth: protected.** `/api/plugins/<name>/*` returns 401 with Cloudflare Access headers alone and 200 with the
  dashboard login. The plugin need not add its own auth check; it should still read the caller's identity if it needs
  one (hooks see `sender_id` `basic:admin`).
- **0.3 Tool events.** `tool.start` carries the real name, a stable `tool_id` and the **full args** (11,892 chars
  arrived untruncated); `tool.complete` repeats the args with `result`/`duration_s`. Args never stream: `tool.start`
  arrives only after the whole call is generated (4 s / 28 s / 39 s for 1.1k / 7.9k / 11.9k chars). `tool.generating`
  carries the name only. **Plugin tools are deferred** behind Tool Search: the model sees `tool_search`,
  `tool_describe` and `tool_call` bridges, not `iris_ui` (Hermes defers every plugin tool unless
  `tools.tool_search.enabled: off`, which would also un-defer every MCP tool). First use cost about 13 s of discovery,
  and `tool.generating` then names the wrapper (`mcp__tool_call`), so Iris cannot tell an `iris_ui` call is coming.
  Consequences: the `pre_llm_call` context names the tool and its argument shape so the model can go straight to
  `tool_call("iris_ui", …)`; Iris shows a generic "composing" state on `tool.generating` and only identifies the
  surface at `tool.start`. No progressive rendering over the tool call (D2 trade-off confirmed).
- **0.4 Hook context is not stored.** `pre_llm_call`'s `{"context": …}` reaches the model but the stored user row holds
  only the typed text, so `history_parser.dart` needs no stripping. Hooks receive the **stored** session id
  (`20261106_…`), never the runtime id; `turn_id` is `<stored>:<stored>:<hex>`.
- **0.5 Flag lifetime.** A fresh WebSocket plus `session.resume` returned the same runtime id and the hooks still saw
  the session as flagged. Key the flag by **stored id** (the only id hooks see); it lives in the plugin's file store,
  so it survives reconnects and restarts. Iris still re-sends it after resume (cheap, idempotent).
- **0.6 History rows.** Stored rows have many fields (`display_kind`, `display_metadata`, `tool_call_uid`, …); a tool
  row's `content` is the handler's return string and `tool_name` is the real name. `HistoryParser` parses the
  session without errors.
- **0.7 Platform.** Dashboard WebSocket sessions report `platform: "desktop"`. Telegram and CLI were not measured;
  they never flag sessions, so the value is informational.
- **0.8 Rewriting (D2b): partly.** `transform_llm_output(response_text, …)` replaced the text in `message.complete`
  and in the stored row, but `message.delta` had already streamed the original. It also fires for background
  (auxiliary) calls with a different `turn_id`. So a fenced block could be removed from the final and stored text
  for other clients, but they would see it while it streams. **D2b is not in v1.**
- **Ops note.** Every Hermes update that replaces the bundled Python leaves a running dashboard on a deleted
  interpreter; agent builds then fail with `agent_init_failed` / `[Errno 2]` until `hermes-dashboard` is restarted.

**OpenUI (0.9, 0.10)**

- **0.9 Source.** `thesysdev/openui` at `eea983e31730677f794f3873e4ee9efa03e065eb`, MIT (© Thesys Inc.): vendoring the
  fixtures is allowed with the licence notice. `spec/fixtures/1.0/`: 58 cases (actions 10, editing 5, entry 7, errors
  12, evaluation 9, grammar 7, state 5, streaming 4), 12 with `interactions.json`; files `library.json` (root `Stack`,
  12 components, `@Upper`, `@CopyToClipboard`), `input.oui` or `chunks.json`, `expected.json`, `patch.oui`,
  `validation.json`. Errors compare as a multiset, unresolved and orphans as sets; a streamed parse must equal the
  batch parse. (`language.md`'s header says 1.1; the fixtures and changelog say 1.0.) Answers:
  - `@Each`: the loop variable exists only inside the template and shadows statements of the same name; nested loops
    with the same name shadow; no index variable; the element is substituted before deferred evaluation. No fixture
    covers it, so Iris adds its own tests.
  - Actions: one step needs no `Action([...])` wrapper; a plain list of steps is data, not an action.
  - Bindable props are marked only in the signature (`$binding<type>`), never in the JSON Schema.
  - A restricted action slot is an `anyOf` of `$ref`s to action names; it shapes the prompt and schema only, and 1.0
    accepts any action there.
  - Edit mode (`language.md` §7) is **out of v1**.
  - Severity: only a non-fatal `no-root` carries `"severity": "warning"`; fatal are `no-root` with no fallback,
    `parse-failed` and `parse-exception`.
  - The prompt generator (`packages/lang-core/src/parser/prompt.ts`) has no fixtures; byte-identical output is checked
    against the TypeScript. Its inline mode contradicts itself ("ENTIRE response must be valid openui-lang" vs "output
    ONLY the changed statements" with edit mode off), so Iris writes its own preamble.
  - The npm `lang-core` package runs PostHog telemetry on install (off with `DO_NOT_TRACK=1`); Iris uses none of the
    npm packages, only the spec and fixtures.
- **0.10 Fluency: go.** The generated prompt for the fixture library (12 components, bindings on; 8,000 chars) was sent
  as plain text, then five requests (weather card, phone comparison table with a computed average, task form with
  bound fields and reset, email cards from one array with `@Each`, spending dashboard with `@Sum`/`@Max` and a
  conditional tag). **5/5 first-try valid** by OpenUI's own parser (no errors, unresolved refs or orphans), no Markdown
  fences, `root` first, and correct by eye. Replies took 6–7 s each. Size: 778 tokens for all five versus 1,521 for the
  same displays as A2UI JSON (o200k tokenizer as a proxy): **A2UI ≈ 2× larger**, and the model's A2UI was looser than
  the real schema, so the true gap is wider.

## Decisions

Proposed by Claude, 2026-10-31; D2, D4, D5, D6, D9 revised 2026-11-04. Each is open for the user to overrule.

- **D1 — One server package, `hermes-iris`**, a Hermes plugin bundling the `iris-genui` skill, tools, hooks and
  dashboard routes. Lives in this repo (`server/hermes-iris/`, Python + pytest) so app and server version together.
- **D2 (revised) — Surfaces are OpenUI Lang programs delivered by a tool call.** The agent calls
  `iris_ui(surface_id, code, fallback, placement)` where `code` is an OpenUI Lang program. The plugin parses and
  validates it against the Iris LibrarySpec, stores it, and returns a short receipt, *or* structured errors with hints so
  the model corrects and retries. Iris reads `tool.start`/`tool.complete` for `iris_ui` and fetches the stored program by
  id when event args are truncated. Reason for a tool and not a fenced block in the reply text: validation before the
  person sees it, no leakage into other clients. **Streaming trade-off:** a tool call arrives whole, so the
  "render while generating" benefit is lost (Phase 0.3: args arrive complete, but only once fully generated).
  D2b, a fenced ```` ```openui ```` block in `message.delta` stripped for non-Iris sessions, is **not in v1**:
  `transform_llm_output` cleans the final and stored text but not the live deltas (Phase 0.8).
- **D3 — Only Iris turns it on.** `POST /api/plugins/iris/sessions/{id}/genui` flags a session by its **stored** id
  (the only id hooks see); hooks act only for flagged sessions; Iris re-sends it after every reconnect/`session.resume`.
- **D4 (revised) — A native Dart OpenUI implementation, no `genui` dependency.** Pure-Dart package
  `packages/openui_lang/` (no Flutter import): lexer, streaming parser, expression evaluator, `$` store, structured
  errors, `LibrarySpec` model, prompt generator. It passes the vendored 1.0 conformance fixtures (licence of
  `thesysdev/openui` checked before copying; keep attribution). Flutter side `lib/features/genui/render/` maps parsed
  `ElementNode`s to Iris widgets. `genui`/A2UI are dropped from the plan.
- **D5 (revised) — The Iris catalog is defined once, in Dart, and exported as a LibrarySpec.** Each component is a Dart
  `IrisComponent(name, props (ordered, typed), description, builder)`. A test exports
  `server/hermes-iris/catalog/v1.library.json` and fails on drift; Python builds the prompt and validator from that
  file. Built from `lib/design/` tokens, light/dark, iOS/Android feel. Library id
  `https://iris.shreyaskamat.in/genui/library/v1`.
- **D6 (revised) — Templates are OpenUI programs with a `data` contract.** A template is a stored program that reads a
  top-level `data` object (`data.service`, `@Each(data.rows, "r", Row(r.name, r.state))`). A reply sends
  `iris_ui(template="deploy-status", data={…})`; the plugin validates `data` against the template's JSON Schema and
  expands to `data = {…}` + the template body. Cheap per turn, consistent displays, still plain OpenUI Lang so the
  review screen renders them with the same code path.
- **D7 — Text stays complete.** Every reply makes sense as text alone; `fallback` Markdown is required.
- **D8 — Approval before personal anything.** Profile and templates are proposals until approved in Iris.
- **D9 (revised) — Actions are messages via one custom action.** The library defines `@Ask(text, context?)`
  (and `Button`/`ApproveReject`/`Submit` call it). It submits a normal `prompt.submit` whose visible text is `text` and
  whose body ends with `<iris-action>{"surface","component","context"}</iris-action>`, hidden in the transcript. Local
  interactions (`$tab`, expanders, toggles, filtering with `@Filter`) never reach the server. `Query`/`Mutation` are
  **not** in the v1 library (see Out of scope).
- **D10 (new) — Server-side parser in Python, same fixtures.** The plugin needs to parse and validate to give the model
  corrective errors. A small Python port of lexer+parser+validator (no renderer, no evaluator beyond what validation
  needs) is tested against the same vendored fixtures. Divergence between Dart and Python is caught by running both
  against one fixture set in CI. Fallback if the port is too costly: the plugin only checks balanced syntax and size
  limits and Iris reports render errors back to the model on the next turn (worse retry loop, so not preferred).

## Architecture

```
 Iris (Flutter)                                    Hermes (hermes.shreyaskamat.in)
 ───────────────                                   ────────────────────────────────
 Settings ▸ Generative UI ──POST sessions/{id}/genui──▶ hermes-iris plugin
                                                        ├─ pre_llm_call: GenUI context (generated prompt digest,
 Chat ── prompt.submit (WS JSON-RPC) ──────────────────▶│   approved templates index, rules) for flagged sessions
                                                        ├─ tool iris_ui(code | template+data, fallback)
      ◀── event tool.start / tool.complete (iris_ui) ───│   → parse → validate → store → receipt | errors+hints
      ── GET surfaces/{session}/{surface} ─────────────▶│
 TranscriptView: UiSurface item → OpenUiView            ├─ tools iris_profile_*, iris_template_*  (study)
   └ packages/openui_lang parser + IrisLibrary          ├─ pre_tool_call: block iris_* outside flagged sessions
 Composer: ReplyKit surface                             ├─ post_llm_call: usage log for the learning loop
 Study / Displays screens ─ GET/POST profile, templates ┤
                                                        └─ skill iris-genui (+ /iris-study, /iris-refine)
                                                           store: ~/.hermes/iris/{profile,templates,surfaces,usage}
```

### Dart: `packages/openui_lang/` (pure Dart, `dart test`)

```
lib/src/lexer.dart            tokens; never throws (skips unknown chars), # and // comments
lib/src/parser.dart           statements, expressions (EBNF §1.6), positional args → named props via LibrarySpec order
lib/src/streaming.dart        StreamingParser.set(fullText) → ParseResult; implicit close of open strings/brackets,
                              prefix cache with re-parse fallback; pending statement never overwrites a completed one
lib/src/library_spec.dart     LibrarySpec / ComponentSpec / PropSpec (JSON round trip)
lib/src/validate.dart         unknown-component, missing-required, null-required, type-mismatch, excess-args, …
lib/src/errors.dart           OpenUIError {source, code, statementId, message, hint}
lib/src/eval.dart             expressions, member pluck, .length, ternary, @Count/@First/@Last/@Sum/@Avg/@Min/@Max/
                              @Filter/@Sort/@Round/@Abs/@Floor/@Ceil/@Each
lib/src/store.dart            $state with defaults, two-way binding, re-parse never clobbers user-changed values
lib/src/prompt.dart           generateSystemPrompt(library, options) — byte-deterministic
test/conformance_test.dart    runs spec/fixtures/1.0/* ; test/fixtures/ is vendored with attribution
```

Flutter side:

```
lib/features/genui/render/
  iris_library.dart       IrisComponent definitions (single source of truth) + toLibrarySpec()
  node_builder.dart       ElementNode → Widget; Unresolved/incomplete → skeleton; errors → "can't show this" chip
  open_ui_view.dart       StreamingParser + Store in a widget; loading, fallback text, max height + "Show all"
  actions.dart            @Ask and local actions (@Set, toggles) → ChatController
```

### Server: `hermes-iris`

```
server/hermes-iris/
  plugin.yaml  __init__.py  dashboard/{manifest.json,plugin_api.py}
  catalog/v1.library.json     LibrarySpec exported from Dart (checked in)
  openui/{lexer,parser,validate,prompt}.py   Python port; tested with the same fixtures
  genui/templates.py          expand {template, data} → program with `data = …`
  genui/store.py              file store under ~/.hermes/iris/ per profile, atomic writes
  genui/context.py            pre_llm_call text, ≤ 2,500 chars
  skills/iris-genui/SKILL.md + references/{library.md (generated prompt), patterns.md, study.md}
  tests/
```

**Tools** (toolset `iris`): `iris_ui(surface_id, code? | template? + data?, fallback, placement="inline"|"reply_kit")`,
`iris_profile_get/propose`, `iris_template_list/propose`.

**Routes** (`/api/plugins/iris/…`, all authenticated, all take `?profile=`): `GET capabilities`
(`{version, openui:"1.0", library_ids, features}`), `POST sessions/{id}/genui`, `GET surfaces/{session}[/{surface}]`,
`GET/PUT profile`, `GET/PUT/DELETE templates[/{id}]`, `POST feedback`.

**Context budget.** `pre_llm_call` adds ≤ ~2,500 chars: rules, a one-line-per-component digest, and the approved templates
index. The full generated prompt (all component signatures + examples, a few thousand tokens like the OpenUI prompt)
lives in `skill_view('iris-genui', 'references/library.md')` and is pulled only when composing something new. Phase 0
measures whether hook text is stored in history and must be hidden.

### Study and learning loop

Unchanged in intent (gather → infer profile → propose 3–8 templates and 2–4 reply kits with redacted sample data →
review in Iris → approve). Templates are now OpenUI programs, so the model writes them in the same compact language and
the review screen renders them with real `OpenUiView`s. Learning loop: Iris posts `used/expanded/dismissed/not_useful`;
`post_llm_call` logs template use; `/iris-refine` proposes edits, new templates and retirements.

### The Iris library (v1)

Component names/props are fixed during Phase 2/3 and recorded in `iris_library.dart`. Shape (positional order matters,
so required props first, optional last):

- **Layout:** `Stack(children, direction?, gap?)`, `Card(children, title?)`, `Section(title, children)`, `Divider()`,
  `Tabs(items)` + `Tab(label, children)` (local `$tab`), `Expander(title, children)`.
- **Text & data:** `Text(value, variant?)`, `Markdown(value)`, `KeyValue(key, value)`, `Stat(label, value, delta?, trend?)`,
  `StatRow(stats)`, `StatusPill(label, tone?)`, `Table(columns, rows)`, `ListRow(title, subtitle?, trailing?)`, `Timeline(items)`,
  `Checklist(items)`, `Progress(value, label?, style?)`, `CodeBlock(code, language?)`, `Diff(before, after)`,
  `Image(url, alt)` (image-host allow-list), `Link(label, url)` (link confirmation).
- **Charts:** `Sparkline(values)`, `LineChart(series, labels?)`, `BarChart(series, labels?)`, `Donut(slices)` — painters.
- **Inputs:** `Button(label, action?, variant?)`, `ChoiceChips(name, options, value?, multi?)` (bindable to `$var`),
  `Input(name, label, type?, placeholder?, value?)`, `Slider`, `Toggle`, `DatePicker`, `Stepper`, `ApproveReject(approveLabel, rejectLabel, askLabel?)`,
  `Submit(label, action)`.
- **Custom functions/actions:** `@Ask(text, context?)`, `@Percent(done, total)`, `@Money(value, currency)`, `@Ago(timestamp)`.

Limits (both sides): ≤ 60 statements per program, ≤ 12 KB source, ≤ 4 surfaces per turn, depth ≤ 8, list templates
≤ 100 rows rendered, string literal ≤ 2 KB.

## Security & privacy

- **Plugin routes must authenticate.** Phase 0.2: the dashboard login covers `/api/plugins/*` on this server (401
  without it), so the plugin adds no auth of its own. Re-check after Hermes updates.
- OpenUI Lang is a **data language with a closed vocabulary**: no imports, no host calls except the library's declared
  actions; expressions are pure; unknown components/functions are dropped, never executed. Both plugin and app validate.
- `Query`/`Mutation` and `@Run` against host tools are **excluded from v1**: no data fetching from generated code.
- Evaluator limits: expression depth, iteration cap on `@Each`/`@Filter` (≤ 1,000 items), no recursion by construction
  (references resolve to a DAG; cycles are dropped with an error).
- Images only from the allow-list; links only through the confirmation; no auto-fetch.
- Actions are ordinary user messages, visible in history; nothing executes on device.
- Study stays on the person's server; samples redacted and reviewed. "Reset" deletes `~/.hermes/iris/` for that profile.
- Never log programs, `data`, or action contexts unredacted (`IrisLog.redact`).

## Risks

| Risk | Mitigation |
|---|---|
| Writing a spec-conformant parser is bigger than it looks | Port against the official fixtures; gate Phase 2 on them; scope v1 to the features the library uses (no Query/Mutation) and record any skipped fixture with a reason |
| Fixtures/spec change (1.0 is new) | Vendor a pinned commit; library `version`; re-sync is a deliberate task |
| Dart ↔ Python divergence | One fixture set run by both in CI; golden prompt snapshot generated by Python and compared with Dart |
| Models write OpenUI Lang worse than JSON | Prompt is generated from the library with examples; server returns structured errors with hints and the model retries; Phase 1 live check measures first-try validity |
| No progressive rendering over a tool call | Confirmed in Phase 0: args arrive whole; generic "composing" state from `tool.generating`; compact programs and templates keep calls short |
| Tool args truncated in events | Not seen up to 11.9k chars; still fetch by id from the plugin store if absent |
| Plugin tools deferred behind Tool Search | Context names `iris_ui` and its args so the model calls `tool_call` directly; skips ~13 s discovery |
| Hook context stored in history | Not stored (Phase 0.4); no stripping needed |
| Slow agent (95–160 s per reply) | Compact programs; templates; no extra round trips |
| Plugin routes unauthenticated | Protected by the dashboard login (Phase 0.2) |
| Dashboard on a deleted Python after a Hermes update | Restart `hermes-dashboard` after updates; Iris shows `agent_init_failed` text as is |
| Other clients see `iris_ui` | Tool blocked outside flagged sessions; fallback text elsewhere |

## Out of scope (v1)

- `Query`/`Mutation` (live data from Hermes tools); a strong Phase 9 candidate: displays that refresh themselves.
- Surfaces in voice calls; home-screen widgets / Live Activities from templates; template sharing.
- OpenUI Gateway/Autofix, the React Agent Interface, A2UI and the `genui` packages.
- Publishing `openui_lang` to pub.dev (possible later; keep the package self-contained and documented to allow it).

## Sources

- OpenUI: https://www.openui.com/ · https://www.openui.com/docs/openui-lang · https://github.com/thesysdev/openui
  (`spec/overview.md`, `spec/language.md`, `spec/prompt.md`, `spec/fixtures/1.0/`) ·
  https://cdn.jsdelivr.net/npm/@openuidev/lang-core@0.2.6/README.md
- Superseded: A2UI https://a2ui.org/ · `genui` https://pub.dev/packages/genui
- Hermes: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills · …/plugins · …/hooks · …/memory ·
  …/dashboard-plugins
