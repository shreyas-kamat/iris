# Phase 5 — maths, richer Markdown, media and input

Phase 5 of the Conduit-parity roadmap. Phases 1–4 are merged. This phase makes replies read properly when they hold
maths or GitHub-style Markdown, and lets the person send more than typed text: files, photos and speech.

## Goals

1. **Maths.** TeX in a reply renders as typeset maths: inline `$…$` and `\(…\)`, display `$$…$$`, `\[…\]` and
   ` ```math ` fences.
   This covers algebra (systems, matrices, determinants, `cases`, AMS `align`/`gather`/`multline`/`alignat`/`split`,
   `\tag`), calculus (limits, derivatives, partials, every integral form, series) and deeper physics (vector calculus,
   tensors, bra-ket). It also covers the `physics` package (`\dv`, `\pdv`, `\abs`, `\norm`, `\expval`, `\comm`…),
   `siunitx` units (`\SI`, `\si`, `\unit`, `\qty`) and `mhchem` chemistry (`\ce`). Commands the layout engine lacks
   are supplied as macros and a small rewrite pass. A 93-expression corpus is the regression test.
2. **Richer Markdown.** GitHub alerts (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`), footnotes,
   emoji shortcodes (`:tada:`), table column alignment, and the inline HTML tags agents use for typography: `<sub>`,
   `<sup>`, `<kbd>`, `<mark>`, `<br>`.
3. **Images in Markdown.** `![alt](https://…)` shows as an image, loaded only when tapped.
4. **Code language detection.** An unlabelled fence in a finished reply is coloured when one language is a clear
   match.
5. **Attachments.** Photos and files from the device go with a prompt, the way Hermes Desktop and Conduit send them.
6. **Dictation.** The mic records a clip, Hermes transcribes it, and the words land in the composer to edit and send.

## Decisions (chosen for the lowest build cost)

- **Keep the custom renderer.** `IrisMarkdown` already draws every node from design tokens. New syntax is added as
  `package:markdown` syntaxes plus a renderer case. Swapping to a third-party Markdown widget would mean restyling it
  from scratch.
- **Maths uses `flutter_math_fork` 0.7.4,** a pure-Dart TeX layout engine with KaTeX fonts bundled. There is no WebView
  and no CDN. TeX that does not parse, including half-written TeX while a reply streams, shows as its source in code
  type.
- **`package:markdown`'s `gitHubWeb` set replaces `gitHubFlavored`.** It already parses alerts, footnotes and emoji.
  This phase only draws them.
- **Currency is not maths.** Inline `$` follows Pandoc's rule: the opening `$` is not followed by a space, the closing
  `$` is not preceded by one and not followed by a digit. "`$5 and $10`" stays text.
- **Markdown images are tap-to-load.** Iris otherwise talks only to the user's own server. An image on a third-party
  host is fetched only when the person asks for it. No setting.
- **Attachments use `file_picker` only.** It covers the photo library and files with one dependency and no camera
  permission. Camera capture is out of scope.
- **The attachment protocol is Conduit's.** Images go through `image.attach_bytes {session_id, content_base64,
  filename}`. If Hermes refuses an image as an image (RPC error 4016 or 4018), it goes up as a file. Other files go
  through `file.attach {session_id, data_url, name, path: ""}`, whose reply gives an `@file:` reference (`ref_text`, or
  one built from `ref_path`/`path`). The prompt is the references, one per line, then a blank line, then the typed
  text. The bubble keeps the typed text and shows the files as chips.
- **Dictation, not voice mode.** Iris records 16 kHz mono WAV with `record` 6.x, for at most 2 minutes. It POSTs
  `/api/audio/transcribe {data_url, mime_type: "audio/wav"}` (profile-scoped) and reads `transcript` (or `text`). An
  `error` field is a failure, and an empty transcript means "didn't catch that". Live voice mode (the speak-stream
  WebSocket, PCM playback, barge-in) moves to Phase 8 with the other native audio work.
- **Limits:** at most 5 attachments per message and 20 MB per file. Larger files are refused before upload with a
  toast.

## Behaviour

- Display maths is centred and scrolls sideways when wider than the bubble. Inline maths sits on the text baseline at
  body size.
- Alerts draw as a quote with a coloured left rule, an icon and the title (Note, Tip, Important, Warning, Caution),
  using the state colours: note `idle` (accent), tip `done`, important `thinking`, warning `working`, caution `failed`.
- Footnote references are superscript numbers. The footnotes block sits at the end under a hairline, smaller and
  muted, with the ↩ back-links dropped.
- A paragraph holding only an image shows a placeholder card ("Image · host · Tap to load"). A tap loads it, at most
  320 px tall with rounded corners. A failed load shows the alt text. An image inside running text stays as its alt
  text.
- Language detection runs only on finished replies, for blocks of 20–20 000 characters. It picks from a fixed set of
  14 common languages and needs relevance ≥ 6 with a clear lead over the runner-up. The header shows the detected name.
- The composer's leading "+" opens the picker. Chosen files show as removable chips above the field. While the field
  is empty and no turn is running, the trailing button is a mic. Recording shows elapsed time with Stop and Cancel.
  The transcript is appended to whatever is already typed.
- Stored transcripts keep `@file:` references in the user's text. They are lifted back out into chips when shown.
- The demo backend accepts attachments without uploading anything, and its "transcription" returns a canned phrase.

## Platform changes

- Android: `RECORD_AUDIO` permission.
- iOS: `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription`.
- Privacy policy: files and recordings go only to the user's own server; tapped Markdown images are fetched from
  their host.

## Testing

Unit tests for the syntaxes, reference handling, detection and the backend calls (fake socket and fake HTTP). Widget
tests for rendering, the composer and the screen flow, using a fake recorder and a fake picker. One live test against
the real server checks `file.attach` and `/api/audio/transcribe`. Then one device pass on the Pixel 9 emulator. There
are no new goldens: the device pass's screenshots stand in for them.

## Out of scope

- Live voice mode, text-to-speech, CarPlay-style calls (Phase 8).
- Camera capture, drag-and-drop, pasting images from the clipboard.
- Mermaid and other diagram fences (they stay code blocks).
- Equation numbering and cross-references: `\label` is dropped, `\tag{n}` shows "(n)", and `\eqref` isn't resolved.
- Full `mhchem` (isotopes, bonds, reaction-arrow labels) and auto-sized `physics` `\qty` brackets: the common forms
  are covered, and the rest draws as plain upright text.
- Plotting graphs of functions.
- Loading images that need the dashboard's session cookie, or `MEDIA:` paths on the server.
- A setting to load Markdown images automatically.
