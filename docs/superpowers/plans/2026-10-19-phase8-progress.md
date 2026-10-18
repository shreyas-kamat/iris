# Phase 8 progress log

Run book: `2026-10-19-phase8-run.md`. Plan: `2026-10-19-phase8.md`. Branch: `feat/phase8-voice`.
Update the table when a status changes; append journal entries at the bottom, newest last.

## Status

| Task | Title | Segment | Model | Status | Last commit |
|---|---|---|---|---|---|
| 0 | Extend the probe | S1 | Sonnet | blocked | |
| 1 | Voice capabilities, catalogue, backend, `VoiceSubmit` | S1 | Sonnet | todo | |
| 2 | Providers, device prefs and call spans | S1 | Sonnet | todo | |
| 3 | `IrisVoiceOrb` | S1 | Sonnet | todo | |
| 4 | Composer: orb, voice button, permission sheets | S1 | Sonnet | todo | |
| 5 | `SpeakStream` and `TranscribeStream` | S1 | Sonnet | todo | |
| 6 | Audio seams, levels, detectors | S2 | Opus | todo | |
| 7 | `VoiceCall` and the chained engine | S2 | Opus | todo | |
| 8 | Preflight | S2 | Opus | todo | |
| 9 | GPT-Live engine | S2 | Opus | todo | |
| 10 | Background, notification, interruptions | S2 | Opus | todo | |
| 11 | Voice screen | S3 | Sonnet | todo | |
| 12 | Approvals and questions by voice | S3 | Sonnet | todo | |
| 13 | Captions and the call divider | S3 | Sonnet | todo | |
| 14 | Voice settings and the picker | S3 | Sonnet | todo | |
| 15 | Demo scripted call | S4 | Haiku | todo | |
| 16 | Goldens, privacy policy, release notes | S4 | Haiku | todo | |
| 17 | Live tests | S5 | Sonnet | todo | |
| 18 | Device pass | S5 | Sonnet | todo | |
| 19 | Final review | S6 | Opus | todo | |

Segments: S1 tasks 0–5 Sonnet · S2 tasks 6–10 Opus · S3 tasks 11–14 Sonnet · S4 tasks 15–16 Haiku ·
S5 tasks 17–18 Sonnet · S6 task 19 Opus. Stop at every segment boundary and ask the user to continue in a new chat on
the next model.

## Journal

### Setup — 2026-10-19
- Spec `8671b83`, probe `bb9adf2`; plan, run book, this log and `/phase8` added on `feat/phase8-voice` (cut from
  `main` at `f4bdcc4`).
- Open items: none. Next: Task 0, Step 1.

### Task 0 — blocked — 2026-10-19 — Sonnet 5.5
- Step 1 is written and `flutter analyze` is clean, but it is uncommitted in `test/live/phase8_probe_live_test.dart`: it adds
  a second test (`include_defaults=false`, both leases, silent-WAV transcribe, speak-stream, transcribe-stream, a throwaway
  `voice_turn` submit plus interrupt) and a failure-kind reason on the link assertion.
- Step 2 not run: `~/.iris-live.json` exists, but the link is `blocked` with a `tls` failure (the pre-existing probe test fails
  the same way). `curl https://hermes.shreyaskamat.in/` gets "Connection was reset" and no certificate comes back, so the
  server is unreachable from this machine, not a certificate problem on our side.
- Needs the user: get the server reachable (VPN, network, Cloudflare Access or the host being down), then re-run `/phase8`.
- Next: Task 0, Step 2.
