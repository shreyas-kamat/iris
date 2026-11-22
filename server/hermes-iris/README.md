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
# {"version":"0.4.1","openui":"1.0","library_ids":[...],"features":[...]}
```

Hermes imports `dashboard/plugin_api.py` only when the plugin is in `plugins.enabled`.

**Named profiles:** each Hermes profile has its own config. The plugin's hooks (push events, generated displays) run
only for chats in a profile whose `plugins.enabled` lists `iris`. Add `iris` to that list in the `config.yaml` of every
profile Iris is used with, or replies there send no notification.

## Upgrade

Repeat the `rsync` and restart `hermes-dashboard`. The store (`~/.hermes/iris/`) is never touched by an upgrade.
Compare `/capabilities` `version` with `plugin.yaml` afterwards.

## Push notifications for iPhones (APNs)

Android needs nothing here: Iris holds `GET push/stream` open. iPhones get notifications from Apple, which this server
calls directly (no relay), so it needs an APNs key once:

1. In the Apple developer portal, Certificates, Identifiers & Profiles -> Keys, create a key with **Apple Push
   Notifications service (APNs)** enabled. Download `AuthKey_<KEY ID>.p8` (Apple lets you download it once) and note
   the key id and your team id (Membership details).
2. On the server, put the key beside a config file and make both private to the user the dashboard runs as:

   ```sh
   mkdir -p ~/.hermes/iris/push && cd ~/.hermes/iris/push
   cp /path/to/AuthKey_ABC123DEFG.p8 .
   cat > apns.json <<'JSON'
   {"team_id": "TEAM123456", "key_id": "ABC123DEFG", "bundle_id": "com.iflotech.iris",
    "key_path": "AuthKey_ABC123DEFG.p8", "environment": "production"}
   JSON
   chmod 600 apns.json AuthKey_ABC123DEFG.p8
   ```

   `environment` is `sandbox` for an Iris build run from Xcode, `production` for TestFlight and App Store builds.
   `key_path` is relative to this directory (or absolute). A key file that is not mode 0600 is refused.
3. Restart `hermes-dashboard`. `GET push/status` should say `"apns_configured": true` (it also needs `curl` on the
   PATH: the server sends with `curl --http2`). `POST push/test/<device id>` sends one test notification to a
   registered iPhone and answers `{"ok", "result"}`.

The sender is a thread in the dashboard process; it reads new events once a second, skips any older than 10 minutes,
and remembers where it got to in `<profile>/push/apns.cursor`. Failures are logged by status and Apple's reason only.

## Remove

```sh
ssh root@hermes 'hermes plugins disable iris && rm -rf ~/.hermes/plugins/iris && systemctl restart hermes-dashboard'
```

Leave `~/.hermes/iris/` in place if the person may reinstall: it holds their profile, templates and surfaces.

## Develop

```sh
cd server/hermes-iris
python -m venv .venv && .venv/Scripts/python -m pip install fastapi httpx pytest pyyaml cryptography   # Scripts -> bin on Linux
.venv/Scripts/python -m pytest
```

Hermes is not installed locally, so `tests/conftest.py` stands in for `hermes_constants` and loads the plugin the two
ways Hermes does: as a package, and `dashboard/plugin_api.py` on its own from its file. The agent-side hooks and the
dashboard routes can run in different processes, so they share state only through files.

## Layout

```
plugin.yaml  __init__.py  pytest.ini
dashboard/{manifest.json,plugin_api.py,dist/index.js}   routes under /api/plugins/iris/
genui/    store (files), templates, surfaces (iris_ui), tool, guards, context, flags, skill, catalog, paths,
          personal (profile, templates and proposed changes), personal_tools, feedback (the app's signals),
          usage (one row per turn)
push/     devices (registry and settings), active (chats awaiting a reply), outbox (events), render (what a device
          may see), hooks (capture), stream (Android SSE), apns (iPhone sender), worker (APNs delivery thread)
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
