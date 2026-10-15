# Changelog

All notable changes to Iris are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - not yet released

The first release.

### Added
- Connect to a Hermes dashboard over the same Wi-Fi, Tailscale or a Cloudflare-protected address, with the
  mode only changing the wording; the address is probed first and Iris asks only for what is needed.
- Streaming chat with Markdown, code highlighting, visible reasoning and tool calls; approvals, `sudo` and
  secret prompts, steering, stop and retry.
- Conversation list with search, rename, archive with undo and an Archived view; agent profiles; provider
  usage on the home screen.
- Ten skins, light and dark, reduced motion, large text and screen-reader labels.
- An offline demo mode with sample conversations and scripted turns, for trying the app without a server.
- Settings that survive a restart: appearance, profile and which usage meters to show.

### Security
- Passwords and access tokens are stored in the platform keystore only.
- Plain `http` is allowed only for private addresses; self-signed certificates only by explicit choice, per
  server.
- No camera, location, contacts or microphone permission; the Android release declares only `INTERNET`.
- Android backup is disabled.
