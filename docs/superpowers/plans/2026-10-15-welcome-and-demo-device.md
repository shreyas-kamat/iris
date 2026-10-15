# Welcome screen and demo on the emulator (2026-10-15)

Release build (`flutter build apk --release`) on the Pixel 9 emulator, with **airplane mode on** throughout, so
nothing could reach a network. Branch `feat/welcome-and-demo`. App id at the time: `com.example.iris` (the
`com.iflotech.iris` change is on another branch).

| Check | Result |
|---|---|
| Welcome screen shows Same Wi-Fi, Tailscale, Cloudflare and, set apart, Try the demo | Pass |
| Try the demo opens home: Demo pill, usage bar (61% used), 4 conversations, Archived | Pass |
| New chat offers the four scripted prompts | Pass |
| "Check disk space on my server": thinking, two tool cards, approval card | Pass |
| Allow once leads to the sudo prompt; the typed value is masked and never shown afterwards ("Sent your sudo password.") | Pass |
| Final reply streams in with a Markdown table and inline code | Pass |
| Free text gets the honest fallback, with a tappable "connect your own Hermes server" link | Pass |
| That link, from inside the chat, returns to the welcome screen | Pass |
| Re-entering the demo works | Pass |
| "Restart the media server": approve, scripted failure with a Retry button | Pass |
| Retry replays the turn; second approval; success reply; transcript reloads clean | Pass |

Not checked on the device (covered by widget tests instead): Settings, Leave demo; search; rename and archive;
switching to the `homelab` profile; Stop and steer.

Not done: a LAN sign-in to the user's own server, which needs the user to type their credentials.
Task 1's check had already shown plain `http` reaches a host from a release build
(`docs/superpowers/plans/2026-10-15-cleartext-check.md`).

Airplane mode was turned off afterwards. Screenshots were deleted.
