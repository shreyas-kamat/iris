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
dashboard/{manifest.json,plugin_api.py,dist/index.js}
tests/
```

More lands as the plan's Phase 2 proceeds: `genui/` (store, templates, context), `openui/` (the Python port),
`catalog/` (the component library exported from Dart), `skills/iris-genui/`.
