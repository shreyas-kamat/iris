# Phase 9 progress log

Run book: `2026-11-06-phase9-run.md`. Update the table when a status changes; append journal entries at the bottom,
newest last. Models are the minimum; a higher one is fine.

## Status

| ID | Subphase / segment | Model | Status | Last commit |
|---|---|---|---|---|
| 9.1 | **GenUI** (`feat/genui`; plan `2026-10-31-genui.md`) | | | |
| G1 | Phase 0: live probe and OpenUI groundwork (gate) | Opus | done | `d535765` |
| G2 | 1.1–1.4: package, fixtures, lexer, parser, errors | Sonnet | done | `c205f14` |
| G3 | 1.5–1.6: streaming parser, evaluator, store | Opus | todo | |
| G4 | 1.7–1.8 prompt generator; Phase 2 server plugin | Sonnet | todo | |
| G5 | Phase 3: rendering surfaces in Iris | Sonnet | todo | |
| G6 | Phase 4: actions, inputs, reply kits | Sonnet | todo | |
| G7 | Phases 5–6: study, Displays, learning loop | Sonnet | todo | |
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
