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
| 6 | Audio seams, levels, detectors | S2 | Opus | done | 6b41765 |
| 7 | `VoiceCall` and the chained engine | S2 | Opus | done | 589cc9e |
| 8 | Preflight | S2 | Opus | done | 36ed7b3 |
| 9 | GPT-Live engine | S2 | Opus | done | ed642ba |
| 10 | Background, notification, interruptions | S2 | Opus | done | 533d138 |
| 11 | Voice screen | S3 | Sonnet | done | e889b2e |
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

### Task 6 — Audio seams, levels, detectors — done — 2026-10-19 03:40 — Opus 5.5
- Commits: 6b41765 feat(phase8): mic PCM, playback, audio session and speech detection
- Verified: `flutter test test/features/voice_levels_test.dart` → `All tests passed!` (20); with `dictation_ui_test.dart` and `voice_entry_test.dart` → `All tests passed!` (46); `flutter build apk --debug` → `Built build\app\outputs\flutter-apk\app-debug.apk`; `flutter analyze` → `No issues found!`
- Packages: audio_session 0.2.4 (2026-06-29), flutter_pcm_sound 3.3.3 (2025-10-04, iOS PCM only), just_audio 0.10.6 (2026-06-29, one-shot files). **permission_handler 13.0.2 → 12.0.3** (2026-06-01): 13.x needs permission_handler_android 14.x, whose Gradle script assumes AGP 9's built-in Kotlin and fails to compile on this app's AGP 8.11.1, so the Android build had been broken since Task 4 (which never built an APK). The API Iris uses (`Permission.microphone.status/request`, `openAppSettings`) is unchanged; the Task 4 tests pass.
- Deviations: (1) Android PCM plays through the app's own `PcmOutChannel.kt` (method channel `iris/pcm_out`: an `AudioTrack` with `USAGE_VOICE_COMMUNICATION`, a writer thread, `end` answers once the playback head passes the last frame, `stop` pauses and flushes). `flutter_pcm_sound` hard-codes `USAGE_MEDIA` on Android, which the speaker/earpiece switch and the echo canceller ignore. iOS uses `flutter_pcm_sound` (play-and-record), with its byte logging turned off. (2) `AudioRoute.setSpeaker({required bool on})` is named (repo lint), not positional. (3) Detector rules the plan left open: `at` is the time at the end of a chunk; a take starts at the start of its first loud chunk; `SpeechStarted` comes on the loud chunk that makes the take 400 ms long, so a shorter take gives no events at all; "loud" is `rms > silenceThreshold`. Barge-in: the floor is the mean of the `calibrate` calls, the bar is `max(floor × multiplier, silenceThreshold)`, and uncalibrated the floor is the threshold. (4) The playback level comes from the PCM in 50 ms slices, played back on a timer; a one-shot file shows a flat 0.45 (no samples to measure). (5) `RouteInfo` has `==`; `PlatformAudioRoute.route` replays the current output to a new listener; interruptions of type `duck` are dropped.
- Decisions for later tasks: `rmsOf`, `orbLevel` in `levels.dart`; `SpeechDetector(tuning).feed(rms, at)` / `reset()`; make one `BargeInDetector` per reply. `RecordMicCapture` (Android source `voiceCommunication`, iOS session left to the route, `audioInterruption: none`, so Task 10 handles interruptions), `start()` is idempotent and shares an open in flight. `PlatformAudioOut({afterSetup})`: pass `PlatformAudioRoute.reapply` as `afterSetup`, because the iOS PCM player resets the category when it sets up (on the first reply and after every `stop`). `PlatformAudioRoute(speaker:)`: `activate` sets Android `MODE_IN_COMMUNICATION` and audio focus; the iOS category has no `defaultToSpeaker`, so the speaker is an explicit override, re-applied on device changes. Fakes in `test/support/fake_voice.dart`: `FakeMic` (`push`, `pushLevel(value)`, `allowed`, `starts/stops`), `FakeAudioOut` (`starts`, `pcm`, `files`, `drain()`, `finishFile()`, `emitLevel()`, `stops`, `playing`), `FakeAudioRoute` (`interrupt`, `unplug`, `plugIn`, `activations/deactivations`). For Task 18: earpiece routing, the echo canceller during playback and the iOS session after `flutter_pcm_sound` setup are unverified on a device.
- Next: Task 7, Step 1

### Task 7 — VoiceCall and the chained engine — done — 2026-10-19 — Opus 5.5
- Commits: 589cc9e feat(phase8): the voice call and the chained engine
- Verified: `flutter test test/features/voice_call_test.dart` → `All tests passed!` (42); with `test/data/speak_stream_test.dart` → 58 passed; `flutter test test/features test/data test/demo test/app` → `All tests passed!` (1046); `flutter analyze` → `No issues found!`
- Packages: fake_async 1.3.3 as a dev dependency (already in the lock through flutter_test; `flutter_test` does not re-export it).
- Deviations: (1) `ChatBackend` gained `Stream<bool> get liveChanges` (DashboardChat feeds it from `_onLink`; the demo answers empty), because `reconnected` alone cannot tell the call the link is down. `FakeChatBackend` has `linkDown()`/`linkUp()` and a `submitQueue`; `FakeVoiceBackend` has `wavs` and a `transcribeQueue`. (2) The CallEngine methods use named booleans (`setMuted({required bool muted})`, `hold({required bool down})`), and it gained `setStyle` and `linkChanged({required bool live})`; engines move the call through a `CallHost` (`state`, `update`, `level`, `now`, `markWorking`, `finish`). (3) `ChainedEngine.preflight` answers Ok: the checks are Task 8's. VoiceCall builds `ChainedEngine` for every engine until Task 9. (4) The speak stream opens on the first non-blank `TextDelta` (the plan allows it), so a tool-only reply opens no socket; the mic reopens at that moment for the barge-in floor, only when barge-in is armed (server on, hands-free, not muted, link up). (5) Fixed `SpeakStream.stop()` (Task 5): it now closes the socket before the frames controller, which may never finish closing once its reader has cancelled. (6) Subscription cancels and `SpeakStream.stop()` are not awaited, so nothing waits on root-zone futures (they hung under fakeAsync). (7) Rules the plan left open: one automatic retry of a failed upload before holding the take; in push to talk the mic opens only while held, there is no automatic barge-in, holding during a reply interrupts it, and a hold under 400 ms is ignored; muting closes the mic; after a barge-in, the old turn's end events are dropped until the new turn produces text, a tool or `MessageStarted`; a pause keeps the whole reply and `resume()` speaks it in full; a link down closes the mic while listening, and 30 s down fails the call ("The call ended unexpectedly."); an echo is all of the last reply or a run of 3+ of its words; a WAV includes up to 3 chunks (300 ms) before the first loud one; a mic that will not open fails the call with "Iris can't use the microphone."
- Decisions for later tasks: `VoiceCall(...).begin()/end()` (both idempotent; begin after end does nothing), `setMuted(muted:)`, `hold(down:)`, `toggleCaptions()`, `setStyle()`, `setSpeaker(on:)`, `pause()`, `resume()`, `retryHeld()`, `tick()` (a 1 s periodic timer runs until `end()`, so widget tests must end the call). `VoiceCallState.level` is a `ValueListenable<double>` (mic level while listening, playback level while speaking). `Caption(you, text, spoken)`; partial words from the transcribe stream show as the last `you` caption. `ChatController.runtimeId`, `sendVoice(text, VoiceSubmit)` → bool, `voiceFieldsRefused`. `wavOf(pcm)` is in `chained_engine.dart`. The engine ignores chat events unless a voice turn is in flight. Known gap: if the link drops and the turn finishes while it is down, no `MessageCompleted` reaches the call, which stays in thinking until the person ends it; worth a look in Task 17/18.
- Next: Task 8, Step 1

### Task 8 — Preflight — done — 2026-10-19 — Opus 5.5
- Commits: 36ed7b3 feat(phase8): preflight before a call listens
- Verified: `flutter test test/features/preflight_test.dart test/features/voice_call_test.dart` → `All tests passed!` (58); `flutter test test/features test/data` → `All tests passed!` (977); `flutter analyze` → `No issues found!`
- Packages: none
- Deviations: (1) `chainedPreflight` and `VoiceCall` take `server` (default "your Hermes server"), because the B10b copy names it and the plan's signature had nothing to name it from; Task 11 passes the server label. (2) A speak stream that cannot open, or that ends with no audio, also tries one-shot speech (as a fallback does). (3) Leases are released (`active: false`, both) when the chained engine ends after a preflight. (4) Lease answers, Ok or Err, are ignored: the lease only warms the provider. (5) `ChatController.ensureLive()` resumes a stored chat that is not attached (sharing `_attach` with `open()`), or creates a new one. (6) Not `await for` over the speak frames: leaving one early awaits the cancel, which hung under fakeAsync. (7) A timed-out check is `FailureKind.timeout`, any other is `server`; the message is the same.
- Decisions for later tasks: `defaultServerName`, `silentWav()` in `preflight.dart`. `FakeAudioSocket` has `onJson` and `FakeAudioSocket.speaking()` (answers `done` with start + PCM). The call rig in `voice_call_test.dart` queues a speaking socket before `begin()` and then clears what the preflight recorded (`forgetPreflight()`); Task 11's widget tests need the same.
- Next: Task 9, Step 1

### Task 9 — doing — 2026-10-19 — Opus 5.5
- Stopped for the usage limit. Nothing of Task 9 is committed; on disk, uncommitted: `pubspec.yaml`/`pubspec.lock` with **flutter_webrtc 1.6.2+hotfix.3** (2026-09-15; hotfix.4 is under two weeks old), and `flutter build apk --debug` already builds with it; `test/support/fake_voice.dart` with `FakeLivePeer` (autoStart, `sent`, `sentTypes`, `micOn`, `serverSends`, `level`) and `FakeVoiceBackend.offers`/`histories`; `test/features/gpt_live_test.dart` (Step 1, written, not yet run: it expects `liveHistory(items)`, `chunkForCommentary`, `VoiceCall(livePeer: () => peer)`, `LivePeer.setMicEnabled({required bool on})`).
- Next: Step 2 (run it, see it fail), then write `lib/features/voice/live_channel.dart` (LivePeer + WebRtcLivePeer: data channel `oai-events`, mic track disabled until start, remote level from getStats `inbound-rtp` audioLevel every 100 ms) and `gpt_live_engine.dart` (preflight: ensureLive, then step gptLive, offer → startGptLive(sdp, liveHistory) → answer → wait for `session.started`; Err → "GPT-Live couldn't start: {detail}"; delegation → sendVoice(text, VoiceSubmit(surface: 'voice-live', voiceContext)) with a 5-minute, 6,000-char window; MessageCompleted → commentary chunks `{type: session.commentary.append, text}`; mute/unmute/close events; `error` → fail; `session.closed` → end). Wire it into `VoiceCall` for `VoiceEngine.gptLive`.
- Unverified wire guesses to log: the field names `delta`/`text` on transcript deltas, `text` on commentary, `error.message`.

### Task 9 — GPT-Live engine — done — 2026-10-19 — Opus 5.5
- Commits: ed642ba feat(phase8): the GPT-Live engine
- Verified: `flutter test test/features/gpt_live_test.dart` → `All tests passed!` (18); `voice_call_test.dart` + `preflight_test.dart` → 58 passed; `flutter build apk --debug` → `Built build\app\outputs\flutter-apk\app-debug.apk`; `flutter analyze` → `No issues found!`
- Packages: flutter_webrtc 1.6.2+hotfix.3 (2026-09-15; hotfix.4 was under two weeks old). No manifest change was needed for the debug build.
- Deviations: (1) `LivePeer.setMicEnabled({required bool on})` is named (repo lint). (2) `VoiceCall` gained `LivePeer Function()? livePeer` (default `WebRtcLivePeer.new`) so tests inject `FakeLivePeer`. (3) The engine owns its preflight: the agent check, then step gptLive (offer with the mic track disabled, `startGptLive(sdp, liveHistory(items))`, answer, wait for `session.started`), each within 20 s; failures read "GPT-Live couldn't start: {server detail | it did not answer in time. | the microphone or the connection failed.}". (4) Rules the plan left open: the delegation's text is its own `text`/`request`/`prompt`/`task`/`instructions` field when present, otherwise the last thing the person said; a repeated delegation id is ignored; `VoiceSubmit` for GPT-Live carries `surface` and `voiceContext` only (no `voice_turn`); an `error` event ends the call unless it says `fatal: false`; a failed turn is reported as commentary "That didn't work: …"; "hearing" lasts 1.5 s after the last input delta; the speaking threshold is a remote level above 0.05; push to talk enables the mic track only while held; a pause mutes the session and the track.
- Unverified until a GPT-Live server is tried (Task 18): the field names `delta`/`text` on transcript deltas, `text` on `session.commentary.append`, `error.message`; the remote level comes from `getStats()` `inbound-rtp` `audioLevel` every 100 ms; `flutter_webrtc` manages Android audio itself and may fight `PlatformAudioRoute` (speaker switching), to be checked on the phone.
- Decisions for later tasks: `liveHistory`, `chunkForCommentary` in `gpt_live_engine.dart`; `LivePeer`, `WebRtcLivePeer` in `live_channel.dart`; `FakeLivePeer` (autoStart, `sent`, `sentTypes`, `micOn`, `answered`, `closed`, `serverSends`, `level`). GPT-Live captions are the input/output transcript lines. Task 12's spoken prompt for GPT-Live goes through the same commentary path.
- Next: Task 10, Step 1

### Task 10 — Background, notification and interruptions — done — 2026-10-19 — Opus 5.5
- Commits: 533d138 feat(phase8): calls keep going in the background
- Verified: `flutter test test/features/call_service_test.dart` → `All tests passed!` (13); `flutter build apk --release` → `Built build\app\outputs\flutter-apk\app-release.apk (107.0MB)`; `aapt dump permissions` lists FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, POST_NOTIFICATIONS, WAKE_LOCK, MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT (plus the plugins' ACCESS_NETWORK_STATE and BLUETOOTH maxSdk 30); `flutter analyze` → `No issues found!`; full `flutter test --exclude-tags live` → `All tests passed!` (1395, 4 skipped).
- Packages: flutter_foreground_task **10.0.0** (2026-07-15). 11.x needs a newer Flutter SDK than this repo's 3.41.6 and does not resolve. Its Gradle build uses Kotlin 1.9 and prints "incompatible version of Kotlin" `e:` lines in the release build, but the build succeeds.
- Deviations: (1) `RECEIVE_BOOT_COMPLETED`, which the plugin's own manifest adds for auto-start on boot, is removed with `tools:node="remove"`: a call never restarts after a reboot. (2) `VoiceCall` gained `CallService? service`; the service starts only after the preflight passes and before the engine listens, and stops on every end path (End, stop phrase, error, the 30 s link loss, dispose); a failed check never starts it. (3) `CallNotice` equality ignores `elapsed`, so the clock alone never re-sends the notification. (4) `noticeText` also covers the other modes: connecting "Connecting", interrupted "Hearing you", needs "Needs you", error/ended "Call ended"; times of an hour or more read h:mm:ss. (5) iOS: `ForegroundCallService` does nothing there (the `audio` background mode keeps the call; the system shows its mic indicator). (6) The notification permission is asked once per app run, on the first call's service start; a refusal only hides the notification. (7) Interruptions and becoming-noisy are handled in `VoiceCall` for both engines.
- Decisions for later tasks: Task 11 passes `ForegroundCallService()` as `service` (and `PlatformAudioRoute`, `RecordMicCapture`, `PlatformAudioOut(afterSetup: route.reapply)`). `FakeCallService` (`starts`, `updates`, `stops`, `running`, `current`, `press(CallAction)`). The notification's buttons are Mute/Unmute and End; tapping it launches the app. The service's isolate only forwards button ids (`startCallTask`, top-level, `vm:entry-point`).
- Next: Task 11, Step 1

### Segment S2 complete — 2026-10-19
- Tasks 6–10 are done and logged (last commit 533d138). Branch `feat/phase8-voice`.
- Next segment: S3 (tasks 11–14), planned for **Sonnet**; first task: Task 11, Voice screen.
- Open items: on a device (Task 18), check earpiece routing, the echo canceller during playback, the iOS session after `flutter_pcm_sound` setup, `flutter_webrtc` and `PlatformAudioRoute` together, and the GPT-Live field names logged in Task 9. iOS still needs `PERMISSION_MICROPHONE=1` in the Podfile (Task 4 note).

### Task 11 — The voice screen — done — 2026-10-19 — Sonnet 5.5
- Commits: e889b2e feat(phase8): the voice call screen
- Verified: `flutter test test/features/voice_screen_test.dart` → `All tests passed!` (45); `flutter test test/features test/app test/data test/demo test/design --exclude-tags live` → `All tests passed!` (1416); `flutter build apk --debug` → `Built buildpp\outputslutter-apkpp-debug.apk`; `flutter analyze` → `No issues found!`
- Packages: wakelock_plus 1.7.0 (2026-07-21; 1.8.x is newer than two weeks but 1.7.0 is the pin). `macos/Flutter/GeneratedPluginRegistrant.swift` regenerated by `pub get` and committed with it.
- Deviations: (1) `openVoiceCall(context, {call, awake})` returns `Future<VoiceCallExit>` (`done` or `again`), not `Future<void>`, so B10b's Call again can start the next call from the chat; the chat records the span and builds the call. (2) `VoiceHost` gained `settings`, `server` and `parts` (a `CallParts` of mic, playback, route, service, awake, livePeer; `CallParts.platform(settings)` is the default and tests pass fakes); `VoiceCall` gained public `engine`, `server` and `title`. (3) The header's chevron, the system back button, and leaving the screen any other way all end the call; there is no minimised call. The call ending from outside (stop phrase, the notification's End) pops the screen. (4) The "Hands-free / Push to talk" chip in the header is tappable and switches the style (`VoiceCall.setStyle`). (5) Not in the plan: a "Try again" button on the screen when a take is held (`heldTake`), a `needs` placeholder (NEEDS YOUR OK / "Iris is waiting for you.") until Task 12 adds the cards, and PTT copy "Let go when you're done." while held. (6) The thinking and tool clocks show only after 10 s of work; the reconnect clock counts from when the screen first saw `reconnecting`, using the call's own elapsed. (7) Chrome labels and button labels clamp text scaling at 130% so the control row and the D3/B10b buttons never overflow at 200%; the body text scales fully and the middle scrolls. (8) A span is recorded only if the call got past connecting, and only when the chat has a stored id.
- Decisions for later tasks: `callCopy(state, server:, reconnectingFor:)` and `callClock` in `voice_call_screen.dart` are the one place for status copy; `CallControlsRow` keys are `call-mute`, `call-captions`, `call-route`, `call-end`. Captions still only toggle `VoiceCallState.captions`; Task 13 draws the layer in `_Stage`'s place and shrinks the orb to 104. Task 12 replaces the `needs` copy with the decision card in `_Stage`. `ChatScreen` keeps the open call in `_call` and ends it in `dispose`.
- Next: Task 12, Step 1
