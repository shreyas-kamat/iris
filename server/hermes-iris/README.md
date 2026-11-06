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
# {"version":"0.1.0","openui":"1.0","library_ids":[...],"features":[...]}
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
genui/    store (files), templates, surfaces (iris_ui), tool, guards, context, flags, skill, catalog, paths
openui/   Python port of the OpenUI Lang lexer, parser, validator and prompt generator (validation only)
catalog/  v1.library.json: the component library (provisional until the Dart export lands, plan 3.1)
skills/iris-genui/   SKILL.md, references/library.md (generated), references/patterns.md (every program is tested)
tools/    build_skill_refs.py: regenerates library.md (`--check` fails when it is stale)
tests/
```

## What it does

| Piece | Where |
|---|---|
| `GET capabilities` -> `{version, openui, library_ids, features}` | `dashboard/plugin_api.py` |
| `POST/GET/DELETE sessions/{id}/genui` flags a *stored* session id for generated UI | `genui/store.py`, `genui/flags.py` |
| Tool `iris_ui(surface_id, code | template+data, fallback, placement, delete)` | `genui/tool.py`, `genui/surfaces.py` |
| `pre_tool_call` keeps `iris_*` to flagged sessions, 4 surfaces a turn; `transform_tool_result` trims receipts | `genui/guards.py` |
| `pre_llm_call` adds <= 2,500 characters of rules, a component digest and the approved templates | `genui/context.py` |
| `GET surfaces/{session}[/{surface}]` | `dashboard/plugin_api.py` |

Files live in `<default Hermes root>/iris/<profile>/`: `profile.json`, `templates/`, `surfaces/<session>/`, `flags.json`,
`usage.jsonl`. Every route takes `?profile=`. Nothing logs a program, its data or a fallback.

Two suites cross-check the Python against the Dart package (`dart` must be on PATH for the second):
`tests/test_openui_conformance.py` runs the vendored OpenUI fixtures, and `tests/test_crosscheck_dart.py` compares every
prefix of every fixture program.
