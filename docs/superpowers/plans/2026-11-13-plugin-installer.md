# Iris Plugin Installer Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans (the user's rule: no subagents). Steps use
> checkbox (`- [ ]`) syntax. Phase 9 run book rules apply (log after each task, commits under the user's name only, no
> `Claude-Session` line, add files by name, stop at segment boundaries).

**Goal:** Iris installs and updates the `hermes-iris` plugin on the user's Hermes server in one tap, from a one-time
onboarding screen after login and from a Settings row, and says what is missed without it.

**Architecture:** No server code. A `PluginInstaller` in the data layer calls Hermes's own
`POST /api/dashboard/agent-plugins/install` with `force: true` and a pinned 40-character commit SHA, then re-probes the
server. Riverpod providers expose the status (absent / outdated / current) and a per-server "Not now" flag; two UI
surfaces read them.

**Tech Stack:** Flutter, Riverpod 3, the existing `ApiClient` / `CapabilityProbe` / `PreferencesStore`.

**Spec:** `docs/superpowers/specs/2026-11-13-plugin-installer-design.md` (approved 2026-11-13).

## Global Constraints

- Source is `shreyas-kamat/iris#server/hermes-iris`, pinned to a release commit. Never "latest main".
- Install and update are the same call: `force: true`, `enable: true`, `ref: <40-char SHA>`, `identifier:
  'shreyas-kamat/iris#server/hermes-iris'` (Hermes pins reinstalls and refuses `/update` on a pinned plugin).
- Hermes names the plugin dir from the manifest (`name: iris`), so the call replaces `~/.hermes/plugins/iris` cleanly
  (read in `plugins_cmd_install.py`, Hermes 2026.9.24). User data under `~/.hermes/iris/` is outside the plugin dir and
  survives. This closes the spec's risk 1 on paper; Task 5 confirms it live.
- Never install without a tap. "Not now" is remembered per server. Nothing shows in demo mode.
- The onboarding appears only when the capability probe has run, is not `requiresAuth`, the link is live, and the
  plugin is **confirmed absent** (`!confirmed(irisGenui)`): an unauthenticated probe also reports "absent".
- No Google, no new packages. Copy: sentence case, no em dashes, plain words (matches the app).
- The release constant's SHA is filled in at the plugin release (Task 5); until then Install reports "not released" and
  the onboarding does not appear.

## Review Focus

1. **Probe says absent only because the login expired.** Expect: no onboarding, no install button offering a replace.
   Test in Task 2 (`not due while the probe was challenged`).
2. **Install succeeds on the server but the re-probe fails (offline right after).** Expect: report installed, say the
   check failed, never claim "not installed". Test in Task 1 (`install ok, reprobe fails`).
3. **Server is newer than the app expects (plugin 0.5.0, app pins 0.4.0).** Expect: "Up to date", never offer a
   downgrade. Test in Task 1 (`status ahead`).
4. **Double tap on Install.** Expect: one request. Test in Task 2 (`install is single flight`).
5. **Hermes answers 200 with `{"ok": false, "error": ...}`, or the scan blocks the plugin.** Expect: the error text
   shown, plus the copyable command. Test in Task 1 (`ok false body`).

---

## Segments

| Segment | Tasks | Model | Why |
|---|---|---|---|
| IN1 | 1–2 | **Sonnet** | Data layer and providers, test-first, fake server |
| IN2 | 3–4 | **Sonnet** | Settings section, onboarding screen and host, goldens |
| IN3 | 5 | **Sonnet** | Release constant and the live reinstall on the user's server; **runs after PS7's release** (needs the tag) |

Order of work: IN1, IN2, then the PS6 Android device pass and PS7 review/release, then IN3. The live check cannot come
earlier: it needs the tag, and device-pass fixes to the plugin would change the pinned commit.

## File map

- Create `lib/data/plugin/plugin_release.dart`: the pinned release constant and semver compare.
- Create `lib/data/plugin/plugin_installer.dart`: `PluginInstaller`, `PluginInstallResult`, `PluginStatus`.
- Create `lib/app/plugin_providers.dart`: status, install controller, onboarding flag and "due" provider.
- Modify `lib/data/prefs/preferences_store.dart`: `PreferenceKeys.pluginOnboarded` (per server).
- Create `lib/features/settings/plugin_settings_section.dart`; modify `settings_screen.dart:212` (section above
  `GenUiSettingsSection`).
- Create `lib/features/plugin/plugin_onboarding_screen.dart`, `plugin_install_panel.dart` (shared progress, error and
  fallback command), `plugin_onboarding_host.dart`; modify `lib/app/iris_app.dart` (wrap `connected`).
- Tests: `test/data/plugin_installer_test.dart`, `test/app/plugin_providers_test.dart`,
  `test/features/plugin/plugin_ui_test.dart`, goldens in `test/features/plugin/goldens/`.

---

### Task 1: Release constant and installer

**Files:** create `plugin_release.dart`, `plugin_installer.dart`; test `test/data/plugin_installer_test.dart`.

**Interfaces:**
- Produces:
  - `final class PluginRelease { const PluginRelease({required version, required tag, required sha, required repo,
    required subdir}); static const current; String get identifier /* 'owner/repo#subdir' */;
    String get fallbackCommand /* 'hermes plugins install <identifier> --force --ref <sha>' */; bool get released
    /* sha is 40 hex */; }`
  - `int compareVersions(String a, String b)` (numeric parts; non-numeric or missing parts count as 0; a `-rc1`
    suffix is ignored).
  - `sealed class PluginStatus` = `PluginAbsent`, `PluginInstalled(version, {updateTo: String?})` (`updateTo` set when
    the installed version is lower than the release's, or unreadable).
  - `final class PluginInstallResult { bool ok; String? error; bool showCommand; String? installedVersion;
    bool recheckFailed; }`
  - `PluginInstaller(ApiClient client, {PluginRelease release = PluginRelease.current})`:
    `PluginStatus statusOf(GenUiCapabilities? plugin)`; `Future<PluginInstallResult> install()`.
- Consumes: `ApiClient.post(path, body:, receiveTimeout:)`, `DashboardGenUiApi(client).capabilities()`,
  `IrisFailure.kind/message/statusCode`.

- [ ] **Step 1: Write the failing tests** (`FakeHttp` as in `test/data/genui_test.dart`):
  - `install posts the pinned release`: request is `POST /api/dashboard/agent-plugins/install` with body
    `{identifier: 'shreyas-kamat/iris#server/hermes-iris', ref: <sha>, force: true, enable: true}`; then a GET of
    `/api/plugins/iris/capabilities`; result `ok`, `installedVersion` from it.
  - `unreleased build refuses`: a release with an empty sha makes no request and returns `ok: false`,
    `showCommand: true`, error "This build of Iris has no released plugin yet".
  - `ok false body`: `200 {"ok": false, "error": "scan blocked"}` gives `ok: false`, error `scan blocked`,
    `showCommand: true`.
  - `route missing or refused`: 404 and 405 give `showCommand: true`; 401 and 403 give `showCommand: true` with "Your
    login cannot install plugins"; 500 gives the failure's message and `showCommand: false`.
  - `install ok, reprobe fails`: install 200 ok, capabilities 404 gives `ok: true`, `recheckFailed: true`.
  - `status`: absent for null; installed `0.4.0` against release `0.4.0` gives `updateTo` null; `0.3.0` gives
    `updateTo: '0.4.0'`; `status ahead`: `0.5.0` gives `updateTo` null; an unparsable version gives
    `updateTo: '0.4.0'`.
  - `compareVersions`: `0.10.0 > 0.9.0`, `1.0 == 1.0.0`, `0.4.0-rc1 == 0.4.0`.
  - `fallbackCommand` contains the identifier, `--force` and the sha. A guard test: `PluginRelease.current.version` is
    not lower than the `version:` line of `server/hermes-iris/plugin.yaml`.
- [ ] **Step 2:** Run `flutter test test/data/plugin_installer_test.dart`. Expected: FAIL to compile (no modules).
- [ ] **Step 3:** Implement `plugin_release.dart` (`current`: version `0.4.0`, tag `hermes-iris-v0.4.0`, sha `''` until
  Task 5, repo `shreyas-kamat/iris`, subdir `server/hermes-iris`).
- [ ] **Step 4:** Implement `plugin_installer.dart` with a 180 s receive timeout on the install call (Hermes clones and
  scans); a 200 whose body has `ok == false` is a failure; map failure kinds as the tests state.
- [ ] **Step 5:** Run the test file. Expected: all pass. Run
  `flutter analyze lib/data/plugin test/data/plugin_installer_test.dart`. Expected: no issues.
- [ ] **Step 6:** Commit `feat(plugin): pinned release and installer for the hermes-iris plugin`.

### Task 2: Providers, "Not now" flag, single flight

**Files:** create `lib/app/plugin_providers.dart`; modify `preferences_store.dart`; test
`test/app/plugin_providers_test.dart`.

**Interfaces:**
- Produces:
  - `PreferenceKeys.pluginOnboarded = 'plugin.onboarded'` (per server; `'true'` once the screen was shown and left,
    whether by Install success or "Not now").
  - `pluginInstallerProvider: Provider<PluginInstaller?>` (null with no live session or in the demo).
  - `pluginStatusProvider: Provider<AsyncValue<PluginStatus?>>` (from `genUiAvailableProvider` and
    `genUiPluginProvider`; null in demo or with no server).
  - `pluginInstallProvider: NotifierProvider<PluginInstall, PluginInstallState>`; state `idle | installing |
    failed(PluginInstallResult) | done(PluginInstallResult)`; `Future<void> install()` is single flight; on success it
    calls `serverRepository.refreshCapabilities(config)` and invalidates `genUiPluginProvider`.
  - `pluginOnboardingDueProvider: Provider<bool>`: true when not demo, a server is active, capabilities
    `hasProbed && !requiresAuth && !confirmed(irisGenui)`, the link is live (`activeLinkProvider` has data and is up),
    the server's `pluginOnboarded` pref is absent, and `PluginRelease.current.released`.
  - `pluginOnboardedProvider` with `markSeen()` writing the pref.

- [ ] **Step 1: Write the failing tests** with a `ProviderContainer` (listen before awaiting `.future`; see the
  `riverpod3-paused-providers` memory): `due when probed absent and not seen`; `not due while the probe was
  challenged` (`requiresAuth: true`); `not due after markSeen`; `not due in demo`; `not due when the release has no
  sha`; `install is single flight` (two calls, one HTTP request); `success re-probes and clears absence`; `failure
  keeps the error and does not mark seen`.
- [ ] **Step 2:** Run it. Expected: FAIL (no providers).
- [ ] **Step 3:** Implement the providers as specified, following the patterns in `genui_providers.dart` (scope is the
  server id).
- [ ] **Step 4:** Run the tests, then `flutter analyze lib test` (only the 3 known infos) and `flutter test
  --exclude-tags live`. Expected: all pass.
- [ ] **Step 5:** Commit `feat(plugin): install state, onboarding flag and status providers`. Log segment IN1 (journal
  entry, status row), commit the log.

### Task 3: Settings section

**Files:** create `lib/features/settings/plugin_settings_section.dart` and
`lib/features/plugin/plugin_install_panel.dart`; modify `settings_screen.dart`; test
`test/features/plugin/plugin_ui_test.dart`; goldens `screen_plugin_settings_{light,dark}` registered like the other
screens in `test/design/screens_golden_test.dart`.

**Interfaces:** `PluginInstallPanel` (shared): given a `PluginInstallState`, renders progress ("Installing…"), the
error text, and the fallback command with a Copy button (`Clipboard`), plus Retry. `PluginSettingsSection` (group
title "Iris plugin") is hidden in the demo.

- [ ] **Step 1: Write the failing widget tests:** `shows Not installed with an Install button`; `shows Version 0.3.0
  and Update to 0.4.0`; `shows Version 0.4.0 and Up to date, no button`; `tapping Install calls the installer once and
  shows progress`; `a failure shows the error and the command, and Copy puts the command on the clipboard`; `hidden in
  the demo`; the buttons have semantics labels.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement; rows use `IrisSettingsRow`; place the section above `GenUiSettingsSection`.
- [ ] **Step 4:** Tests pass; regenerate the goldens and open them (light and dark, absent and outdated).
- [ ] **Step 5:** Commit `feat(plugin): Settings row to install and update the plugin`.

### Task 4: Onboarding screen and host

**Files:** create `plugin_onboarding_screen.dart`, `plugin_onboarding_host.dart`; modify `iris_app.dart`; tests in
`plugin_ui_test.dart`; goldens.

**Interfaces:** `PluginOnboardingScreen` (full screen, uses `PluginInstallPanel`): title "Get more from Iris", line
"Add the Iris plugin to your Hermes server.", three rows (Generated displays: "Cards, tables and checklists drawn
natively instead of plain text"; Alerts: "Your own words on your lock screen when a reply lands, an approval waits, or
a job finishes"; Study and templates: "Saved displays and the learning loop"), buttons **Install on my server** and
**Not now**, link **What does this install?** (a sheet: source `github.com/shreyas-kamat/iris`, version and tag from
`PluginRelease`, "adds files to your server; Hermes marks it as an unreviewed source"). Success state: "Installed
v<version>" with Continue. `PluginOnboardingHost` wraps `connected` in `iris_app.dart`: when
`pluginOnboardingDueProvider` turns true it pushes the screen once on `irisNavigatorKey`; Not now and Continue call
`markSeen()` and pop.

- [ ] **Step 1: Write the failing tests:** `host pushes the screen once when due, and not again after Not now`; `Not
  now marks seen and pops`; `Install shows progress, then Installed v0.4.0 and Continue`; `failure shows the error,
  Retry and Not now`; `the sheet names the source and version`; no overflow at 2x text; goldens (light and dark: the
  offer, installing, failed).
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test --exclude-tags live` and `flutter analyze lib test` pass; open the goldens.
- [ ] **Step 5:** Commit `feat(plugin): onboarding screen that installs the plugin`. Log segment IN2, commit the log.

### Task 5: Release wiring and live reinstall (IN3, after PS7's release)

Needs the user: the plugin 0.4.0 tag pushed (PS7 Task 12) and a yes to reinstall on their server.

- [ ] **Step 1:** Fill `PluginRelease.current.sha` with `git rev-parse hermes-iris-v0.4.0^{commit}`; the guard test
  compares against `plugin.yaml`.
- [ ] **Step 2:** On the Moto G45 against the user's server: Settings, Iris plugin, Update. Verify: Hermes reports ok,
  the capabilities version reads 0.4.0, `~/.hermes/plugins/iris` was replaced with no second plugin directory,
  `~/.hermes/iris/default` is untouched, push and displays still work. Note any consent or scan gate the
  non-interactive path hits.
- [ ] **Step 3:** If the route or the login is refused, confirm the fallback command works when pasted on the server.
  Record results and defects in the progress log; fix test-first; commit.
