# Iris

A Flutter client for [Hermes Agent](https://github.com/NousResearch/hermes-agent), talking to
your own Hermes dashboard (the agent's built-in web dashboard, default port 9119).

The phone is a control plane, not a compute plane. The agent, its tools and your data stay on
your hardware. Iris connects directly to your server — no relay, no account, no analytics.

## Status

Phases 0 (foundation), 1 (design system) and the dashboard transport are complete: Iris signs
in (through Cloudflare Access when the dashboard sits behind it), holds a live JSON-RPC
connection that reconnects by itself, and shows its state. Chat is next.

## The design language

**Aperture.** Iris is the Greek messenger who travels on light — Hermes' counterpart, which is
exactly this app's relationship to the server it talks to. The agent works on a machine in another
room; this is the opening you watch it through.

- **Colour is state, not decoration.** The accent hue names what the agent is doing — thinking is
  cool, tools run warm, an approval gate is hot enough to stop your thumb. You should know a run's
  state before reading a word. Every colour is derived in OKLCH so ramps step evenly across all ten
  skins instead of going muddy in some hues; `lib/design/tokens/oklch.dart` does the conversion and
  fits out-of-gamut colours by reducing chroma rather than clipping channels.
- **Mono is the interface's own voice.** Section labels, tool names, timestamps, counts and paths
  are set in Geist Mono, small and tracked; prose is Geist. Nearly everything the app says on its
  own behalf is machine fact, and setting it apart means you can tell what the agent *said* from
  what the app is *reporting* without reading either.
- **Boldness is spent in one place.** The aperture (`design/components/aperture.dart`) is the only
  element allowed continuous motion. It answers the three questions the whole app exists for — is
  it alive, what is it doing, does it need me — in one 26pt mark, through hue, dilation and motion
  simultaneously, so it stays legible to someone who cannot separate the colours.
- **Everything moves on a spring.** Duration curves restart when interrupted; springs carry their
  velocity into the new target. On a phone, where every gesture is interrupted, that is the
  difference between software and an object. Reduced-motion is honoured throughout.

## Architecture

```
lib/
  core/       Result / IrisFailure, tolerant JSON, redacting logger
  design/     tokens, theme, components, motion, platform adapters
  data/
    net/      dio client, failure translation, capability probe
    rpc/      JSON-RPC over WebSocket: frames, client, live session
    db/       Drift schema — offline mirror and durable outbox
    models/   wire models, hand-decoded through Json
  features/   one folder per screen
  services/   notifications, live activity, voice, share intake
```

`features/` talks only to repositories. Repositories return `Result<T>` and never throw.

### Three load-bearing decisions

**Tolerant decoding.** The Hermes dashboard ships fast and every user runs a different build, so no wire
field is trusted to exist or to have the type it had last week. Everything is read through
`core/json.dart`, which never throws and coerces across the representations the server actually
uses. An unknown SSE event becomes `UnknownEvent` and renders as a labelled chip rather than
crashing the transcript.

**Capability probing, not version pinning.** Features are gated on whether an endpoint answers,
not on a version string — version numbers lie about backported and locally-patched builds, and
pinning would let an app update declare a user's own machine unsupported.

**Reconnection is normal.** A phone loses its connection constantly while the agent keeps working.
`DashboardSession` mints a fresh single-use ticket and reopens the socket with backoff,
signing in again first if the session cookie expired. An access-proxy refusal or an untrusted
certificate stops it instead, because retrying cannot fix either.

## What the design system guarantees

These are asserted by tests, not by intention. Each one failed at least once before it held.

- **Contrast.** Every foreground/background pair in all ten skins in both appearances is measured
  against WCAG AA (`test/design/contrast_test.dart`, 13 assertions across 20 palettes). This caught
  placeholder text sitting at 2.84:1, below even the large-text floor.
- **Touch targets.** Anything tappable reserves at least 44pt in both axes, without changing how it
  looks. Non-interactive chips are not padded out.
- **Text scaling.** The whole gallery renders without overflow at 200% text, in portrait and in
  landscape. Buttons grow rather than clipping their labels; tracked mono labels stop scaling at
  1.6x, where they would otherwise wrap mid-word.
- **Insets.** The composer rises above the keyboard and sits above the home indicator, never both.
  Headers clear the notch. Scroll views end above the home bar.
- **Screen readers.** Fields announce what they are for rather than only their contents; errors are
  live regions so they are spoken when they appear.
- **Windows.** Portrait, landscape, and a 320pt iPhone SE all render without overflow. Size classes
  are separate for width and height, because a phone in landscape has plenty of width and almost no
  height.
- **Reduced motion.** Honoured everywhere, including the aperture's ambient animation, which stops
  rather than slowing.

## Development

```sh
flutter pub get
dart run build_runner build      # Drift codegen
flutter analyze                  # must be clean
flutter test
flutter run
```

Regenerate after touching `lib/data/db/database.dart`.

## Environment notes

- **`compileSdk` is pinned to 36** in `android/app/build.gradle.kts`. Flutter defaults to 37, but
  this SDK installs the minor-versioned `android-37.0` platform, which AGP 8.11 cannot match
  against the plain `android-37` hash it looks for. `flutter_secure_storage` warns that it was
  compiled against 37; the build and app work at 36. Resolving it properly means AGP 8.13+ and
  `compileSdkMinor`, which is a separate upgrade.
- **`applicationId` is still `com.example.iris`.** It has to change before any store release and
  is permanent once published, so it is left for a deliberate choice rather than guessed at.
- **Cloudflare Access.** A dashboard published behind Access needs a service token (Zero Trust
  → Access → Service credentials) and a *Service Auth* policy on the application. Iris sends it
  as `CF-Access-Client-Id` / `CF-Access-Client-Secret`, over HTTPS only.
