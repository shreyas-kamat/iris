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
| G7 | Phases 5–6: study, Displays, learning loop | Sonnet | doing | |
| G8 | 7.1, 7.2, 7.5: demo, export/search, docs | Haiku | todo | |
| G9 | 7.3, 7.4: accessibility and device pass | Sonnet | todo | |
| G10 | 7.6 final review, release, PR | Opus | todo | |
| 9.2 | **Push notifications** (`feat/push`) | | | |
| P-spec | Brainstorm and design | Opus | todo | |
| P-plan | Implementation plan with segment table | Opus | todo | |
| P-build | Per the plan (Opus for the relay) | per plan | todo | |
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
