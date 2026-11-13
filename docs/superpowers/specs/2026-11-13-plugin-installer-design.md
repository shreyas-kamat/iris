# Iris plugin installer: onboarding and Settings (design)

Status: awaiting the user's approval (2026-11-13). Size: a small project (one flow, two surfaces, no server code).

## Intent

Iris is useful without the `hermes-iris` plugin, but generated displays, alerts and the study need it. Today the user
installs it by hand over SSH. The app should install and update it for them, from a screen after login and from
Settings, and say plainly what they miss without it.

## Goals

- After the first successful login to a server that lacks the plugin, show a one-time onboarding screen with a
  one-tap **Install on my server**, and what is missed without it.
- Settings has an **Iris plugin** row: not installed (Install), installed with its version, update available (Update),
  or up to date.
- The install runs on the user's own server through Hermes's own plugin installer. After it, the app re-probes and the
  features appear without a restart.

## Non-goals / anti-goals

- No new server routes and no plugin code changes: Hermes already has install, enable and replace.
- Never install without a tap. Never nag: "Not now" is remembered per server. Never run in demo mode.
- No "latest main" installs: a server must never run plugin code newer than the app expects.
- Not iOS-specific; works on both platforms.

## Facts found (Hermes 2026.9.24 on the user's server)

- `POST /api/dashboard/agent-plugins/install` `{identifier, ref?, force, enable}` behind the dashboard login. The
  identifier takes `owner/repo#subdir` or a GitHub URL; `ref` must be a full 40-character commit SHA. The install is
  recorded as an unreviewed ("custom") source, and Hermes warns about that.
- A plugin installed with a `ref` is pinned: `POST .../agent-plugins/{name}/update` refuses it and says to reinstall with
  `force` and a new `ref`. So **update = install again with `force: true` and the new SHA.**
- The response says whether the plugin went live (`activation`, `restart_required`); `activate_plugin_now` loads it in
  the dashboard process, so no restart is normally needed.
- The version of the installed plugin is `capabilities.version` at `/api/plugins/iris/capabilities` (already probed as
  `ServerCapability.irisGenui`).
- The user's server has the plugin from a hand copy (no install record) at `~/.hermes/plugins/iris`.

## Approaches

1. **App calls Hermes's install route with a pinned release** (chosen by the user: "A, pinned release"). The app ships
   one constant: plugin version `0.4.0`, tag `hermes-iris-v0.4.0`, its full commit SHA. No server changes.
2. *Latest `main`*: rejected by the user; server code could drift ahead of the app.
3. *Upload the plugin from the app*: Hermes has no upload route. Would need a plugin that already exists. Rejected.

## Design

- `PluginRelease` constant (version, repo `shreyas-kamat/iris`, subdir `server/hermes-iris`, tag, 40-char SHA) in
  `lib/data/plugin/`. The SHA is filled in at release time (Task 12 of the push plan, tagging needs the user's yes).
- `PluginInstaller` (data layer): `status(server)` from the capability probe (`absent` / `installed(version)` /
  `outdated(version -> pinned)` / `ahead`), `install()` calls the route with `force: true` always (covers first install
  over the hand copy, and update), then re-runs the capability probe and reports installed version, or the server's
  error text. Version compare is semver; unknown version counts as outdated.
- **Onboarding screen** (`lib/features/plugin/`): shown once per server, after the first live login, when the plugin is
  absent and the server has not been dismissed. Copy as agreed: Generated displays, Alerts in your own words, Study and
  templates. Buttons: Install on my server / Not now / What does this install? (source, pinned version, "adds files to
  your server, Hermes marks it unreviewed"). Progress, success ("Installed v0.4.0", continue), failure (server's reason,
  Retry, Not now). Dismissal key per server in preferences.
- **Settings row** under the existing Generated displays / Notifications groups: Not installed (Install) /
  Version x.y.z + Update to a.b.c or Up to date. Always available, also after "Not now". Hidden in demo.
- **Fallback:** if the route is missing (404/405) or refuses the login (401/403), show the equivalent
  `hermes plugins install <identifier> --force --ref <sha>` command with a Copy button.
- Existing `irisGenui` gating stays; the installer only changes whether the plugin exists.

## Risks to verify with a spike on the real server (before the plan is final)

1. **Install name:** the installer names the directory from the subdir or repo, possibly `hermes-iris`, while the
   hand copy is `iris` and the manifest says `name: iris`. Expect a clean replace of `iris`; verify no duplicate plugin
   and that `force` over the hand copy works. If it makes a second copy, the fix is a manifest or repo layout change,
   not app code.
2. **Is the login enough:** the app's cookie/session may or may not satisfy `_require_token` in the user's gated mode.
3. **Unreviewed-source gate:** whether the non-interactive path asks for consent we cannot answer (`assume_deps_consent`).
4. **Python deps:** the plugin needs none beyond Hermes's own (cryptography ships with Hermes); confirm the consent text.

## Left to the builder

Screen layout details, copy wording within the above, the preference key names, and test structure (fake Hermes API in
tests; the live check is one throwaway reinstall on the user's server, with their yes).

## Sequencing

Needs a tagged release and a pushed tag before the installer can really install, so the live check comes after the
plugin 0.4.0 release. Until then it is tested against a fake server. PS6's Android device pass waits for this work.
