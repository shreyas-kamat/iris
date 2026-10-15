# Changelog

All notable changes to Iris are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Replies render TeX maths (inline and display, AMS environments, physics notation, SI units and chemistry),
  GitHub alerts, footnotes, emoji shortcodes and table alignment.
- Images in Markdown show a placeholder and load only when tapped.
- Code blocks with no language label are detected and highlighted once the reply finishes.
- Attach photos and files to a message (up to 5, 20 MB each).
- Dictate a message with the mic; Hermes turns the recording into text, which lands in the composer unsent.

### Changed
- The Android release now also declares `RECORD_AUDIO`, used only for dictation.

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
- No camera, location or contacts permission; the microphone is asked for only when dictating.
- Android backup is disabled.
