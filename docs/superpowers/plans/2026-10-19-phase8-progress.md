# Phase 8 progress log

Run book: `2026-10-19-phase8-run.md`. Plan: `2026-10-19-phase8.md`. Branch: `feat/phase8-voice`.
Update the table when a status changes; append journal entries at the bottom, newest last.

## Status

| Task | Title | Segment | Model | Status | Last commit |
|---|---|---|---|---|---|
| 0 | Extend the probe | S1 | Sonnet | done | d716116 |
| 1 | Voice capabilities, catalogue, backend, `VoiceSubmit` | S1 | Sonnet | done | e44d562 |
| 2 | Providers, device prefs and call spans | S1 | Sonnet | done | bcfa563 |
| 3 | `IrisVoiceOrb` | S1 | Sonnet | done | 98b5793 |
| 4 | Composer: orb, voice button, permission sheets | S1 | Sonnet | done | 1ce5787 |
| 5 | `SpeakStream` and `TranscribeStream` | S1 | Sonnet | done | e54dd65 |
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

### Task 0 — blocked (probe run, two failures) — 2026-10-19 — Sonnet 5.5
- Server reachable again; Steps 1–3 done. Note: `2026-10-19-phase8-probe.md`. Probe commit follows this entry.
- Verified: `flutter test --tags live --run-skipped test/live/phase8_probe_live_test.dart` → `All tests passed!`; `flutter analyze` clean.
- `include_defaults=false` yes (no `voice` key in it); leases yes; `voice_turn` accepted.
- **Failed, so blocked per Step 3:** transcribe returns HTTP 400 (server STT model `nvidia/parakeet-tdt-0.6b-v3` not installed,
  not `ok ""`); speak-stream answers `fallback` with no `start`/audio (edge has no client wire), so the rate is unobserved.
- Needs the user: fix the server's STT, and decide whether `fallback` is acceptable as this server's normal TTS path.
- Next: Task 0 done once the user answers; then Task 1, Step 1.

### Task 0 — blocked (re-probed) — 2026-10-19 — Sonnet 5.5
- Re-ran after the user re-invoked `/phase8`: transcribe is now `ok ""` (STT fixed). Added a one-shot speak probe.
- **Still blocked:** `POST /api/audio/speak` fails (Edge TTS 403 from Microsoft), and speak-stream gives `fallback` with no
  audio. The server cannot speak at all, so the speak-stream rate cannot be recorded.
- Needs the user: make the server's TTS work (another `tts.provider`, or fix Edge), then `/phase8`.
- Next: re-run the probe; if speak-stream gives `start` and PCM, mark Task 0 done and start Task 1, Step 1.

### Task 0 — Extend the probe — done — 2026-10-19 — Sonnet 5.5
- Commits: f29d1a0 test(phase8): probe leases, sockets and voice turns; a2ea41b test(phase8): probe one-shot speak, record TTS failure; d716116 docs(phase8): probe note, server STT and TTS working
- Verified: `flutter test --tags live --run-skipped test/live/phase8_probe_live_test.dart` → `All tests passed!`; `flutter analyze` clean on the probe. Transcribe silence `ok ""`; one-shot speak `ok audio/mpeg`; speak-stream `start` 24000 Hz mono, 1 frame, `end`. Note: `2026-10-19-phase8-probe.md`.
- Packages: none
- Deviations: added a one-shot speak probe (not in Step 1) to tell a speak-stream `fallback` from a broken TTS; the user fixed the server's STT and TTS between runs.
- Decisions for later tasks: `include_defaults=false` works but has no `voice` key, so the voice write must create the block; leases exist; `voice_turn` is accepted; speak-stream rate 24000; transcribe-stream is unavailable with `stt.streaming` off (error frame "no live STT for the configured provider").
- Next: Task 1, Step 1

### Task 1 — Voice capabilities, catalogue, backend, VoiceSubmit — done — 2026-10-19 — Sonnet 5.5
- Commits: e44d562 feat(phase8): voice capabilities, catalogue and the voice backend
- Verified: `flutter test test/data/voice_capabilities_test.dart test/data/voice_backend_test.dart test/data/chat_backend_test.dart` → all passed (96); `flutter test test/data test/demo test/app` → `All tests passed!` (419); `flutter analyze` → `No issues found!`
- Packages: none
- Deviations: (1) `VoiceSubmit` lives in `lib/data/chat/chat_models.dart`, not a voice file, so chat does not import voice code. (2) The `submit sends voice fields only when set` test is in `chat_backend_test.dart`, where the chat harness is. (3) `DashboardVoice` sends `profile` explicitly on every route, the default profile included (the plan's tests expect `profile=default`), and also on the config `PUT` so a named profile's document is never written to default. (4) `capabilities()` treats only a 404 on live status as chained; another failure there is an `Err`. (5) Added an `IoAudioSocket` loopback test and `FakeVoiceBackend`.
- Decisions for later tasks: `AudioConnector` is `(Uri, Map<String,String>) -> Future<AudioSocket>`; `IoAudioSocket.connect(uri, headers, {client})` is the default. `FakeAudioSocket` has `serverSends(Map)`, `serverSendsBytes`, `sentJson`, `sentBytes`, `closed`; `FakeVoiceBackend` has settable `*Result` fields, `calls`, `sockets` (queue) and `opened`. The lease name is `iris-voice`; a lease body with `ok: false` is an `Err`. The speak stream's rate on this server is 24000 (Task 0 note). `ChatBackend.submit` sends `voice_turn`/`interrupted`/`surface`/`voice_context` only when set; the retry-without-`voice_turn` rule is Task 7's.
- Next: Task 2, Step 1

### Task 2 — Providers, device prefs and call spans — done — 2026-10-19 — Sonnet 5.5
- Commits: bcfa563 feat(phase8): voice providers, settings and call spans
- Verified: `flutter test test/app test/data/preferences_store_test.dart` → `All tests passed!` (50; the new file has 12); `flutter analyze` → `No issues found!`
- Packages: none
- Deviations: none. Extra tests: no live link and demo mode are `none`/null; settings load from saved values and ignore damaged ones; spans follow the profile.
- Decisions for later tasks: `activeVoiceProvider` returns null in demo mode until Task 15 replaces that line; `voiceCapabilitiesProvider` is `none` on any failure, so callers use `ref.invalidate(voiceCapabilitiesProvider)` to re-read. `VoiceSettingsController` methods are `setStyle(CallStyle)`, `setSpeaker(speaker:)`, `setCaptions(captions:)`; booleans are stored as `'true'`/`'false'`, speaker defaults on and captions off. `PreferenceKeys.voiceStyle/voiceSpeaker/voiceCaptions/voiceTagsSeen/voiceCalls(id)` exist (app-wide scope `''` except spans). Spans: `VoiceCallSpan(startedAt, endedAt, fromIndex)`, `voiceCallSpansProvider(storedId)`, `ref.read(voiceCallSpansWriterProvider).add(storedId, span)`, cap 20; they live in `lib/app/device_state.dart`.
- Next: Task 3, Step 1

### Task 3 — IrisVoiceOrb — done — 2026-10-19 — Sonnet 5.5
- Commits: 98b5793 feat(phase8): the voice orb
- Verified: `flutter test test/design/iris_voice_orb_test.dart` → `All tests passed!` (16); `flutter test test/design` → `All tests passed!` (278); `flutter analyze` → `No issues found!`. Looked at the regenerated `gallery_aperture_dark.png`: all 12 modes render as distinct still frames.
- Packages: none
- Deviations: (1) `VoiceOrbMode` is defined in `palette.dart` beside `AgentState` (the palette cannot import a component) and re-exported from `iris_voice_orb.dart`. (2) The O1 sheet in the gallery changes the whole-page gallery goldens, so the seven `gallery_*.png` goldens were regenerated here, not in Task 16; Task 16 still adds the dedicated O1/B/C/E goldens. (3) Added an optional `semanticLabel` and three `@visibleForTesting` getters on the public `IrisVoiceOrbState` (`smoothedLevel`, `ripplePresence`, `pulseAlpha`). (4) The still pulse and the 400 ms band cross-fade run only for `still: true` and never under the system's reduced motion, which is fully static.
- Decisions for later tasks: `IrisVoiceOrb(mode, size, level, still, semanticLabel)`; pass `level` (0..1 `ValueListenable<double>`) in the app so the orb uses the real level, not the simulation. `ringRadiusFor(mode, level)` returns a share of the size. A 50 ms cap per frame applies, so tests of easing must pump in small steps. `context.palette.voiceOrbColor(mode)` is the one colour source.
- Next: Task 4, Step 1

### Task 4 — Composer: orb, voice button, permission sheets — done — 2026-10-19 — Sonnet 5.5
- Commits: 1ce5787 feat(phase8): the orb in the composer and the voice button
- Verified: `flutter test test/features/dictation_ui_test.dart test/features/voice_entry_test.dart` → `All tests passed!` (26); `flutter test test/features test/app test/design test/data` → all passed after regenerating the 8 chat goldens; `flutter analyze` → `No issues found!`. Looked at the regenerated `screen_chat_empty_dark.png` (rounded-square mic left of a quiet Send).
- Packages: permission_handler 13.0.2 (published 2026-09-04; resolved against Flutter 3.41.6 with six additive packages in the lock, plus the generated Windows plugin files). Platform files: the Android `RECORD_AUDIO` and iOS `NSMicrophoneUsageDescription` already existed. **iOS:** the repo has no `ios/Podfile` (generated on a Mac), and `permission_handler` needs `'PERMISSION_MICROPHONE=1'` in the Podfile's `GCC_PREPROCESSOR_DEFINITIONS` or it reports the microphone as denied. Add this when the iOS build is first made (Task 18 / release).
- Deviations: (1) The first-run tags and `ensureMicAccess` find the provider container with `maybeProviderContainer(context)` (`lib/app/scope.dart`) and do nothing, answering `granted`, when there is no `ProviderScope` (the existing chat-screen tests have none; the recorder still refuses in its own way). (2) The Send button now always shows in the action slot when the voice button does not, so an empty field without voice mode has a dimmed Send beside the mic (as the plan's "mic still present to its left" implies). (3) 8 chat goldens regenerated here because the composer changed; Task 16 still adds the dedicated ones. (4) `onVoice` on the chat screen only asks for the microphone for now; Task 11 opens the call screen there. (5) The conversation list builds the chat inside a `Consumer` so the voice button appears when the capability read lands.
- Decisions for later tasks: `Composer` gained `voiceMode`, `onVoice`, `maxRecording`; `ChatScreen` gained `VoiceHost? voice` (`lib/features/voice/voice_host.dart`); `ensureMicAccess(context)` returns `MicAccess.granted|denied`; `micPermissionProvider` / `MicPermission` / `FakeMicPermission` (in `test/support/fake_voice.dart`); `PreferenceKeys.voiceMicAsked`. The recording bar's orb is `IrisVoiceOrb` (46) with mode listening below level .3, hearing at or above. Only `conversation_list_screen` passes a `VoiceHost`; the archived, job and task chat screens have no voice.
- Next: Task 5, Step 1

### Task 5 — SpeakStream and TranscribeStream — done — 2026-10-19 — Sonnet 5.5
- Commits: e54dd65 feat(phase8): speak-stream and transcribe-stream protocols
- Verified: `flutter test test/data/speak_stream_test.dart test/data/transcribe_stream_test.dart` → `All tests passed!` (32); `flutter analyze` → `No issues found!`; full `flutter test` (not live) → `All tests passed!` (1286 passed, 9 skipped).
- Packages: none
- Deviations: (1) A speak-stream `error` frame is treated as `SpeakFallback` (not in the plan) so a failed synthesis still gets the reply spoken by one-shot. (2) A `start` frame with no usable `sample_rate` is ignored rather than crashing. (3) `finish()` takes a `timeout` (default 60 s) and answers `FailureKind.timeout`. (4) Extra tests: whitespace deltas are kept, `done` is sent once, nothing is delivered after the end, frames wait for a listener.
- Decisions for later tasks: `SpeakStream(socket)`: `add(text)`, `done()`, `stop()` (sends stop, closes, `frames` ends with no event), `frames` single-subscription and buffered; the last frame is always `SpeakEnd` or `SpeakFallback` unless `stop()` was called. `TranscribeStream(socket, sampleRate:)` sends `{sample_rate}` on construction; `partials` is a broadcast stream; `finish({timeout})` returns `Err` for an error frame (`server`, with the server's message), a drop (`offline`), a timeout, or a cancel (`cancelled`). On this server `stt.streaming` is off, so the stream answers `error "no live STT for the configured provider"`: a caller must only open it when `VoiceCapabilities.liveTranscription` is true.
- Next: Task 6, Step 1

### Segment S1 complete — 2026-10-19
- Tasks 0–5 are done and logged (last commit e54dd65). Branch `feat/phase8-voice`.
- Next segment: S2 (tasks 6–10), needs **Opus**; first task: Task 6, Audio seams, levels, detectors.
- Open items for S2/S5: iOS needs `PERMISSION_MICROPHONE=1` in the Podfile when the iOS build is first made (Task 4 note). The server's speak-stream gives 24000 Hz mono, so `AudioOut` must play at the rate in the `start` frame.
