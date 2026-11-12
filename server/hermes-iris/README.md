# hermes-iris

The Hermes side of Iris's generated UI. Hermes replies in Iris with native displays and reply kits written in OpenUI
Lang; this plugin validates what the agent writes, stores it per profile and serves it to the app. Design:
`docs/superpowers/specs/2026-10-31-genui-design.md`. Plan: `docs/superpowers/plans/2026-10-31-genui.md`.

Tested against Hermes release 2026.9.24. Needs Python 3.11 or newer (the interpreter Hermes already runs) and FastAPI,
which Hermes ships.

## Install

Copy the plugin directory (without `.venv/`, `tests/` and caches) to the Hermes home, enable it, restart the dashboard:

```sh
rsync -a --exclude .venv --exclude tests --exclude __pycache__ --exclude .pytest_cache \
  server/hermes-iris/ root@hermes:~/.hermes/plugins/iris/
ssh root@hermes 'hermes plugins enable iris && systemctl restart hermes-dashboard'
```

Check it is up (the dashboard login or Cloudflare Access headers are needed; plugin routes sit behind them):

```sh
curl -s https://<server>/api/plugins/iris/capabilities
# {"version":"0.3.0","openui":"1.0","library_ids":[...],"features":[...]}
```

Hermes imports `dashboard/plugin_api.py` only when the plugin is in `plugins.enabled`.

## Upgrade

Repeat the `rsync` and restart `hermes-dashboard`. The store (`~/.hermes/iris/`) is never touched by an upgrade.
Compare `/capabilities` `version` with `plugin.yaml` afterwards.

## Remove

```sh
ssh root@hermes 'hermes plugins disable iris && rm -rf ~/.hermes/plugins/iris && systemctl restart hermes-dashboard'
```

Leave `~/.hermes/iris/` in place if the person may reinstall: it holds their profile, templates and surfaces.

## Develop

```sh
cd server/hermes-iris
python -m venv .venv && .venv/Scripts/python -m pip install fastapi httpx pytest pyyaml   # Scripts -> bin on Linux
.venv/Scripts/python -m pytest
```

Hermes is not installed locally, so `tests/conftest.py` stands in for `hermes_constants` and loads the plugin the two
ways Hermes does: as a package, and `dashboard/plugin_api.py` on its own from its file. The agent-side hooks and the
dashboard routes can run in different processes, so they share state only through files.

## Layout

```
plugin.yaml  __init__.py  pyproject.toml
dashboard/{manifest.json,plugin_api.py,dist/index.js}   routes under /api/plugins/iris/
genui/    store (files), templates, surfaces (iris_ui), tool, guards, context, flags, skill, catalog, paths,
          personal (profile, templates and proposed changes), personal_tools, feedback (the app's signals),
          usage (one row per turn)
openui/   Python port of the OpenUI Lang lexer, parser, validator and prompt generator (validation only)
catalog/  v1.library.json: the component library, exported from `lib/features/genui/render/iris_library.dart` (refresh: `IRIS_WRITE_CATALOG=1 flutter test test/features/genui/iris_library_test.dart`)
skills/iris-genui/   SKILL.md, references/library.md (generated), references/patterns.md (every program is tested)
skills/iris-study/   SKILL.md, references/study.md: "Study my work" reads the person's work and proposes a profile and templates
skills/iris-refine/  SKILL.md, references/refine.md: the weekly refinement reads usage and proposes changes
tools/    build_skill_refs.py: regenerates library.md (`--check` fails when it is stale)
tests/
```

## What it does

| Piece | Where |
|---|---|
| `GET capabilities` -> `{version, openui, library_ids, features}` | `dashboard/plugin_api.py` |
| `POST/GET/DELETE sessions/{id}/genui` flags a *stored* session id for generated UI | `genui/store.py`, `genui/flags.py` |
| Tool `iris_ui(surface_id, code or template+data, fallback, placement, delete)` | `genui/tool.py`, `genui/surfaces.py` |
| `pre_tool_call` keeps `iris_*` to flagged sessions, 4 surfaces a turn; `transform_tool_result` trims receipts | `genui/guards.py` |
| `pre_llm_call` adds <= 2,500 characters of rules, a component digest and the approved templates | `genui/context.py` |
| `GET surfaces/{session}[/{surface}]` | `dashboard/plugin_api.py` |
| `GET/PUT profile`: the study's summary of the person's work, with the approved text kept as `previous` | `genui/personal.py` |
| Tools `iris_profile_get/propose`, `iris_template_list/propose` (proposals wait for the person) | `genui/personal_tools.py` |
| `GET templates[?status=]`, `GET/PUT/DELETE templates/{id}`: keep, rename, retire, and apply or discard a proposed change | `dashboard/plugin_api.py`, `genui/personal.py` |
| `POST feedback`: a batch of `used`, `expanded`, `dismissed` or `not_useful` signals from the app | `genui/feedback.py` |
| `post_llm_call` writes one `use` row per finished turn of a flagged session (ids only) | `genui/usage.py` |
| Tools `iris_usage_summary`, `iris_template_refine`: counts, and a proposed change beside the approved template | `genui/personal_tools.py`, `genui/personal.py` |

`iris_usage_summary`, `iris_template_refine`, `iris_template_list`, `iris_template_propose` and `iris_profile_get` run in
any session, so a scheduled refinement run can use them. `iris_ui` and `iris_profile_propose` still need a flagged session.

Files live in `<default Hermes root>/iris/<profile>/`: `profile.json`, `templates/`, `surfaces/<session>/`, `flags.json`,
`usage.jsonl` (with `usage.jsonl.1` after a rotation). Every route takes `?profile=`. Nothing logs a program, its data or
a fallback.

Two suites cross-check the Python against the Dart package (`dart` must be on PATH for the second):
`tests/test_openui_conformance.py` runs the vendored OpenUI fixtures, and `tests/test_crosscheck_dart.py` compares every
prefix of every fixture program.
