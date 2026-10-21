/// The Iris palette.
///
/// ## The direction: aperture
///
/// Iris is the Greek messenger who travels on light — Hermes' counterpart, which
/// is exactly the relationship the app has to the server it talks to. The agent
/// works somewhere else, on a machine in another room, and this is the opening
/// you watch it through. So the language is light and aperture, not the green
/// phosphor terminal every agent client reaches for.
///
/// Three decisions follow from that:
///
/// **The ground is ink, not black.** A deep blue-violet, the colour of a room
/// with a screen in it. Pure black would make the app a void; a neutral grey
/// would make it an admin panel. The tint is slight — a few thousandths of
/// chroma — but it is what stops the dark theme reading as a default.
///
/// **Colour is state, not decoration.** The accent hue is not a brand constant
/// applied everywhere; it names what the agent is doing. Thinking is cool,
/// tools run warm, an approval gate is hot enough to stop your thumb. A person
/// glancing at their phone should know the run's state before reading a word.
///
/// **Boldness is spent in one place.** The transcript is quiet — near-neutral
/// surfaces, restrained type. The aperture is the one element that moves and
/// shifts hue. Everything else stays out of its way.
library;

import 'dart:ui';

import 'oklch.dart';

/// What the agent is doing, as far as the interface is concerned.
///
/// This is the only thing that drives accent hue, so the mapping lives with the
/// palette rather than being scattered across widgets.
enum AgentState {
  /// Connected, nothing running.
  idle,

  /// Model is reasoning — the `reasoning` event.
  thinking,

  /// Assistant text is arriving — the `token` event.
  streaming,

  /// A tool is executing — between `tool` and `tool_complete`.
  working,

  /// Blocked on the user: an approval gate or a clarify prompt.
  waiting,

  /// The turn finished cleanly.
  done,

  /// The run failed, or the connection is lost.
  failed,

  /// Connecting, or reaching the gateway for the first time.
  loading,

  /// The gateway cannot be reached right now.
  offline,

  /// A finished conversation at rest, as opposed to a turn that just ended.
  /// Kept apart from [done] so a list of old conversations does not light up
  /// green: only the moment of completion earns the success colour.
  rest;

  /// The word shown beside the orb. These are the design's own labels, so the
  /// header, the hero and the transcript all speak the same language.
  String get label => switch (this) {
    AgentState.idle => 'Ready',
    AgentState.thinking => 'Thinking',
    AgentState.streaming => 'Writing',
    AgentState.working => 'Using tools',
    AgentState.waiting => 'Needs you',
    AgentState.done => 'Done',
    AgentState.failed => 'Failed',
    AgentState.loading => 'Connecting',
    AgentState.offline => 'Offline',
    AgentState.rest => 'Done',
  };
}

/// What the voice orb is doing during a call. The colour names it, as
/// [AgentState] does for the agent; the two are kept apart because a call has
/// states a run does not (hearing you, muted, interrupted) and the voice
/// colours are the design's own.
enum VoiceOrbMode {
  /// Between calls, or a call that has not begun.
  idle,

  /// Warming up: checks running before the call opens.
  connecting,

  /// The call is open and waiting for you to speak.
  listening,

  /// You are speaking.
  hearing,

  /// The agent is working on your request.
  thinking,

  /// The agent is running a tool.
  tool,

  /// The agent is speaking.
  speaking,

  /// You spoke over the agent.
  interrupted,

  /// The microphone is off.
  muted,

  /// The call failed.
  error,

  /// The agent is waiting for an answer from you.
  needs,

  /// The link is down.
  offline,
}

/// Resolved colours for one skin in one brightness.
///
/// Widgets read roles, never ramps: a component asking for `palette.line` keeps
/// working in every skin, whereas one asking for "neutral 800" breaks the first
/// time a skin inverts.
final class IrisPalette {
  const IrisPalette({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.scrim,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkInverse,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentQuiet,
    required this.accentHue,
    required this.neutralHue,
    required this.chroma,
  });

  final bool isDark;

  /// The page ground. Everything else sits on this.
  final Color canvas;

  /// Cards, tool output, message groups — one step off the ground.
  final Color surface;

  /// Sheets and menus, which float above the conversation.
  final Color surfaceRaised;

  /// Wells: code blocks, input fields — one step *into* the page.
  final Color surfaceSunken;

  /// The wash behind a modal surface.
  final Color scrim;

  final Color ink;

  /// Secondary text: timestamps, captions, metadata.
  final Color inkMuted;

  /// Text that should be present but never compete — placeholders, hints.
  final Color inkFaint;

  /// Text on top of [accent].
  final Color inkInverse;

  /// Hairlines and dividers.
  final Color line;

  /// Borders that need to be seen: focused fields, selected rows.
  final Color lineStrong;

  /// The skin's identity colour, used for selection and emphasis.
  final Color accent;

  /// Legible text on [accent].
  final Color accentInk;

  /// A tint of the accent, for selected backgrounds and badges.
  final Color accentQuiet;

  final double accentHue;
  final double neutralHue;
  final double chroma;

  /// Aperture in dark: the Iris design's own colours, fixed rather than derived.
  ///
  /// The values come from the design file (`design/Iris App.dc.html`), where
  /// they were chosen by eye against the orb. Deriving them from the skin's
  /// three numbers gives a close but visibly different ground, and the orb's
  /// glow is tuned against these exact tones. Changing one changes the look of
  /// the app's signature screen, so change it deliberately.
  ///
  /// Contrast assertions in `contrast_test.dart` apply to these values too. If
  /// one fails, nudge that single role and say why here; do not loosen the test.
  ///
  /// Nudged so far, each the smallest step that clears its floor:
  /// - `surfaceRaised` #17161F to #1B1A24. Measured 1.03 against `surface`,
  ///   under the 1.05 step the dark theme needs to lift a plane by tone alone.
  /// - `line` #1E1E27 to #242430. The design's hairline (white at 5%) measured
  ///   1.11 against `surface`, under the 1.18 needed for a divider to read as
  ///   structure rather than decoration.
  static const IrisPalette apertureDark = IrisPalette(
    isDark: true,
    canvas: Color(0xFF0B0B10),
    surface: Color(0xFF13131A),
    surfaceRaised: Color(0xFF1B1A24),
    surfaceSunken: Color(0xFF07070A),
    scrim: Color(0xA6050508),
    ink: Color(0xFFECEBF2),
    inkMuted: Color(0xFFA9A7B8),
    inkFaint: Color(0xFF6E6C7E),
    inkInverse: Color(0xFF14121F),
    line: Color(0xFF242430),
    lineStrong: Color(0xFF34333F),
    accent: Color(0xFFC9C3FF),
    accentInk: Color(0xFF14121F),
    accentQuiet: Color(0xFF25223A),
    accentHue: 296,
    neutralHue: 292,
    chroma: 0.165,
  );

  /// A destructive action's fill, and its text.
  ///
  /// Separate from `colorFor(failed)` because they do different jobs. That one
  /// tints an error message on a dark ground, so it must be *light* to stay
  /// legible — which as a button fill reads as coral, and a coral button does
  /// not look like it deletes anything. This one is deep and saturated, with
  /// light text on it, so the weight matches the consequence.
  Color get danger => Oklch(isDark ? 0.505 : 0.535, 0.185, 21).toColor();

  Color get onDanger => Oklch(0.985, 0.012, 21).toColor();

  /// The hue that names [state].
  ///
  /// Idle borrows the skin's own accent so a resting app looks like itself;
  /// every other state overrides it, because knowing a tool is running matters
  /// more than brand consistency in that moment.
  /// The hues are spread deliberately far apart. An earlier pass had thinking
  /// at 268 and the default accent at 258 — ten degrees, which is invisible at
  /// aperture size, so "idle" and "thinking" were the same mark. Nothing here
  /// is closer than about 35 degrees to its neighbour.
  double hueFor(AgentState state) => switch (state) {
    AgentState.idle => accentHue,
    AgentState.thinking => 258,
    AgentState.streaming => 222,
    AgentState.working => 68,
    AgentState.waiting => 32,
    AgentState.done => 152,
    AgentState.failed => 16,
    // The new states sit where the design's hexes put them. Offline and rest
    // are near-neutral, so their hue only nudges [quietFor]'s tint.
    AgentState.loading => 228,
    AgentState.offline => 280,
    AgentState.rest => 285,
  };

  /// The colour for [state].
  ///
  /// In the dark, these are the design's hex values exactly, because they were
  /// tuned against the design's ground and nobody should re-derive them. The
  /// light values are darker versions of the same hues, adjusted until they
  /// clear the contrast floor on a light canvas. [AgentState.idle] is the
  /// exception: it stays the skin's own accent so every skin still looks like
  /// itself when nothing is happening.
  Color colorFor(AgentState state) => switch (state) {
    AgentState.idle => accent,
    AgentState.thinking => _stateColor(isDark, 0xFF9B7BFF, 0xFF6A4BE0),
    AgentState.loading => _stateColor(isDark, 0xFF5CC8FF, 0xFF0A7FB8),
    AgentState.working => _stateColor(isDark, 0xFFFFB547, 0xFFA86200),
    AgentState.streaming => _stateColor(isDark, 0xFF4FE3C1, 0xFF0B8A70),
    AgentState.done => _stateColor(isDark, 0xFF6EE787, 0xFF1F8A3B),
    AgentState.failed => _stateColor(isDark, 0xFFFF6B6B, 0xFFD23A3A),
    AgentState.offline => _stateColor(isDark, 0xFF6B6A78, 0xFF74737F),
    AgentState.rest => _stateColor(isDark, 0xFF8E89AE, 0xFF6F6A90),
    AgentState.waiting => _stateColor(isDark, 0xFFFF8A5C, 0xFFC2501C),
  };

  /// The voice orb's colour for [mode]: the design's `DK` and `LT` tables from
  /// `design/iris-voice.js`, unchanged. Interrupted has no colour of its own;
  /// it is the moment the orb turns from speaking to hearing, so it takes
  /// hearing's.
  Color voiceOrbColor(VoiceOrbMode mode) => switch (mode) {
    VoiceOrbMode.idle => _stateColor(isDark, 0xFFC9C3FF, 0xFF4F3FCF),
    VoiceOrbMode.connecting => _stateColor(isDark, 0xFF5CC8FF, 0xFF0B6FA3),
    VoiceOrbMode.listening ||
    VoiceOrbMode.hearing ||
    VoiceOrbMode.interrupted => _stateColor(isDark, 0xFFFF8AD8, 0xFFB0307F),
    VoiceOrbMode.thinking => _stateColor(isDark, 0xFF9B7BFF, 0xFF6544D9),
    VoiceOrbMode.tool => _stateColor(isDark, 0xFFFFB547, 0xFF8A5000),
    VoiceOrbMode.speaking => _stateColor(isDark, 0xFF4FE3C1, 0xFF00735E),
    VoiceOrbMode.muted ||
    VoiceOrbMode.offline => _stateColor(isDark, 0xFF8A8898, 0xFF646372),
    VoiceOrbMode.error => _stateColor(isDark, 0xFFFF6B6B, 0xFFC0312D),
    VoiceOrbMode.needs => _stateColor(isDark, 0xFFFF8A5C, 0xFFB5410F),
  };

  static Color _stateColor(bool dark, int darkArgb, int lightArgb) =>
      Color(dark ? darkArgb : lightArgb);

  /// A tint of [state]'s colour, for the background of a status chip.
  ///
  /// The dark tint sits lower than it used to (0.30 to 0.21). The design's
  /// `offline` grey is dim, and against a 0.30 tint it measured 2.6, under the
  /// chip floor. A deeper tint keeps every state chip legible rather than
  /// lightening the design's own colour.
  Color quietFor(AgentState state) => Oklch(
    isDark ? 0.21 : 0.95,
    isDark ? 0.055 : 0.045,
    hueFor(state),
  ).toColor();

  /// Builds a palette from a skin's three parameters.
  ///
  /// Deriving every role from `accentHue`, `neutralHue` and `chroma` is what
  /// makes ten skins cost three numbers each instead of thirty hand-picked
  /// values that drift apart as the component set grows.
  factory IrisPalette.derive({
    required bool isDark,
    required double accentHue,
    required double neutralHue,
    required double chroma,
    double neutralChroma = 0.012,
  }) {
    final neutral = ColorRamp.neutral(neutralHue, chroma: neutralChroma);
    final accentRamp = ColorRamp.fromHue(accentHue, chroma: chroma);

    if (isDark) {
      return IrisPalette(
        isDark: true,
        // Not ramp stops: the dark ground needs to sit below the ramp's
        // darkest step so surfaces have somewhere to rise from.
        //
        // The chroma multipliers are large — up to 4x the neutral chroma —
        // because tint is far less visible at low lightness. An earlier pass
        // used 1.6x and the result was flat grey: the palette said "violet ink"
        // and the screen said "admin panel".
        canvas: Oklch(0.175, neutralChroma * 4.0, neutralHue).toColor(),
        surface: Oklch(0.228, neutralChroma * 3.4, neutralHue).toColor(),
        surfaceRaised: Oklch(0.282, neutralChroma * 3.0, neutralHue).toColor(),
        surfaceSunken: Oklch(0.138, neutralChroma * 4.4, neutralHue).toColor(),
        scrim: Oklch(0.10, neutralChroma, neutralHue, 0.66).toColor(),
        ink: neutral.color(50),
        inkMuted: Oklch(0.72, neutralChroma * 1.4, neutralHue).toColor(),
        inkFaint: Oklch(0.55, neutralChroma * 1.4, neutralHue).toColor(),
        inkInverse: Oklch(0.16, neutralChroma, neutralHue).toColor(),
        line: Oklch(0.32, neutralChroma * 1.5, neutralHue).toColor(),
        lineStrong: Oklch(0.44, neutralChroma * 1.5, neutralHue).toColor(),
        accent: accentRamp[400].toColor(),
        accentInk: Oklch(0.18, 0.03, accentHue).toColor(),
        accentQuiet: Oklch(0.30, chroma * 0.42, accentHue).toColor(),
        accentHue: accentHue,
        neutralHue: neutralHue,
        chroma: chroma,
      );
    }

    return IrisPalette(
      isDark: false,
      // The light planes are spread wider than they look like they need to be.
      // Relative luminance is heavily compressed near white, so two tones that
      // differ by a visible amount of lightness can still land within a 1.02
      // contrast ratio and read as the same surface. An earlier pass put canvas
      // at 0.985 with both surfaces at pure white, which collapsed the
      // three-plane system into two and tripped the no-pure-white rule: with
      // nothing above white, a raised card had nowhere to rise to.
      canvas: Oklch(0.963, neutralChroma * 0.9, neutralHue).toColor(),
      surface: Oklch(0.990, neutralChroma * 0.4, neutralHue).toColor(),
      surfaceRaised: Oklch(0.996, neutralChroma * 0.2, neutralHue).toColor(),
      surfaceSunken: Oklch(0.935, neutralChroma * 1.4, neutralHue).toColor(),
      scrim: Oklch(0.30, neutralChroma, neutralHue, 0.34).toColor(),
      ink: Oklch(0.235, neutralChroma * 2.2, neutralHue).toColor(),
      inkMuted: Oklch(0.475, neutralChroma * 1.8, neutralHue).toColor(),
      // Darker than the word "faint" suggests, because a placeholder is text
      // someone has to read before they know what to type. At 0.635 it measured
      // 2.84 against the sunken field it sits in, under even the large-text
      // floor of 3.0.
      inkFaint: Oklch(0.580, neutralChroma * 1.5, neutralHue).toColor(),
      inkInverse: Oklch(0.99, 0, neutralHue).toColor(),
      line: Oklch(0.905, neutralChroma * 1.4, neutralHue).toColor(),
      lineStrong: Oklch(0.795, neutralChroma * 1.4, neutralHue).toColor(),
      accent: accentRamp[600].toColor(),
      accentInk: Oklch(0.99, 0, accentHue).toColor(),
      accentQuiet: Oklch(0.945, chroma * 0.30, accentHue).toColor(),
      accentHue: accentHue,
      neutralHue: neutralHue,
      chroma: chroma,
    );
  }
}

/// A named look. Three numbers and a name.
///
/// The set mirrors the skins hermes-webui ships so a user's phone and browser
/// agree; `aperture` is the Iris default and has no upstream counterpart.
enum IrisSkin {
  /// The default. Violet ink and a violet accent — the flower and the eye the
  /// app is named for, and a deliberate step away from the cornflower blue
  /// that every developer tool defaults to. Sits far enough round the wheel
  /// from `thinking` (258) that idle and thinking never read alike.
  aperture('Aperture', accentHue: 296, neutralHue: 292, chroma: 0.165),

  /// Near-neutral. For people who want the interface to disappear.
  mono('Mono', accentHue: 265, neutralHue: 265, chroma: 0.022),

  /// Cool blue-grey, slightly institutional.
  slate('Slate', accentHue: 232, neutralHue: 245, chroma: 0.105),

  /// Deep sea blue-green.
  poseidon('Poseidon', accentHue: 196, neutralHue: 220, chroma: 0.135),

  /// Iron and rust — a warm, martial red.
  ares('Ares', accentHue: 27, neutralHue: 35, chroma: 0.155),

  /// Stone and olive; muted, patient.
  sisyphus('Sisyphus', accentHue: 128, neutralHue: 105, chroma: 0.095),

  /// Soft lavender on warm grey, after the Catppuccin family.
  catppuccin('Catppuccin', accentHue: 300, neutralHue: 285, chroma: 0.125),

  /// Amber on near-black.
  nous('Nous', accentHue: 82, neutralHue: 70, chroma: 0.150),

  /// Maximum contrast, minimum colour. Accessibility-first.
  contrast('Contrast', accentHue: 250, neutralHue: 260, chroma: 0.09),

  /// Warm paper and terracotta, for reading long transcripts.
  sienna('Sienna', accentHue: 46, neutralHue: 55, chroma: 0.130);

  const IrisSkin(
    this.label, {
    required this.accentHue,
    required this.neutralHue,
    required this.chroma,
  });

  final String label;
  final double accentHue;

  /// The hue mixed into every surface and ink tone. Kept close to, but usually
  /// not identical to, [accentHue] — a neutral that exactly matches the accent
  /// makes the whole screen look like one wash.
  final double neutralHue;
  final double chroma;

  /// How much hue to allow into the neutrals. `contrast` pulls this toward zero
  /// so text sits on a genuinely achromatic ground.
  double get _neutralChroma => switch (this) {
    IrisSkin.contrast => 0.0,
    IrisSkin.mono => 0.006,
    IrisSkin.sienna || IrisSkin.ares => 0.016,
    _ => 0.012,
  };

  IrisPalette palette({required bool isDark}) {
    // Aperture dark is the design, so it is fixed. Every other combination
    // still derives, which keeps the other nine skins and light mode as they
    // were.
    if (this == IrisSkin.aperture && isDark) return IrisPalette.apertureDark;
    return IrisPalette.derive(
      isDark: isDark,
      accentHue: accentHue,
      neutralHue: neutralHue,
      chroma: chroma,
      neutralChroma: _neutralChroma,
    );
  }

  /// Matches a skin name reported by the server, so the phone can follow the
  /// browser. Unknown names fall back to [aperture] rather than failing.
  static IrisSkin parse(String? name) {
    final key = name?.trim().toLowerCase();
    if (key == null || key.isEmpty) return IrisSkin.aperture;
    for (final skin in IrisSkin.values) {
      if (skin.name == key || skin.label.toLowerCase() == key) return skin;
    }
    return switch (key) {
      // Upstream names that do not map one-to-one.
      'default' => IrisSkin.aperture,
      'geist-contrast' || 'geist' => IrisSkin.contrast,
      _ => IrisSkin.aperture,
    };
  }
}
