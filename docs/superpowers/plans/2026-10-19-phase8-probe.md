# Phase 8 probe note

Run 2026-10-19 against the user's Hermes with `flutter test --tags live --run-skipped test/live/phase8_probe_live_test.dart`.
No keys, transcripts or audio are recorded here.

## Results

| Probe | Result |
|---|---|
| `GET /api/config` | ok. `stt: {enabled: true, provider: openai, streaming: false, language: en}`, `tts: {provider: edge}` |
| `voice` block | `voice_chat_mode: chained`, `max_recording_seconds: 120`, `auto_tts: false`, `client_direct: true`, `silence_threshold: 200`, `silence_duration: 3.0`, `barge_in: true`, `barge_in_grace_seconds: 0.5`, `barge_in_threshold_multiplier: 3.0`, `stop_phrases: [stop]`, `thinking_sound: true` |
| `GET /api/config?include_defaults=false` | ok. Returns only the profile's own keys: `tts` present, **`voice` absent** (the voice block is all defaults) |
| `GET /api/audio/voice-config` | ok. `stt: direct, openai-multipart, streaming false`; `tts: relay, "provider 'edge' has no client wire"` |
| `GET /api/audio/voice-live/status` | ok. `{mode: chained, available: true, reason: null, model: gpt-live-1, voice: marin}` |
| `GET /api/audio/elevenlabs/voices` | ok, `available: false`, 0 voices |
| `POST stt-lease` active true / false | ok both. `warmed: false, action: noop` on activate; `leases` 1 then 0 |
| `POST tts-lease` active true / false | ok both. `provider: edge, warmed: true, action: cached`; `leases` 1 then 0 |
| `POST /api/audio/transcribe` (300 ms silence) | First run: HTTP 400, STT model `nvidia/parakeet-tdt-0.6b-v3` not installed. **Re-run after the server's STT was fixed: `ok: true`, `transcript: ""`, as expected** |
| `POST /api/audio/speak` "Ready." | **rejected, HTTP 400:** `TTS chunk 1 failed (edge): ... 403 'Invalid response status'` from Microsoft's Edge speech endpoint. No audio |
| `speak-stream` "Ready." + done | Socket opens. **No `start` frame, no binary frames; final frame `fallback`** |
| `transcribe-stream` (`stt.streaming` off) | First frame `{type: error, message: "no live STT for the configured provider"}` |
| `prompt.submit` with `voice_turn: true` | **accepted**, `status: streaming`; `session.interrupt` ok |

## Decisions

- `include_defaults=false` supported: **yes**. The voice write must tolerate the `voice` block being absent in it (create it).
- Leases exist: **yes** (both).
- Speak-stream sample rate: **not observed**. The server answered `fallback` and sent no audio, and one-shot speak also
  fails (Edge 403), so the `start` rate stays unverified until the server's TTS works.
- `voice_turn` accepted: **yes**. Task 7 sends it as planned.
- Live transcribe-stream: unavailable, as expected with `stt.streaming` off.

## Open problems (need the user)

1. ~~Transcribe fails~~ Fixed on the server; re-probed `ok ""`.
2. **TTS is broken server-side.** Edge synthesis gets 403 from Microsoft's speech service, so one-shot speak fails and
   speak-stream answers `fallback` with no audio. The `fallback` is therefore not a usable path: no call can speak until
   the server's TTS works (switch `tts.provider` to another provider such as openai, or fix Edge). Speak-stream's `start`
   rate stays unobserved until then.
