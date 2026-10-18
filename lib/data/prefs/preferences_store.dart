/// Settings that outlive a launch.
///
/// Read once before the first frame (see `main.dart`), so the theme is right
/// on the very first paint, then written through as the person changes
/// things. A failed write is logged and forgotten: a setting that does not
/// stick is a small annoyance, and must never block the screen it was changed
/// on.
library;

import 'package:drift/drift.dart';

import '../../core/logging.dart';
import '../db/database.dart';

/// `(scope, key)`. The scope is `''` for app-wide settings, else a server id.
typedef PreferenceKey = (String scope, String key);

/// The keys Iris stores, so a typo is a compile error rather than a setting
/// that silently never loads.
abstract final class PreferenceKeys {
  static const skin = 'theme.skin';
  static const mode = 'theme.mode';
  static const followServerSkin = 'theme.followServerSkin';

  /// Per server: the profile home shows.
  static const profile = 'profile';

  /// Per server: a JSON list of provider slugs, `@profile` meaning the
  /// active profile's own provider.
  static const usageProviders = 'usage.providers';

  /// Per `<server>/<profile>`: a JSON list of pinned stored ids, newest first.
  static const pins = 'pins';

  /// Per `<server>/<profile>`: `branch.<childId>` → where a branch came from.
  static String branch(String childId) => 'branch.$childId';

  /// Per server: a JSON list of recent search queries, newest first.
  static const searchRecent = 'search.recent';

  /// Per server: hosts whose Markdown images load without a tap.
  static const imageHosts = 'images.hosts';

  /// App-wide: how a call listens, `handsFree` or `pushToTalk`.
  static const voiceStyle = 'voice.style';

  /// App-wide: `false` when calls start on the earpiece, not the speaker.
  static const voiceSpeaker = 'voice.speaker';

  /// App-wide: `true` when live captions are on.
  static const voiceCaptions = 'voice.captions';

  /// App-wide: `true` once the first-run voice tags have been shown.
  static const voiceTagsSeen = 'voice.tagsSeen';

  /// App-wide: `true` once the microphone primer has been shown and the
  /// system prompt asked for, so a later refusal opens Settings instead.
  static const voiceMicAsked = 'voice.micAsked';

  /// Per `<server>/<profile>`: `voiceCalls.<id>` → a JSON list of the voice
  /// calls made in one conversation, oldest first.
  static String voiceCalls(String id) => 'voiceCalls.$id';
}

abstract interface class PreferencesStore {
  Future<Map<PreferenceKey, String>> loadAll();

  /// Stores [value] under [scope] and [key], or removes the key when null.
  Future<void> write(String scope, String key, String? value);
}

final class DriftPreferencesStore implements PreferencesStore {
  DriftPreferencesStore(this._db);

  final IrisDatabase _db;
  static const _log = IrisLog('prefs');

  @override
  Future<Map<PreferenceKey, String>> loadAll() async {
    final rows = await _db.select(_db.preferences).get();
    return {for (final row in rows) (row.scope, row.key): row.value};
  }

  @override
  Future<void> write(String scope, String key, String? value) async {
    try {
      if (value == null) {
        await (_db.delete(_db.preferences)
              ..where((row) => row.scope.equals(scope) & row.key.equals(key)))
            .go();
      } else {
        await _db
            .into(_db.preferences)
            .insertOnConflictUpdate(
              PreferencesCompanion.insert(scope: scope, key: key, value: value),
            );
      }
    } on Object catch (error) {
      _log.warn('could not save $key', data: '$error');
    }
  }
}

/// Keeps settings in memory only. The default when no database is wired, so
/// tests and previews never need one.
final class MemoryPreferencesStore implements PreferencesStore {
  final Map<PreferenceKey, String> values = {};

  @override
  Future<Map<PreferenceKey, String>> loadAll() async => Map.of(values);

  @override
  Future<void> write(String scope, String key, String? value) async {
    if (value == null) {
      values.remove((scope, key));
    } else {
      values[(scope, key)] = value;
    }
  }
}
