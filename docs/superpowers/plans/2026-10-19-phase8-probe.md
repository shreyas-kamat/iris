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
| `POST /api/audio/transcribe` (300 ms silence) | **rejected, HTTP 400.** Body: `API error: Error code: 404 - Model 'nvidia/parakeet-tdt-0.6b-v3' is not installed locally`. Not `ok` with `""` |
| `speak-stream` "Ready." + done | Socket opens. **No `start` frame, no binary frames; final frame `fallback`** |
| `transcribe-stream` (`stt.streaming` off) | First frame `{type: error, message: "no live STT for the configured provider"}` |
| `prompt.submit` with `voice_turn: true` | **accepted**, `status: streaming`; `session.interrupt` ok |

## Decisions

- `include_defaults=false` supported: **yes**. The voice write must tolerate the `voice` block being absent in it (create it).
- Leases exist: **yes** (both).
- Speak-stream sample rate: **not observed**. The server answered `fallback` and sent no audio, so use one-shot speak
  (`POST /api/audio/speak`) on this server; the `start` rate stays unverified.
- `voice_turn` accepted: **yes**. Task 7 sends it as planned.
- Live transcribe-stream: unavailable, as expected with `stt.streaming` off.

## Open problems (need the user)

1. **Transcribe fails on the server.** The STT provider resolves to a local model (`nvidia/parakeet-tdt-0.6b-v3`) that is
   not installed, so every transcribe returns HTTP 400 instead of `ok` with `""`. Preflight's STT check and any call
   will fail against this server until its STT is fixed (install the model, or point `stt` at a working provider).
2. **Speak-stream yields `fallback` for "Ready."** Edge is a `relay` provider with no client wire. It may be that
   synthesis legitimately produced nothing through the stream, or the stream does not support Edge. This needs a decision:
   treat `fallback` as the normal path for this server (one-shot speak), or fix the server side.
