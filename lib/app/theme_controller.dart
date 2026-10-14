/// Which skin and brightness the app is wearing.
///
/// Kept at the app root rather than inside Settings because two things outside
/// Settings can change it: the system switching to dark at sunset, and the
/// server reporting a skin the user picked in the browser. Iris follows both,
/// so the phone and the web UI look like the same product.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs/preferences_store.dart';
import '../design/theme/iris_theme.dart';
import '../design/tokens/palette.dart';
import 'preferences.dart';

/// How brightness is decided.
enum BrightnessMode {
  system,
  light,
  dark;

  String get label => switch (this) {
    BrightnessMode.system => 'System',
    BrightnessMode.light => 'Light',
    BrightnessMode.dark => 'Dark',
  };
}

/// The user's appearance choice.
@immutable
final class ThemePreference {
  const ThemePreference({
    this.skin = IrisSkin.aperture,
    this.mode = BrightnessMode.system,
    this.followServerSkin = true,
  });

  final IrisSkin skin;
  final BrightnessMode mode;

  /// Whether a skin reported by the server overrides [skin].
  ///
  /// On by default so the phone matches the browser without being configured,
  /// but switchable, because someone may reasonably want a light phone and a
  /// dark desktop.
  final bool followServerSkin;

  ThemePreference copyWith({
    IrisSkin? skin,
    BrightnessMode? mode,
    bool? followServerSkin,
  }) => ThemePreference(
    skin: skin ?? this.skin,
    mode: mode ?? this.mode,
    followServerSkin: followServerSkin ?? this.followServerSkin,
  );

  /// Resolves against the platform brightness.
  IrisThemeData resolve(Brightness platform) => IrisThemeData(
    skin: skin,
    isDark: switch (mode) {
      BrightnessMode.system => platform == Brightness.dark,
      BrightnessMode.light => false,
      BrightnessMode.dark => true,
    },
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThemePreference &&
          other.skin == skin &&
          other.mode == mode &&
          other.followServerSkin == followServerSkin);

  @override
  int get hashCode => Object.hash(skin, mode, followServerSkin);
}

/// Holds the appearance choice.
///
/// Written by hand rather than generated: `riverpod_generator` needs a newer
/// Dart SDK than this project's Flutter provides, and a plain [Notifier] costs
/// only the class declaration.
/// Not `final`, so tests and goldens can substitute a fixed preference through
/// `overrideWith` without standing up persistence.
class ThemeController extends Notifier<ThemePreference> {
  @override
  ThemePreference build() {
    // Read, not watched: the controller owns the theme from here on, and a
    // rebuild on every saved setting would throw away what it holds.
    final saved = ref.read(preferencesProvider);
    String? at(String key) => saved[('', key)];
    return ThemePreference(
      skin: at(PreferenceKeys.skin) == null
          ? IrisSkin.aperture
          : IrisSkin.parse(at(PreferenceKeys.skin)),
      mode:
          BrightnessMode.values.asNameMap()[at(PreferenceKeys.mode)] ??
          BrightnessMode.system,
      followServerSkin: at(PreferenceKeys.followServerSkin) != 'false',
    );
  }

  void setSkin(IrisSkin skin) {
    state = state.copyWith(skin: skin);
    _save(PreferenceKeys.skin, skin.name);
  }

  void setMode(BrightnessMode mode) {
    state = state.copyWith(mode: mode);
    _save(PreferenceKeys.mode, mode.name);
  }

  void setFollowServerSkin({required bool follow}) {
    state = state.copyWith(followServerSkin: follow);
    _save(PreferenceKeys.followServerSkin, '$follow');
  }

  void _save(String key, String value) =>
      ref.read(preferencesProvider.notifier).set('', key, value);

  /// Adopts a skin name the server reported, if the user has not opted out.
  ///
  /// Silently ignores an unknown name — a server running a skin this build has
  /// never heard of should leave the app looking like itself, not blank.
  void applyServerSkin(String? name) {
    if (!state.followServerSkin || name == null) return;
    final parsed = IrisSkin.parse(name);
    if (parsed != state.skin) state = state.copyWith(skin: parsed);
  }

  /// Cycles brightness. Bound to a long-press on the app's title in debug and
  /// to the Settings control in release.
  void cycleMode() => setMode(
    BrightnessMode.values[(state.mode.index + 1) %
        BrightnessMode.values.length],
  );
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemePreference>(ThemeController.new);
