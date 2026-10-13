# Iris design: implementation plan

**Date:** 2026-10-14. **Branch:** `feat/iris-design`, cut from `main` at `30660c6`.
**Source:** the claude.ai/design project "Iris App". It is checked in as `design/Iris App.dc.html` (markup and
behaviour) and `design/iris.js` (the orb renderer). Both files are the reference for this plan. Open the HTML for
exact sizes, radii and colours. Its `<script data-dc-script>` block (line 330 onward) holds the state labels and
the interaction logic.

## Decisions (made by the user, 2026-10-14)

1. **Build only what has real data.** This covers home with the conversation list, chat, and a Settings screen
   whose rows all work. The design's **Scheduled** and **Tasks** tabs, the **mic button**, **voice mode**, the
   composer's **"+" attachment button** and the chat header's **"⋯" button** are **not built**. Each one waits for
   the phase that adds its backend. Don't add placeholders or "coming soon" text for them.
2. **The design becomes the Aperture skin in dark mode.** Its exact hex values become `IrisSkin.aperture`'s dark
   palette. The other nine skins and light mode keep working. Every widget reads palette **roles**. No widget
   holds a design hex value.
3. **The "iris orb" replaces the Aperture mark everywhere.** Port `design/iris.js` to a Flutter `CustomPainter`.
   Delete `lib/design/components/aperture.dart`.

## Ground rules for the implementer

- Invoke the `flutter` skill before starting, and follow its verification loop.
- Match the surrounding code. That means library doc comments, comments that explain *why*, `context.palette`,
  `context.type` and `context.iris`, `IrisSpace` / `IrisRadius` tokens, and `IrisPressable` for taps.
- After **every** task, run `flutter analyze` (expect 0 issues) and `flutter test` (all green; live tests skip
  themselves). Then commit with a conventional message such as `feat(design): …`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't push.
- Never weaken a test to make it pass. If a widget test's *selector* no longer fits, change the selector so it
  still checks the same behaviour. Examples: `find.text('Send')` becomes `find.bySemanticsLabel('Send')`, and a
  header model label moves to the composer chip. Contrast tests are never loosened. Adjust the colour instead.
- Tests run with `disableAnimations: true` (`test/support/harness.dart`). Under reduced motion the orb must paint
  one static frame and run **no ticker**. Otherwise `pumpAndSettle` hangs.

---

## Task 1: Instrument Serif and the serif type role

1. Download these into `assets/fonts/` and check that each one is a real TTF (`file` or the first bytes), not an
   HTML error page:
   - `https://github.com/google/fonts/raw/main/ofl/instrumentserif/InstrumentSerif-Regular.ttf`
   - `https://github.com/google/fonts/raw/main/ofl/instrumentserif/InstrumentSerif-Italic.ttf`
   - `https://github.com/google/fonts/raw/main/ofl/instrumentserif/OFL.txt`, saved as
     `assets/fonts/INSTRUMENT-SERIF-OFL.txt`
2. In `pubspec.yaml`, add a family `InstrumentSerif` with both files (the italic one with `style: italic`). Add the
   OFL file to `assets`. Extend the existing fonts comment to cover it.
3. In `lib/design/tokens/typography.dart`:
   - Add `IrisFonts.serif = 'InstrumentSerif'` with the fallback `['Georgia', 'serif']`.
   - Add one role, `serif`: italic, weight 400, size 32, height 1.05, tracking -0.3. This is the design's voice
     for greetings and screen titles ("Good evening.", "Settings" at 38 via `copyWith`, "What should we work on?"
     at 30). Add it to `all`. Add a doc comment saying it is the only place the serif appears.
4. Make `loadIrisFonts()` in `test/design/gallery_golden_test.dart` load `InstrumentSerif` too.

## Task 2: Palette, with the design's colours and the new states

In `lib/design/tokens/palette.dart`:

1. **Extend `AgentState`** with `loading` ("connecting / reaching the gateway"), `offline` ("gateway
   unreachable") and `rest` ("a finished conversation at rest"). Keep the existing names. `working` is the design's
   `tool`, and `done` is the design's `success`. `waiting` (an approval gate) has no design counterpart, so it keeps
   its role. Fix every exhaustive `switch` the compiler flags.
2. **Add `String get label` on `AgentState`** (an extension or an enum getter). It holds the design's `META` words:
   idle "Ready", thinking "Thinking", streaming "Writing", working "Using tools", waiting "Needs you", done "Done",
   failed "Failed", loading "Connecting", offline "Offline", rest "Done".
3. **State colours.** In **every dark skin**, `colorFor` returns the design's hex values exactly:
   thinking `#9B7BFF`, loading `#5CC8FF`, working `#FFB547`, streaming `#4FE3C1`, done `#6EE787`,
   failed `#FF6B6B`, offline `#6B6A78`, rest `#8E89AE`, and waiting `#FF8A5C` (a new value, hot coral).
   `idle` stays `accent`, so each skin still looks like itself at rest. In **light** skins, use darker versions of
   the same hues that pass the contrast tests. Start from thinking `#6A4BE0`, loading `#0A7FB8`,
   working `#A86200`, streaming `#0B8A70`, done `#1F8A3B`, failed `#D23A3A`, offline `#74737F`, rest `#6F6A90`,
   waiting `#C2501C`. Adjust the light values until `test/design/contrast_test.dart` passes. Keep `hueFor` working:
   it is used by `quietFor`. Derive the hue from the colour, or keep a hue table that matches these colours.
4. **Aperture dark becomes the design palette.** `IrisSkin.aperture.palette(isDark: true)` returns a hand-specified
   `IrisPalette`, not `IrisPalette.derive`, with these values:
   canvas `#0B0B10`, surface `#13131A`, surfaceRaised `#17161F`, surfaceSunken `#07070A`, scrim `#A6050508`,
   ink `#ECEBF2`, inkMuted `#A9A7B8`, inkFaint `#6E6C7E`, inkInverse `#14121F`, line `#1E1E27`,
   lineStrong `#34333F`, accent `#C9C3FF`, accentInk `#14121F`, accentQuiet `#25223A`, accentHue 296,
   neutralHue 292, chroma 0.165.
   Add a comment saying these values come from the design file and why they are fixed rather than derived. If a
   contrast assertion fails, nudge that one role (for example lift `inkFaint` toward `#7A7889`) and note it in the
   comment.
5. `flutter test test/design/contrast_test.dart` must pass for all 20 palettes.

## Task 3: `IrisOrb`, ported from `design/iris.js`

Create `lib/design/components/iris_orb.dart`. Its public API is
`IrisOrb({required AgentState state, double size = IrisSize.orb, bool glow = true, String? semanticLabel})`.
Rename `IrisSize.aperture` (26) to `IrisSize.orb` and `apertureSmall` to `orbSmall`, and update every user.

**Port the renderer exactly.** Read `design/iris.js` line by line.

- Build a parameter table per state. Use `iris.js`'s `S` table, mapping its keys as follows: idle→idle,
  rest→rest, thinking→thinking, loading→loading, tool→working, streaming→streaming, success→done,
  failed→failed, offline→offline. `waiting` is new:
  `dot .15, pulse .28, pf 2.2, ring .37, w .045, arc 1, seg 0, spin .4, wob 0, glow .9, sat 0, track 0, alpha 1`.
  The colour always comes from `context.palette.colorFor(state)`, never from the table, so skins and light mode
  work.
- **Animate with a `Ticker`.** Each frame: `dt = min(.05, elapsed)`, `t += dt`, and every numeric parameter
  approaches its target by `k = min(1, dt*5)`. The colour lerps the same way. `seg` snaps. `rot += spin*dt`.
  `shake` and `burst` decay at 1.6/s and 1.1/s. A change to `failed` sets `shake = 1`, and a change to `done` sets
  `burst = 1` (in `didUpdateWidget`).
- **Paint in this order:**
  1. glow: a radial gradient filling the box, alpha `.32*glow` / `.12*glow` / 0 at stops 0 / .45 / 1, only when
     `glow` is on
  2. track ring: a full circle at `track` alpha
  3. the ring:
     - with segments: `n` arcs, each `slot*min(.92,arc)` long
     - with `arc > .985`: a full ring
     - otherwise one partial arc whose tail fades (alpha `.12 + .88*f^1.6` per sub-segment, about `len*40`
       sub-segments). A failed ring is centred at the bottom and doesn't fade, as in `iris.js`.
     The radius wobbles by `amp*sin(a*5+t*3.2)*sin(a*3-t*2.1)`. The stroke has round caps and width
     `max(1, size*w)`. When glow is on, draw a blurred copy underneath (`MaskFilter.blur`, sigma about
     `size*.04*glow`, alpha `.8*glow`) in place of canvas `shadowBlur`.
  4. the satellite dot when `sat > .02`
  5. the success burst ring
  6. the centre dot: radius `size*dot*(1+pulse*sin(t*pf*2π))`, filled with a `RadialGradient` from white (`.95*alpha`)
     through the colour to the colour at `.85`, with its focal point offset (-.3D, -.35D)
  Multiply every alpha by the state's `alpha`. Apply the shake as a horizontal translate of
  `sin(t*55)*shake²*size*.045`.
- **Cost rules:**
  - Wrap the painter in a `RepaintBoundary`.
  - Under reduced motion (`context.reduceMotion`), paint the target state statically with `t = 0`, `rot = 0` and no
    shake or burst, and never start the ticker.
  - Stop the ticker once the state has settled (every parameter within 0.001 of its target, `shake` and `burst` at
    0) **and** the state has no motion (`spin == 0 && pulse == 0 && wob == 0`). In practice that is rest, done and
    failed, so a long list of rest orbs costs no frames. Restart it on a state change.
  - Seed the start values deterministically (for example from the widget's identity hash) rather than with
    `Random`, so goldens stay stable.
- **Semantics:** the same labels Aperture used, plus loading "Connecting", offline "Offline" and rest "Finished".
  `liveRegion` stays on for `waiting`.

Then:

- Replace every `Aperture(` with `IrisOrb(` across `lib/`, and delete `aperture.dart`.
- Remap `describeLink` in `lib/features/home/link_status_screen.dart`:
  - `idle`/`connecting` → `loading`
  - `live` → `done`
  - `retrying` → `offline`
  - `needsSignIn`/`blocked`/the rest → `failed`
- Update `lib/features/design_gallery/design_gallery.dart`. Replace the aperture section with an orb grid showing
  every `AgentState` with its `label` at sizes 40 and 20, plus one at 84. Add `serif` to the type specimen.
- Add a widget test, `test/design/iris_orb_test.dart`, that checks these four things:
  - every state renders at 12, 20, 40 and 150 under `themed()` without throwing
  - under `disableAnimations`, `tester.binding.hasScheduledFrame` is false after the first pump
  - without reduced motion, `rest` stops scheduling frames after about 2 s of pumping
  - the semantics labels are right
- Re-run the gallery goldens with `--update-goldens`, then **open the PNGs** and check that the orb looks like the
  design.

## Task 4: Shared components

1. **`IrisSwitch`** in `controls.dart`. It is the design's toggle: a 50×30 track with radius 999 and 3px padding,
   and a 24px white knob with a shadow `0 2 6 rgba(0,0,0,.35)` that slides 20px. The track is
   `colorFor(thinking)` when on and `palette.lineStrong` when off. The knob moves on a spring
   (`Cubic(.34,1.56,.64,1)` over 350ms). Pass `value` and `onChanged`, and use switch semantics (`toggled`).
2. **`IrisCircleButton`** in `controls.dart`. It is a 40px circle filled with `surfaceRaised` and bordered with
   `line`, holding a single icon (18px, `ink`). It scales to 0.92 on press via `IrisPressable` and requires a
   `semanticLabel`. It is used for back and settings.
3. **Settings rows**, in a new `lib/design/components/settings_list.dart`:
   - `IrisSettingsGroup(title, children)`: a mono uppercase label (`IrisLabel`, faint, 6px side padding) over a
     card with `surface` fill, radius 20, a `line` border and `clipBehavior`.
   - `IrisSettingsRow(label, {sub, value, trailing, onTap})`:
     - padding 13×16
     - a top hairline in `line` for every row but the first; the group passes `first`, or wraps the rows itself
     - the label at 14.5 sans `ink`, with `sub` at 12 `inkFaint` below it
     - `value` at mono 12 `inkMuted`
     - a 14px chevron in `lineStrong` only when `onTap != null`
     - `trailing` (for example an `IrisSwitch`) replaces the value and chevron
4. **`IrisPageRoute`** in `lib/design/platform/platform_feel.dart`. Replace both platform branches with the design's
   push, which runs the same on every platform:
   - the incoming page slides in from `Offset(1.05, 0)` with `Cubic(.32,.72,0,1)`, 500ms forward and 380ms reverse
   - it casts a left shadow, `BoxShadow(color: #80000000, blurRadius: 60, offset: Offset(-30, 0))`
   - the outgoing page drifts to `Offset(-0.28, 0)` via `secondaryAnimation`
   Return the child unchanged under reduced motion. Then change the `MaterialPageRoute` pushes in
   `conversation_list_screen.dart` (and any other screens) to `IrisPageRoute`.

## Task 5: Home (`lib/features/chat/conversation_list_screen.dart`)

Follow the design's `<!-- HOME -->` block. Keep the existing data flow (providers, paging, `_open`, `_loadMore`,
`_pickProfile`). Only the presentation changes.

- **Top bar** (padding 8×20; the scaffold header):
  - **On the left, a profile pill.** It is a radius-999 pill with `surfaceRaised` fill, a `line` border and
    padding 6/12/6/6. Inside: a 28px circle avatar in `accentQuiet` showing the profile's first letter
    (uppercased, 12 w600, `accent`), then a column with "Profile" (10, `inkMuted`) over the profile name (13 w500),
    then a 14px chevron-down in `inkMuted`. Show the chevron, and make the pill tappable (opening `_pickProfile`),
    only when there is more than one profile.
  - **On the right,** an `IrisCircleButton` with a tune/sliders icon (`Icons.tune`), semantic label "Settings". It
    pushes the new `SettingsScreen` (Task 6).
- **Hero** (padding 18/24/22, row with gap 16):
  - an `IrisOrb` at 84 whose state is `idle` when the link is live, otherwise the `describeLink` state
  - `type.serif` text with a time-of-day greeting: "Good morning." before 12, "Good afternoon." before 17,
    otherwise "Good evening."
  - "Iris is ‹label lowercased›", the label word coloured `colorFor(state)` (use `Text.rich`), followed by
    " · N conversations" when the first page's `total` is known (13.5, `inkMuted`)
  - a gateway line in mono 11 `inkFaint`: a 6px dot coloured `colorFor(linkState)`, then
    "‹server host› · ‹link headline›". Take the host from `Uri.parse(server.baseUrl).host`. Tapping the line pushes
    `LinkStatusScreen`.
- **List:**
  - An `IrisLabel` "Recent" (faint, padding 0/4/6).
  - Then the conversation rows, matching the design's "Earlier" rows: padding 10/12/10/10, radius 18, no fill
    (pressed or hovered: `surface`). Each row has:
    - a 44px tile, radius 14, `surfaceSunken`, holding `IrisOrb(state: rest, size: 30, glow: false)`
    - the title at 14 sans in `ink` (one line, ellipsis)
    - the existing subtitle at mono 11 `inkFaint`
    - a 16px chevron in `lineStrong`
  - The gap between rows is 6. Side padding is 20 and bottom padding 130, so the last row clears the floating bar.
  - Keep the skeletons, the empty and error states, and "Show more".
- **Floating "new chat" bar** (design lines 149–158, without the mic):
  - Pin it to the bottom over a gradient from `canvas` (55%) to transparent, with padding 24/16/(16 + safe-area
    bottom).
  - The pill has radius 24, `surfaceRaised` fill, a `line` border and shadow `0 12 40 rgba(0,0,0,.5)`.
  - Inside is one full-width pressable row, 44 high: a 18px "+" icon in `accent`, then "Ask Iris anything…" at 15
    `inkMuted`.
  - Semantic label "New conversation". Disabled (opacity 0.5, no tap) under the same condition as today's button.
- Update `test/features/conversation_list_screen_test.dart` selectors for the new copy.

## Task 6: Settings (`lib/features/settings/settings_screen.dart`, new)

Follow the design's `<!-- SETTINGS -->` block, with only rows that work.

- The header is an `IrisCircleButton` (back, `Icons.arrow_back_ios_new`, semantic label "Back").
- The title is "Settings" in `type.serif.copyWith(fontSize: 38)`, with 4px side padding.
- **Connection card:** padding 16, radius 22, `surface` fill, `line` border. It holds an `IrisOrb` at 48 in the
  `describeLink` state, the link headline (15 w500) and, in mono 11.5 `inkFaint`, "‹host› · hermes ‹version›"
  (version from `activeCapabilitiesProvider`, when known). Tapping it pushes `LinkStatusScreen`.
- **Group "Agent":**
  - Profile: the value is the active profile; it opens the same picker as home when there is more than one
    profile, and `onTap` is null otherwise. Move `_pickProfile` into a shared function (for example
    `showProfilePicker(context, ref)` in `lib/features/chat/profile_picker.dart`) and use it from both screens.
  - Default model: the value is the active `AgentProfile.model`, and the row is not tappable.
- **Group "Appearance":**
  - Skin: the value is `skin.label`. It opens an `IrisSheet` listing `IrisSkin.values` as `IrisListRow`s and calls
    `themeController.setSkin`.
  - Brightness: the value is the mode label. It opens a sheet with System/Light/Dark and calls `setMode`.
  - Match browser skin: sub "Use the skin picked in Hermes's web UI", with an `IrisSwitch` as `trailing`, bound to
    `followServerSkin`.
- **Group "Server":**
  - Servers: the value is the server label, and it opens `showServerSwitcher`.
  - Connection details: pushes `LinkStatusScreen`.
- Lay it out as a scroll view with padding 4/20/40 and a gap of 22 between blocks.
- Add `test/features/settings_screen_test.dart`. Check that the rows render with real provider values (reuse the
  overrides in `test/features/conversation_list_screen_test.dart`), that Brightness → Dark calls the controller,
  and that the switch toggles `followServerSkin`.

## Task 7: Chat screen and transcript

Follow the design's `<!-- CHAT -->` block. The files are `chat_screen.dart` and `transcript_view.dart`, plus the
code-block part of `lib/design/components/markdown.dart`.

- **Header** (padding 8/14/12, bottom hairline in `line`):
  - an `IrisCircleButton` back
  - an `IrisOrb` at 34 in the turn's state
  - the title at 14 w500, one line
  - below the title, the state label (11.5 w500, coloured `colorFor(state)`, the colour animating over 400ms):
    `agentStateFor(turn).label`, or "Connecting" while the chat is loading
  The model **leaves the header** for the composer (Task 8).
- **Empty conversation** (`items.isEmpty` and ready), centred, with a gap of 18:
  - `IrisOrb(idle, 110)`
  - "What should we\nwork on?" in `type.serif.copyWith(fontSize: 30)`, centred
  - three suggestion rows: padding 13×16, radius 16, `surface` fill, `line` border, text at 14, with a 16px
    north-east arrow in `inkFaint`. The suggestions are "Summarize what happened overnight", "Draft a cron for a
    weekly audit" and "What can you do on this server?". Tapping one sends it through the same path as the
    composer. Disable them unless `phase == ready`.
- **Transcript spacing:** horizontal 18 and vertical 20 padding, with a gap of 22 between entries.
- **User bubble:**
  - `accentQuiet` fill, radius `20,20,6,20` (topLeft, topRight, bottomRight 6, bottomLeft 20, so the bottom-right
    corner is the small one)
  - padding 11×15, text at 15/1.45 in `ink`
  - `maxWidth` of 82% of the column, using a `LayoutBuilder` or `FractionallySizedBox`
- **Assistant turn** (`_AssistantBlock`), a column with a gap of 10:
  - **Header row:** an `IrisOrb` at 20, "Iris" (13 w500) and a mono 11 `inkFaint` meta. While streaming, the orb
    and meta follow the live turn state ("thinking", "writing"). Once finished, the orb is `rest` and there is no
    meta. Pass the live `TurnPhase` from `ChatScreen` to the last streaming turn's entry. Add an optional
    `AgentState? live` parameter to `TranscriptEntry`.
  - **Thoughts card** (when `reasoning` isn't empty):
    - a stateful card with radius 16, `surface` fill and a border of `colorFor(thinking)` at 14% alpha
    - its header button (padding 10×12, 12.5 w500, coloured `colorFor(thinking)` lightened, or just that colour)
      reads "Thinking…" while streaming with no text yet, otherwise "Thought process"
    - a 14px chevron rotates 180° when open
    - the body is `AnimatedSize` with italic 13/1.55 `inkMuted` and padding 0/12/12
    - it starts open while streaming with no text yet, and closes itself when text starts arriving unless the
      person toggled it. Afterwards it starts closed.
  - **Text:** the existing `IrisMarkdown` (body at 15/1.6). While streaming, put a blinking caret after the text:
    an 8×16 block, radius 2, `colorFor(streaming)`, 1s step blink, static under reduced motion. A caret on the line
    below the Markdown is acceptable. Delete the old "Thinking…" caption, because the thoughts card and the header
    meta replace it.
- **Tool card** (`ToolCard`). Keep the tap-to-expand behaviour and the 4000-character clip.
  - The card has padding 10×12, radius 14 and `surface` fill with a `line` border.
  - A 28px tile (radius 9, `surfaceRaised`) holds the status: `IrisOrb(working, 24)` while running, a 14px check
    in `colorFor(done)` when done, and a 14px ✕ in `colorFor(failed)` when failed.
  - Next to the tile, the name in mono 12.5 `ink` and the arguments in mono 11 `inkFaint` (one line collapsed,
    full when expanded).
  - The status text at 11 sits on the right: "running" in `colorFor(working)`, "done" in `inkFaint`, "failed" in
    `colorFor(failed)`.
  - When expanded, the output shows below in mono 11.5.
- **Error notice** (`Notice.isError`):
  - padding 12/12/12/14, radius 16
  - `colorFor(failed)` at 8% fill and a 22% border
  - the text at 13 w500 in `colorFor(failed)`
  - no Retry button, because the controller has no retry
  Plain notices stay as they are.
- **Code blocks** (`markdown.dart`, the `code()` builder). Turn the block into a stateful `_CodeBlock`:
  - radius 14, `surfaceSunken` fill, `line` border
  - a header row (padding 8×12, bottom hairline) with the language (taken from the `language-xxx` class, or
    "code") in mono 11 `inkFaint` on the left and, on the right, a "Copy" button: a 13px copy icon plus 11 w500
    `accent`. It calls `Clipboard.setData` and reads "Copied" for 1.4s; cancel the timer on dispose.
  - the body is mono 12.5/1.6 in `accent`, padding 12, scrolling horizontally
  Keep `test/design/markdown_test.dart` passing, and add a case for the copy label.
- Approval and clarify cards are unchanged apart from inheriting the new tokens.
- Update `test/features/chat_screen_test.dart` and `chat_widgets_test.dart` selectors to match.

## Task 8: Composer (`lib/features/chat/composer.dart`)

Follow design lines 256–277, with no "+" and no mic.

- **New parameters:** `String? model`, `VoidCallback? onModel` and `AgentState state` (used for the running
  border and the stop orb). `ChatScreen` passes `state.model`, the model-picker callback (which moves here from the
  header) and `agentStateFor(state.turn)`.
- **The outer box:**
  - padding 8/12/(12 + bottom inset; the scaffold may already handle the inset, so check `IrisScaffold`)
  - no top border and no `canvas` fill
  - the slash suggestions stay above the box, unchanged
- **The box itself:**
  - padding 10/8/8/14, radius 24, `surfaceRaised` fill
  - the border is `line`, or `colorFor(state)` at 33% alpha while running, animated over 400ms
    (`AnimatedContainer`)
  - it holds a borderless `TextField` (no `IrisField` chrome) with style 15/1.45 `ink`, hint "Message Iris…" in
    `inkFaint`, and `minLines` 1 / `maxLines` 5. Keep the existing controller and the existing send-on-submit
    behaviour, if there is any.
- **Action row** (gap 6):
  - **Model chip,** when `model != null`: height 32, padding 0×10, radius 999, `line` border. It shows
    "‹model›" in mono 12 `inkMuted` with a 12px chevron-down and calls `onModel`. The semantic label is
    "Model: ‹model›". It is disabled (with no chevron) when `onModel` is null.
  - A spacer.
  - **Send:** a 40px circle in `accent` with an up-arrow (18px, `accentInk`). Semantic label "Send". Disabled at
    0.4 opacity when the text is blank or `!enabled`. It appears with a 250ms fade or scale.
  - **Stop,** shown while running in place of Send: a 40px circle in `surface` with
    `IrisOrb(state, 40, glow: false)` behind a 10×10 `ink` square (radius 2). Semantic label "Stop".
- Update the tests that used `find.text('Send')` / `find.text('Stop')` to use `find.bySemanticsLabel`, and the ones
  that read the model in the header (`'gpt-6-luna ▾'`, and similar) to read it from the chip.

## Task 9: Screen goldens and final checks

1. Add `test/design/screens_golden_test.dart`. It renders **home**, **chat** and **settings** at 390×844 in
   Aperture dark **and** Aperture light, with `disableAnimations`, the bundled fonts, and the fakes in
   `test/support/` (`fake_chat_backend.dart`, `fakes.dart`). Cover these cases:
   - home with 5 conversations
   - chat with a user turn, a finished assistant turn that has reasoning, a done tool call and a fenced code block
   - chat in the empty state
   - settings
   Write the goldens to `test/design/goldens/screen_*.png`.
2. Run `flutter test --update-goldens test/design`, then **open every new PNG**. Compare each one against the
   design's markup for spacing, colour and type, and fix whatever is visibly off. Also check light mode for
   unreadable text, which comes from hard-coded colours.
3. Run `flutter analyze` (0 issues), the full `flutter test`, and `flutter build apk --debug` to confirm that the
   Android build compiles.
4. Run `grep -rn "Color(0x" lib/features`. It must return nothing new, because feature code uses palette roles
   only.
5. Commit, then report back:
   - the list of commits
   - test counts
   - the paths of the screen goldens
   - anything in the design you could not match, and why

## Out of scope (do not build)

- The Scheduled and Tasks tabs, the segmented control, the mic, voice mode, attachments and the "⋯" menu.
- The design's left-hand "state legend" panel and the phone frame. Those are presentation scaffolding in the design
  file, not app UI.
- A retry action on failed turns.
- Persisting theme choices.
