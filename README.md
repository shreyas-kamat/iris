# Iris

[![CI](https://github.com/shreyas-kamat/iris/actions/workflows/ci.yml/badge.svg)](https://github.com/shreyas-kamat/iris/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

A free, open-source phone app for [Hermes Agent](https://github.com/NousResearch/hermes-agent). It
talks to your own Hermes dashboard (the agent's built-in web dashboard, default port 9119).

The phone is a control plane, not a compute plane. The agent, its tools and your data stay on your
hardware. Iris connects directly to your server: **no relay, no account, no analytics, no crash
reporting.** It needs a Hermes dashboard to talk to; it does not include an agent or a hosted service.
There is an offline demo if you want a look first.

## What it does

- **Connect your way.** Same Wi-Fi, Tailscale, or a Cloudflare-protected address. Iris checks the address
  first and asks only for what it needs: a Cloudflare Access service token, or a username and password.
  Plain `http` works only for private addresses (LAN, Tailscale, `.local`); anything on the internet must
  use `https`.
- **Chat.** Streaming replies with Markdown, code highlighting, visible reasoning and tool calls.
  Approve or deny commands, answer `sudo` and secret prompts, steer a running turn, stop it, retry a
  failed one. Pick how a message sent mid-reply is handled (queue, steer or interrupt), and undo the last
  turn or branch a chat from any reply.
- **Conversations.** A paged list with a search field (local matches at once, the server's full-text hits
  after), grouped by chat, with recent searches. Pin, rename, archive with undo, delete, and an Archived
  view; chats that are replying right now show under Live.
- **Passwords and connections.** Unlock the password manager, enter a one-time code, or save a login when
  Hermes asks; connect connectors and MCP servers from a card in the chat.
- **Profiles and usage.** Switch between the server's agent profiles; see how much of a provider's quota
  is used on the home screen.
- **Look and feel.** Ten skins, light and dark, honours reduced motion and large text, touch targets of at
  least 44 points. See [`docs/design-language.md`](docs/design-language.md).
- **Try the demo.** From the first screen, with no server and no network: sample conversations and five
  scripted turns that show tool calls, approvals, the sudo prompt, a failed turn and retry, and the
  password-manager and connection prompts. Nothing from it
  is saved.

## Privacy and security in brief

- Passwords and access tokens are kept in the platform keystore (Android Keystore, iOS Keychain), never in
  the app's database or logs.
- Iris sends your messages to the server you entered, and nowhere else. Conversations are held in memory
  while you read them; they are not copied into Iris's own storage.
- A self-signed certificate is trusted only if you choose to, and only for that one server.
- Links in a reply open in your browser, and only `http`, `https` and `mailto` links open at all.
- Android backup is off, so saved server addresses and settings are not copied to cloud backups.

The full policy is in [`SECURITY.md`](SECURITY.md); the user-facing privacy policy is at
<https://iris.shreyaskamat.in/privacy-policy>.

## Getting started

You need a running Hermes dashboard, or use **Try the demo** on the first screen. Pick how your phone
reaches the server and enter its address, usually on port 9119.

If the dashboard is behind **Cloudflare Access**, Iris needs a service token (Zero Trust, Access,
Service credentials) and a *Service Auth* policy for it on the application. Iris sends it as
`CF-Access-Client-Id` and `CF-Access-Client-Secret`, over HTTPS only.

## Building from source

Requirements: Flutter 3.41 (Dart 3.11) and, for Android, the Android SDK.

```sh
flutter pub get
dart run build_runner build      # Drift code generation; rerun after editing lib/data/db/database.dart
flutter analyze                  # must report no issues
flutter test
flutter run
```

Release builds, signing and store assets are covered in [`docs/release.md`](docs/release.md). iOS has not
been built or run yet; the project is set up for it but needs a Mac.

The golden-image tests were generated on Windows. If you work on another platform and a golden differs
only in text rendering, say so in your pull request rather than regenerating every image.

Tests in `test/live/` talk to a real server and are skipped by default. They read connection details from
`~/.iris-live.json`, which lives outside the repository and must never be committed.

## Architecture

```
lib/
  app/        providers, preferences, theme controller
  core/       Result / IrisFailure, tolerant JSON, redacting logger
  data/
    net/      dio client, auth, capability probe, connection modes, private-address rules
    rpc/      JSON-RPC over WebSocket: frames, client, live session
    chat/     the ChatBackend interface, events, models, parsers
    db/       Drift schema
    prefs/    saved choices
  demo/       an in-memory stand-in for a Hermes server, behind the same ChatBackend
  design/     tokens, theme, components, motion, platform adapters
  features/   chat, home, servers, settings, design gallery
```

`features/` talks to repositories and to the `ChatBackend` interface. Repositories return `Result<T>` and
do not throw. The demo plugs in at that interface, so no screen knows whether it is talking to a server.
More on the reasoning behind the design is in [`docs/design-language.md`](docs/design-language.md); the
design specs and implementation plans for each phase are in [`docs/superpowers/`](docs/superpowers/).

## Contributing

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first, and please follow the
[Code of Conduct](CODE_OF_CONDUCT.md). To report a vulnerability, see [`SECURITY.md`](SECURITY.md); do not
open a public issue for it.

## Environment notes

- **`compileSdk` is pinned to 36** in `android/app/build.gradle.kts`. Flutter defaults to 37, but this SDK
  installs the minor-versioned `android-37.0` platform, which AGP 8.11 cannot match against the plain
  `android-37` hash it looks for. `flutter_secure_storage` warns that it was compiled against 37; the build
  and app work at 36. Resolving it properly means AGP 8.13+ and `compileSdkMinor`, a separate upgrade.
- **The application ID is `com.iflotech.iris`** on Android and iOS.

## License

Iris is released under the [Apache License 2.0](LICENSE). Copyright 2026 Shreyas Kamat. Bundled fonts
(Geist, Geist Mono, Instrument Serif) are under the SIL Open Font License; see [`NOTICE`](NOTICE).
