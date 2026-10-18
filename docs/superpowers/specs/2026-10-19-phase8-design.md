# Phase 8 — Live voice mode

**Date:** 2026-10-19. **Branch:** `feat/phase8-voice`, cut from `main` at `f4bdcc4` (Phase 7, #27).
Builds on Phase 5's dictation (`2026-10-15-phase5-design.md`) and Phase 7 (`2026-10-17-phase7-design.md`).
**Design:** the claude.ai/design project "Iris Chat App Design", file `Iris Phase 4.dc.html` (Claude Design's own phase
numbering), checked in at `design/Iris Phase 4.dc.html` with its orb at `design/iris-voice.js`. Frames: O1, O2;
A1a, A1b, A2, A2b, A3a, A3b, A4 and their ·L, plus A1b·320/·320L/·RM/·RML; B1, B2, B2b, B3–B8, B9a, B9b, B10a, B10b and
their ·L; B3·320, B6·320, B3·RM, B6·RM and their light twins; C1, C2 and ·L; D1, D3a, D3b and ·L; E1a, E1b and ·L.
D2 (iOS Live Activity) is in the file but belongs to Phase 9.
The design is the source of truth for sizes, colours, motion numbers, copy and states. This spec says what each frame
needs from the code and where the code differs from the design. It does not repeat the design's numbers.

## Goals

Talk to Iris instead of typing: ask it to check the status of things, give it tasks, approve its work, with the phone
in your hand or in your pocket.

1. **A live voice conversation** on the open chat (B1–B10b): Iris listens, Hermes does the turn, Iris speaks the reply
   while it streams, and you can talk over it.
2. **The orb is the microphone.** One voice orb (O1, O2) shows hearing, thinking, tools and speaking, and replaces
   dictation's level strip (A1a, A1b).
3. **Iris adapts to each server's voice setup.** Iris is open source and every Hermes is configured differently; it reads
   the server's own voice config and offers only what that server can do (A4, E1b).
4. **Nothing you say is lost.** A call starts only after speech-to-text, the agent and text-to-speech have all answered.
   A failed transcription keeps the recording.
5. **It works out of sight.** The call keeps going with the screen locked, with an Android ongoing notification (D1),
   and pauses cleanly for phone calls and unplugged headphones (D3a, D3b).
6. **Voice settings** (E1a, E1b), including the server's voice.

## Decisions

Made by the user on 2026-10-18 and 2026-10-19:

- **Voice mode is its own phase (8).** The old "native" phase becomes Phase 9.
- **The orb replaces the level strip** in dictation and in voice mode. No strip anywhere.
- **Iris adapts to every server's configuration**, not just the user's.
- **Both Hermes voice engines:** `chained` (STT → Hermes turn → TTS) and **GPT-Live** (OpenAI's full-duplex voice model
  delegating to Hermes over WebRTC). Gemini Live is Phase 9.
- **The iOS Live Activity and Dynamic Island (D2) are Phase 9**, with the widgets. On iOS a locked-screen call relies on
  background audio and the system's own microphone indicator.
- **The voice picker writes the server's voice.** It changes the voice for every client of that profile.
- **Iris ships built-in voice lists** for providers whose server does not list voices.
- **Check before talking:** a call starts only after STT, the agent and TTS have been confirmed. Nothing is listened to
  before then.
- **GPT-Live's audio path is disclosed.** In a GPT-Live call the audio goes between the phone and OpenAI while the work
  and the history stay on the user's server; the privacy policy says so, and the call screen's header reads
  "VOICE · GPT-LIVE · OPENAI" instead of "VOICE · {server}".
- **Model-wise tasks and a resume command.** The plan assigns each task a model, and a `phase8` project command runs or
  resumes the plan from its progress log, so a fresh chat on another model can pick it up.

Made while writing the spec (change any of them by saying so):

- **Audio always goes through the user's server for chained calls.** Iris never uses `GET /api/audio/voice-config`'s
  provider keys (`client_direct`), so no provider key ever sits on a phone. GPT-Live is the exception that the engine
  itself forces: the media stream runs phone ↔ OpenAI over WebRTC, though the key stays on the server (see Platform
  and release).
- **The server picks the engine.** Iris reads `voice.voice_chat_mode` and never offers a local override.
- **The server's voice tuning wins.** Silence length, silence threshold, barge-in on/off, its threshold and grace, the
  stop phrases, the recording cap and the thinking sound all come from the server's `voice.*` config.
- **No barge-in while the agent is thinking or running a tool.** The mic is closed then (B4 and B5 say "no mic
  reaction"), so a cough cannot cancel a two-minute job. Barge-in is armed only while Iris is speaking. Hermes Desktop
  also interrupts during generation; Iris deliberately does not.
- **Built-in voice lists:** OpenAI TTS's 13 voices and GPT-Live's 14 (both copied from the Hermes source, below), and for
  Edge the five voices Hermes itself suggests (Aria, Jenny, Andrew, Brian, Sonia). The server's current voice is always
  shown as selected even when it is not in the list.
- **Call spans are stored on the device** so the "voice · 4 min" divider (C2) survives a reload on this device. Hermes
  does not mark voice rows, so another device shows the turns without the divider.
- **Demo mode runs a scripted call** with no real audio and no permission prompts, so a reviewer sees every B and C
  frame.

## Verified in the Hermes source (upstream `main` at `54809183`, read 2026-10-19)

Every audio route takes `?profile=`. Every audio WebSocket authenticates like `/api/ws`: a fresh `POST /api/auth/ws-ticket`
ticket in `?ticket=` (single use, 30 s) plus the Cloudflare Access headers, exactly as Iris dials `/api/ws` today.

| Area | Wire |
|---|---|
| Config read | `GET /api/config[?profile=]` (merged with defaults); `?include_defaults=false` gives the profile's own values; `GET /api/config/defaults` |
| Config write | `PUT /api/config {config}` writes the whole document. There is no single-key write for `tts.*`/`voice.*`: the `config.set` RPC only knows a fixed list of setters |
| Engine | `voice.voice_chat_mode`: `chained` (default) or `gpt-live` |
| GPT-Live status | `GET /api/audio/voice-live/status` → `{ok, mode, available, reason, model, voice}` (non-secret; `available` = a key resolves). 404 on older servers → chained |
| Transcribe | `POST /api/audio/transcribe {data_url, mime_type}` → `{ok, transcript, provider}`. Silence or "empty transcript" answers **ok with `""`**, not an error. 25 MB cap |
| Live transcribe | WS `/api/audio/transcribe-stream`: client sends `{"sample_rate": N}` (8000–48000), binary s16le mono frames, `{"eos": true}`; server sends `{type:"partial", text}`, `{type:"final", transcript, provider}` or `{type:"error", message}` (also when the provider has no live STT). Only when `stt.streaming` is on |
| Speak (one shot) | `POST /api/audio/speak {text}` → `{ok, data_url, mime_type, provider}` |
| Speak stream | WS `/api/audio/speak-stream`, one socket per reply: client sends `{"text": …}` deltas, `{"done": true}`, `{"stop": true}` (or closes) for barge-in; server sends `{type:"start", sample_rate, channels: 1}` with the first audio, binary int16 mono PCM, `{type:"end"}`, or `{type:"fallback"}` when synthesis produced nothing (then use one-shot speak). Markdown is stripped server-side; sentences are cut server-side |
| Warm-up | `POST /api/audio/stt-lease` and `/api/audio/tts-lease {lease, active}`; failures are reported in the body, never as an HTTP error |
| Voices | `GET /api/audio/elevenlabs/voices` → `{available, voices: [{voice_id, name, label}]}` (the only provider with a list endpoint) |
| GPT-Live session | `POST /api/audio/voice-live/session {sdp, history?}` → `{ok, session: {id}, transport: {type: "webrtc", sdp}}`; 503 no key, 502 vendor refusal. The vendor SDP must be sent byte-exact |
| GPT-Live data channel | `oai-events`. In: `session.started`, `session.input_transcript.delta`, `session.output_transcript.delta`, `session.delegation.created {delegation: {id}}`, `error`, `session.closed`. Out: `session.commentary.append` (≤ ~1,400 chars per append), `session.thinking.append`, `session.instructions.append`, `session.input_audio.mute`/`unmute`, `session.close` |
| Voice turns | `prompt.submit` gains `voice_turn: true` (chained: runs on `auxiliary.voice_chat`), `interrupted: true` (a barge-in), and for GPT-Live `surface: "voice-live"` + `voice_context` (recent spoken transcript, ≤ 6,000 chars) |

Server voice settings Iris reads (defaults in brackets): `stt.enabled` [true], `stt.provider`, `stt.streaming` [false],
`tts.provider` [edge], `tts.<provider>.voice` / `voice_id`, `voice.voice_chat_mode` [chained], `voice.gpt_live.voice`
[marin], `voice.max_recording_seconds` [120], `voice.silence_threshold` [200, RMS of int16], `voice.silence_duration`
[3.0 s], `voice.barge_in` [true], `voice.barge_in_grace_seconds` [0.5], `voice.barge_in_threshold_multiplier` [3.0],
`voice.stop_phrases` [["stop"]], `voice.thinking_sound` [true].

Built-in lists: OpenAI TTS (`gpt-4o-mini-tts`) alloy, ash, ballad, cedar, coral, echo, fable, marin, nova, onyx, sage,
shimmer, verse. GPT-Live marin, cedar, quartz, ripple, vesper, willow, stone, gleam, meridian, bossa, tempo, beacon,
delta, cinder. Edge en-US-AriaNeural, en-US-JennyNeural, en-US-AndrewNeural, en-US-BrianNeural, en-GB-SoniaNeural.

### Probed on the user's server (2026-10-19, `test/live/phase8_probe_live_test.dart`, read-only)

`stt: {enabled: true, provider: openai, streaming: false, language: en}`, `tts: {provider: edge}`,
`voice: {voice_chat_mode: chained, max_recording_seconds: 120, silence_threshold: 200, silence_duration: 3.0,
barge_in: true, barge_in_grace_seconds: 0.5, barge_in_threshold_multiplier: 3.0, stop_phrases: [stop],
thinking_sound: true}`. `voice-live/status` answers `mode: chained, available: true`. ElevenLabs voices
`available: false`. Task 0 extends this probe (Testing).

## Design

### Voice capability

`VoiceCapabilities` is read per server and profile from `GET /api/config` and `GET /api/audio/voice-live/status`, and
refreshed when the profile changes, when Settings opens, and before each call. It answers:

| Server state | What Iris offers |
|---|---|
| `stt.enabled: false`, or the config read 404s | No mic, no voice button (A4 without dictation) |
| chained | Dictation and voice mode |
| gpt-live, `available: true` | Dictation (still chained STT) and voice mode on GPT-Live |
| gpt-live, `available: false` | Dictation only. Settings › Voice says "GPT-Live needs an OpenAI key on {server}" |
| `stt.streaming: true` | Live partial captions of your own words (chained) |
| A voice list exists for the engine's provider | The Voice row (E1a); otherwise none (E1b) |

Whether text-to-speech actually works cannot be known from config. That is the preflight's job (below), and a failing
TTS is reported there, by name, rather than guessed at.

Before a capability read has succeeded the voice button is not drawn (Phase 7's "confirmed" rule): it must not be
offered and then fail. Dictation keeps Phase 5's optimistic behaviour.

### Preflight

Every call opens on B1 and runs these checks in order; the B1 subtitle names the current one. The orb turns pink (B2)
only when all have passed.

**Chained:**
1. *Agent:* the dashboard link is live and the conversation is attached (resumed, or created for a new chat).
2. *Speech-to-text:* `stt-lease` warm-up, then a 300 ms silent 16 kHz WAV through `POST /api/audio/transcribe`. Any `ok`
   passes (an empty transcript is the expected answer). This exercises the real provider and key.
3. *Text-to-speech:* `tts-lease` warm-up, then a `speak-stream` socket fed a short phrase ("Ready.") and `done`. Pass is a
   `start` frame and at least one PCM frame; the audio is discarded. `fallback` then retries one-shot `POST
   /api/audio/speak`; its `ok` passes.

**GPT-Live:** the agent check, then the WebRTC session reaches `session.started` with the remote audio track attached.

Each check has a 20 s budget (local Whisper or Piper may cold-load; the leases cut that). A failure ends on B10b with
the failing part named: "Iris can't reach speech-to-text on {server}", "…the agent…", "…text-to-speech…", or "GPT-Live
couldn't start: {server's reason}", with Try again and Back to chat. Nothing is recorded before the checks pass.

### Engines

Both engines drive one `VoiceCall` state machine whose states are the orb modes:
`connecting → listening ⇄ hearing → thinking ⇄ tool → speaking → listening …`, plus `interrupted`, `muted`,
`needs`, `reconnecting`, `paused` (D3), `error` and `ended`. The screen, the notification and the captions read only this
state, never the engine.

**Chained** (Iris runs the loop, like Hermes Desktop and Conduit):
- *Listening.* Iris streams 16 kHz mono PCM from the mic (`record`'s stream mode, echo cancellation on) and computes RMS
  in the server's units. Speech starts when RMS crosses `voice.silence_threshold`; the take ends after
  `voice.silence_duration` below it, or at `voice.max_recording_seconds`. Push to talk (B2b) skips detection: the take is
  what is held. Takes under 400 ms are ignored.
- *Transcribing.* With `stt.streaming`, the take also streams to `transcribe-stream` for partials; its `final` is the
  transcript, and an `error` falls back to POST with the same audio. Otherwise POST. An empty transcript means silence:
  back to listening, no turn. A transcript that is exactly a stop phrase (case and punctuation ignored) ends the call.
  A transcript that matches what Iris just said is its own echo and is dropped (Desktop's `isTtsEcho` rule).
- *Turn.* `prompt.submit {text, voice_turn: true}` on the open session, `interrupted: true` after a barge-in.
  `voice_turn` lets the server route the turn to its `auxiliary.voice_chat` model; by default that is the session's own
  model, so this only changes anything on servers whose owner chose a faster voice model. If the server rejects the
  unknown fields (an older Hermes), Iris resubmits without them once and remembers that for the server. The mic
  closes; the orb is thinking, or tool while a tool runs (B5, with the tool pill and the trail).
- *Speaking.* A `speak-stream` socket opens with the turn and is fed `message.delta` text as it arrives, then `done` on
  `message.complete`. PCM plays as it arrives at the `start` frame's rate; the orb's level is the playback RMS.
  `fallback` switches to one-shot `POST /api/audio/speak` for the whole reply. Thinking and reasoning text is never
  spoken.
- *Barge-in* (when `voice.barge_in`). While speaking, the mic stays open with echo cancellation. The floor is measured in
  the 300 ms before playback; after `barge_in_grace_seconds`, RMS above floor × `barge_in_threshold_multiplier` for
  200 ms trips it: playback stops (B7's 120 ms cut), `{"stop": true}` goes to the socket, `session.interrupt` is sent if
  the turn is still running, and the take that tripped it becomes the next turn with `interrupted: true`.
- *Thinking sound* (when `voice.thinking_sound`): a quiet loop while thinking or running a tool, so a pocketed call is
  audibly alive. It is generated in code as PCM (no audio asset) and stops the moment speech starts.

**GPT-Live:**
- `flutter_webrtc` peer connection with the mic track and a remote audio track; the SDP offer goes to
  `POST /api/audio/voice-live/session` with `history` built from the chat's last 10 turns as
  `{type: "message", role, content: [{type: "input_text" | "output_text", text}]}` (Hermes Desktop's shape), and the
  answer is applied byte-exact. Listening, speaking and interruption belong to the model.
- `session.delegation.created` becomes `prompt.submit {text, surface: "voice-live", voice_context}` on the open session,
  where `text` and `voice_context` come from the transcript window (last 5 minutes, newest last). While the turn runs the
  orb is thinking or tool. Each finished `message.complete` is sent back as `session.commentary.append` in chunks cut on
  sentence ends.
- Orb modes come from the data channel: input transcript deltas → hearing, the remote track's audio level → speaking.
  Levels for the orb come from WebRTC audio-level stats.
- Mute sends `session.input_audio.mute`; End sends `session.close` and closes the peer.

### Approvals and questions mid-call (B9a, B9b)

`approval.request` and clarify requests arrive on the dashboard socket as today. The orb goes to needs and the card
appears in the voice screen; tapping always works and answers through the existing `approval.respond` /
`clarify.respond`.
- *Chained:* Iris speaks the prompt through `speak-stream` ("Shall I run git push origin main?"), then listens for one
  take. "approve", "yes", "go ahead" approve; "deny", "no", "stop" deny; for a question, the take is matched to a choice
  by its text, else sent as the free answer. Anything unclear asks once more, then waits for a tap.
- *GPT-Live:* Iris appends the prompt as `session.commentary.append` so the voice asks it, and matches the next input
  transcript the same way.

### Background, interruptions and reconnects

- **Locked screen.** Android runs the call in a microphone-type foreground service with the D1 notification (state text,
  Mute/Unmute, End). iOS uses the `audio` background mode; the system shows its own mic indicator (no Live Activity).
- **Audio session.** Play-and-record with voice processing; Bluetooth headsets allowed. The route control (B5, B8)
  cycles Speaker and Earpiece, shows the headset's name when one is connected, and opens the system picker where the
  platform has one.
- **Phone call or Siri/Assistant takes the mic (D3a).** The call pauses: the in-flight turn keeps running on the server,
  playback stops, and the reply is not spoken. Resume returns to listening; a reply that finished while paused is
  spoken then.
- **Headphones unplugged (D3b).** Playback pauses at once; Resume on speaker, or plugging back in, continues.
- **The dashboard link drops (B10a).** The existing reconnect runs and the call shows reconnecting; nothing is listened
  to meanwhile. On reconnect the session is resumed (Phase 2's rule) and the call returns to its state. After 30 s
  without a link, B10b. A speak-stream that drops mid-reply finishes the rest with one-shot speak.
- **Failed transcription.** The take is kept and retried once. A second failure shows "Didn't send that. Try again?"
  with the take still held; Try again resends it. A spoken turn is never dropped silently.

### Captions and the transcript (C1, C2)

- Captions are a layer over the call (C1). Your words: chained shows the final transcript, or partials with
  `stt.streaming`; GPT-Live shows the input transcript. Iris's words: chained shows the reply sentence by sentence,
  in ink once its audio starts and muted before; GPT-Live shows the output transcript.
- The voice turns are ordinary turns in the chat. On ending, the chat shows them after a mono "voice · N min" divider and
  a "call ended m:ss" note (C2). These come from call spans stored on the device (`voice_calls` table: session id,
  started, ended, first and last message ids).

### Data layer

New under `lib/data/voice/`, each returning `Result`, with profile scoping as `ChatBackend` does.

| Part | Responsibility |
|---|---|
| `VoiceRepository` | Config and live-status reads → `VoiceCapabilities`; transcribe; one-shot speak; leases; ElevenLabs voices; GPT-Live session; the voice write (`GET ?include_defaults=false`, change one key, `PUT`) |
| `SpeakStream` | One reply's speak-stream socket: send deltas/done/stop, expose `start`, PCM chunks, `end`, `fallback` |
| `TranscribeStream` | The live STT socket, when `stt.streaming` |
| `AudioSockets` | Mints a ticket per socket and adds the Access headers (shared with `DashboardSession`'s dialling) |
| `VoiceSettings` | Device prefs: conversation default, speaker by default, captions by default |
| `voice_calls` | Drift table for call spans (a schema version bump with a migration test) |

The voice write changes exactly one key: `tts.<provider>.voice` (or `voice_id` for ElevenLabs, xAI, Mistral, MiniMax),
or `voice.gpt_live.voice`. If the read, the `PUT` or the read-back fails, the picker keeps the old voice and says why.

Audio playback of streamed PCM and the audio session need new dependencies; the plan picks them after checking current
versions (candidates: `audio_session`, `flutter_pcm_sound` or `flutter_sound` for PCM playback, `flutter_webrtc`, and a
foreground-service package for Android). `record` 6.2.1's stream mode covers capture.

### Behaviour by frame

**Orb (O1, O2).** `IrisVoiceOrb` is a new `CustomPainter` port of `design/iris-voice.js`: the same modes, colours (dark
and light), level drive with 60 ms attack and 280 ms release, the hearing-inward / speaking-outward ripple rule, and the
interrupted squash. Under reduced motion it draws O2: static outlines by level band, a 400 ms band cross-fade, and an
opacity pulse every 3.6 s. It runs one ticker, only while visible. The existing `IrisOrb` is unchanged.

**Dictation (A1a, A1b, A1b·320, A1b·RM).** The recording strip is replaced by a 46 pt `IrisVoiceOrb` in the composer:
listening below the threshold, hearing above, driven by `VoiceRecorder.level`. Elapsed time is mono with "/ 2:00" taken
from the server's cap. Cancel and Send keep 44 pt targets. At 320 pt the orb keeps its size and the timer shrinks.

**Voice entry (A2, A2b, A4).** A filled accent circle with a waveform glyph sits where Send is when the field is empty;
once there is text it becomes Send. The mic never moves. Voice mode starts only from a chat's composer, on that chat
(a new chat starts one); the home Ask bar is unchanged. First-run tags "Tap to dictate" / "Talk hands-free" show once
per install. With no voice mode the button is absent and the field takes the space.

**Permission (A3a, A3b).** The primer shows before the first OS prompt from either the mic or the voice button. After a
refusal, the denied sheet opens the app's system settings. Android 13+ also asks for notifications on the first call;
refusing it does not stop the call.

**Voice screen (B1–B10b).** A full-screen route over the chat. Header: "VOICE · {server label}" and the call clock in
mono, the Hands-free / Push to talk chip (from Settings; tapping it switches for this call). The status line and helper
copy are the design's per state. Fixed controls: Mute, Captions, Route, End. B5's tool pill shows the running tool's name
and first argument; finished tools trail beneath in muted mono. At 320 pt the orb is 168 pt (B3·320, B6·320). The screen
keeps the display awake while visible.

**Push to talk (B2b).** The orb rests in idle; holding the button records, releasing sends. The chip switches modes for
this call only.

**Ending.** End, the stop phrase, or the notification's End close sockets and the peer, stop the foreground service, write
the call span, and return to the chat at its newest turn (C2).

**Settings (E1a, E1b).** Settings gains a Voice section when voice mode is available on the current profile:
Conversation (Hands-free | Push to talk), Speaker by default, Captions by default, and the Voice row with "Offered by
{server}" when a list exists. The Voice sheet lists voices by display name; choosing one writes the server's voice and
plays nothing. E1b's footnote shows when there is no list. Server-dependent rows are omitted, never disabled.

### UI

| Frame | Component |
|---|---|
| O1, O2 | `IrisVoiceOrb` (painter + modes), `lib/design/components/iris_voice_orb.dart` |
| A1a–A1b | the composer's recording row (`composer.dart`), `_RecordingStrip` removed |
| A2, A2b, A4 | `_VoiceButton` in the composer, first-run tags |
| A3a, A3b | `MicPermissionSheet` |
| B1–B10b, B2b | `VoiceCallScreen`, `VoiceStatusLine`, `VoiceControls`, `ToolTrail`, `VoiceDecisionCard` |
| C1 | `CaptionsLayer` |
| C2 | `VoiceCallDivider` in the transcript |
| D1 | the Android foreground service and its notification |
| D3a, D3b | the paused variant of `VoiceCallScreen` |
| E1a, E1b | `VoiceSettingsSection`, `VoicePickerSheet` |

New code lives under `lib/features/voice/` (screen, call state machine, engines) and `lib/data/voice/`.
`chat_screen.dart` only gains the route push and the call-span divider.

- Every colour is a palette role, an `AgentState` colour, or a voice-orb mode colour defined once in the palette; no
  widget holds a design hex value. Contrast tests are never loosened.
- Light variants for every frame. Reduced motion has an alternative for every animation; under `disableAnimations` the
  orb uses O2 and no continuous ticker runs.
- 44 pt targets (56 pt for the call controls), and no overflow at 320 pt wide or 200% text on every new surface.

## Design and wire differences

| The design shows | Iris does |
|---|---|
| B1 "Connecting to hermes.local…" | The subtitle names the preflight step ("Checking speech-to-text…") |
| B4 elapsed timer | Counts from `prompt.submit`, shown after 10 s (O1's note) |
| B5 route "AIRPODS" | The connected headset's name from the audio session, else Speaker or Earpiece |
| B9a "Say approve or deny" | Also accepts yes/no/go ahead (above). Tapping always works |
| C1 "spoken words are ink" | Sentence by sentence for chained; transcript deltas for GPT-Live |
| C2 divider after reload | Only on the device that made the call (call spans are local) |
| D1 "Working on it · 2:07" | The notification text follows the call state; the orb icon is static, as the frame says |
| D2 Live Activity | Not built (Phase 9) |
| E1a "Voice · Wren" | The provider's display name for the voice id; an unknown id shows verbatim |

## Platform and release

- **Android:** `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, `MODIFY_AUDIO_SETTINGS`,
  `BLUETOOTH_CONNECT` (headset routing; requested only when a headset is present), `WAKE_LOCK`. A foreground service of
  type `microphone`. `RECORD_AUDIO` exists from Phase 5.
- **iOS:** `UIBackgroundModes: audio`; the microphone string widens to "…to dictate and to talk with Iris"; WebRTC needs
  no extra key. No Live Activity.
- **Privacy policy and `docs/release.md`:** chained audio goes only to the user's Hermes server, which may forward it to
  the speech providers it is configured with. A GPT-Live call sends audio directly between the phone and OpenAI (the
  server only sets the call up), and the policy must say so. The Play data-safety form and App Store privacy labels gain
  "audio, not stored by Iris".
- CHANGELOG and README get voice mode.

## Testing

- **Task 0, extending the probe** (read-only except throwaway synthesis): record `include_defaults=false` support on
  `GET /api/config`; whether `prompt.submit` accepts `voice_turn` and `interrupted` (sent on a throwaway session with a
  one-word prompt); whether `stt-lease`/`tts-lease` exist; a 300 ms silent WAV through transcribe (expect `ok, ""`);
  a speak-stream round trip with "Ready." (record the `start` rate and frame sizes); and whether `transcribe-stream`
  answers `error` with streaming off. Results go in the plan.
- **Unit tests:** capability parsing for every row of the table above, including 404s and old servers; the RMS end-of-
  speech detector and barge-in trip against recorded level sequences; stop-phrase and echo matching; spoken
  approve/deny and choice matching; speak-stream framing (start/PCM/end/fallback/stop) with a fake socket; the
  transcribe retry that keeps the take; the commentary chunker; the one-key voice write (only that key changes, failure
  keeps the old voice); call spans.
- **Call state machine:** every transition driven by fake engines, including barge-in, reconnect, phone-call pause,
  unplug, preflight failures by part, and mute.
- **Widget tests:** `IrisVoiceOrb` modes and O2 under `disableAnimations`; the composer orb (A1a/A1b, 320 pt, reduced
  motion); the voice button's presence and absence; the permission sheets; each voice screen state; captions; the
  divider; Settings with and without a voice list; 320 pt and 200% text on every new surface.
- **Goldens:** the O1 state sheet, B3 and B6 (the two states that must never be confused), B9a, C1 and E1a, each dark
  and light, plus B3·RM and B6·RM. Existing goldens change only where the composer strip goes; each change is looked at.
- **Live tests:** the preflight against the real server; one chained turn end to end without a microphone: synthesise
  "Reply with exactly the word pong" with one-shot speak, transcribe that audio, submit it as a voice turn, and
  speak-stream the reply, waiting at least 240 s (Hermes is slow). The voice write is tested by writing the server's
  current voice back to itself and reading it back.
- **Demo backend:** a scripted call through B1–B9b and C1 with simulated levels.
- **Device pass:** one pass on the Pixel 9 emulator (release APK) and one on a physical Android phone, since emulators
  have no real mic routing. The user connects the phone when the pass is reached; the plan stops there and asks.
  iOS is built and unit-tested only (no Mac in this setup). Recorded in `docs/superpowers/plans/2026-10-19-phase8-device.md`: dictation, a hands-free
  call, push to talk, barge-in, an approval by voice, captions, locked screen with the notification, a phone-call pause,
  headphones unplugged, the voice picker, light and dark, 320 pt and reduced motion. GPT-Live is covered by switching the
  server's `voice_chat_mode` to `gpt-live` for the pass and back afterwards.

## Execution split

The plan will carry the final task list. A task that fails its tests on the first model is retried on the next one up.

| Task | Model |
|---|---|
| 0 Extend the probe | haiku |
| 1 `VoiceRepository`, `VoiceCapabilities`, `AudioSockets` | sonnet |
| 2 `IrisVoiceOrb` painter and O2 | sonnet |
| 3 Composer: orb replaces the strip, voice button, permission sheets | sonnet |
| 4 Audio session, PCM capture with RMS, PCM playback | opus |
| 5 `SpeakStream`, `TranscribeStream`, one-shot fallbacks | sonnet |
| 6 Call state machine and the chained engine, including barge-in | opus |
| 7 Preflight | sonnet |
| 8 Voice screen B1–B10b, push to talk, tool trail | sonnet |
| 9 Approvals and questions by voice | sonnet |
| 10 GPT-Live engine (WebRTC, data channel, delegation) | opus |
| 11 Captions, call spans, the divider | sonnet |
| 12 Android foreground service, notification, iOS background audio, interruptions | opus |
| 13 Voice settings and the voice picker with the one-key write | sonnet |
| 14 Demo scripted call | haiku |
| 15 Goldens, analyze, privacy policy, release notes, CHANGELOG, README | haiku |
| 16 Live tests | sonnet |
| 17 Device pass | sonnet |
| 18 Final review of the whole diff | opus |

Opus is for the audio plumbing, the barge-in state machine, the WebRTC engine and the background service, where timing
bugs hide, and for the final review.

## Out of scope

- Gemini Live, the iOS Live Activity and Dynamic Island, CarPlay, Siri/App Intents and Android shortcuts, the wake word
  (Phase 9).
- Client-direct voice (provider keys on the phone).
- Choosing the STT or TTS provider, or editing any voice tuning, from Iris. Only the voice itself is written.
- Voice for scheduled jobs, voice memos as attachments, and reading old messages aloud.
- Push, offline cache, paging past 120 rows, native PKCE OAuth, usage alerts, widgets, localisation (Phase 9).
