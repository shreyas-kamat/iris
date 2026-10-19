# Changelog

All notable changes to Iris are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Voice mode: a live voice call from any chat, with the voice orb as the microphone. Chained servers run
  speech-to-text, the agent and text-to-speech; GPT-Live servers talk through OpenAI's realtime model. A call
  starts only after its parts answer, with live captions, approvals and questions answered by voice, and
  push-to-talk or hands-free. Calls keep going in the background, with a notification to mute or end them.
  Settings chooses the call style, speaker and captions, and the server's voice.
- The demo plays a scripted voice call.
- Replies render TeX maths (inline and display, AMS environments, physics notation, SI units and chemistry),
  GitHub alerts, footnotes, emoji shortcodes and table alignment.
- Images in Markdown show a placeholder and load only when tapped.
- Code blocks with no language label are detected and highlighted once the reply finishes.
- Attach photos and files to a message (up to 5, 20 MB each).
- Dictate a message with the mic; Hermes turns the recording into text, which lands in the composer unsent.
- Delete conversations (home and Archived), with a confirm; Hermes refuses while one is replying.
- Pin conversations to the top of home; chats that are replying right now show under Live.
- Undo the last turn from the menu on your latest message or with `/undo`; your prompt comes back to edit.
- Branch a conversation, whole (`/branch`, home menu) or from any reply; the new chat says where it came from.
- While a reply runs, sending follows Hermes's setting (Queue, Steer or Interrupt), which Settings changes.
  Queued messages wait in a tray above the composer; `/queue` and `/steer` always do their one thing.
- Reasoning effort and fast mode in the model sheet, when the model supports them.
- Password-manager prompts (unlock, one-time code, save login) and a connection card for connectors and
  MCP servers.
- Recent searches, and search results grouped by chat with a match count.
- Home gets Scheduled and Tasks tabs on servers that have them: list, pause and resume, run now, create, edit and
  delete cron jobs, with each job's past runs; and the Kanban board by column, with task detail, moving a task and
  creating one.
- A ⋯ menu in the chat header: rename, pin, branch, archive, compress, undo, export as Markdown, session info, delete.
- Create, rename, edit the SOUL of, and delete profiles (Settings → Profiles).
- Search across every profile from home, with results grouped by profile.
- "Always load images from this host" in the image card's long-press menu.

### Changed
- The Android release now also declares `RECORD_AUDIO`, used only for dictation.
- Transcript text is no longer selectable in place: long-press a message for Copy or Select text.
- sudo, secret, failed-turn, rename, archive, context, usage, attachment and dictation surfaces follow the
  new design.

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
