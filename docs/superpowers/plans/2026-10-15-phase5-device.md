# Phase 5 device pass

Release APK (`com.iflotech.iris`, built from `feat/phase5-maths`) on the Pixel 9 emulator, cold-booted, signed in to
the real server (Hermes, model `gpt-6.1-sol`). Screenshots are in `2026-10-15-phase5-device/`.

## Live check (`test/live/phase5_live_test.dart`)

- `file.attach` stages a file and returns an `@file:` reference: **passes**.
- `/api/audio/transcribe` answers (one second of silence gave an empty string): **passes**, so speech-to-text is
  configured on this server.

## Checks

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 0 | Composer: attach button and mic when empty | Pass | `00-composer-empty.png` |
| 1 | Quadratic formula, Euler, Maxwell, Schrödinger (physics), Taylor, `\ce` render as maths, light and dark | Pass, with one defect (below) | `01-maths-light-*.png`, `01-maths-dark.png` |
| 1b | `align*` 3×3 system | Not rendered: the agent put it in a `latex` code block (it was showing source). Unit tests cover the `align*` rewrite | `01-maths-light-end.png` |
| 2 | Table with centred and right-aligned columns, GitHub warning alert, footnote | Pass | `02-table-alert-footnote.png` |
| 3 | Markdown image: placeholder, tap loads it | Pass | `02-…png` (placeholder), `03-image-loaded.png` |
| 4 | Unlabelled code block coloured | Inconclusive: the agent labelled the block `python` itself, twice, so detection was never exercised. Covered by unit tests | `04-unlabelled-code.png` |
| 5 | Attach a photo and a PDF | Pass: both chips in the composer and in the sent bubble; the agent described the image and read the PDF's text | `05-attach-chips.png`, `06b-attach-bubble.png`, `06-attach-reply.png` |
| 6 | Dictation | Partly: recording strip, timer, upload and transcription round trip all ran; the emulator's virtual mic heard silence, so the toast "Didn't catch that" showed. Words landing in the composer is covered by the screen test only | `08-recording.png`, `09-dictation-no-speech-toast.png` |
| 7 | Mic denied | Pass: toast "Iris needs the microphone. Allow it in Settings to dictate." | `07-mic-denied-toast.png` |
| 8 | Demo mode, attaching and dictating | Not run: entering the demo would sign the emulator out of the real server | none |

## Findings

1. **Fixed: `\pdv{t}` with one argument.** The Schrödinger equation drew `∂t / ∂|⟩` because the macro took the next
   token as a second argument. physics reads a lone `\pdv{t}` as ∂/∂t. `prepareTex` now rewrites a one-group `\pdv` or
   `\dv` as an operator; two groups stay a fraction (test added, red then green). Not yet re-checked on a device.
2. **Open: a loaded image goes back to its placeholder** once a later message arrives and the list rebuilds
   (`02-…` and `04-…` show the placeholder again after the tap in `03-…`). Tap to load works, but the loaded state
   isn't kept.
3. The composer shows a small spinner beside the model chip after a turn finishes. It was there in every screenshot; I haven't checked whether
   it predates this phase. Worth a look.
