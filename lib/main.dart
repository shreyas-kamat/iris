import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/iris_app.dart';
import 'app/licenses.dart';
import 'app/preferences.dart';
import 'app/providers.dart';
import 'data/prefs/preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

  // Opened before the first frame rather than lazily: every screen reads from
  // it, and an app that renders an empty state for a moment before its own data
  // arrives looks broken on every cold start.
  final database = await openDatabase();

  // The theme in particular must be known before the first paint, or a dark
  // phone flashes the light theme on every launch.
  final preferences = DriftPreferencesStore(database);
  final saved = await preferences.loadAll();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        preferencesStoreProvider.overrideWithValue(preferences),
        initialPreferencesProvider.overrideWithValue(saved),
      ],
      child: const IrisApp(),
    ),
  );
}
