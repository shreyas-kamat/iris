import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/iris_app.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened before the first frame rather than lazily: every screen reads from
  // it, and an app that renders an empty state for a moment before its own data
  // arrives looks broken on every cold start.
  final database = await openDatabase();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const IrisApp(),
    ),
  );
}
