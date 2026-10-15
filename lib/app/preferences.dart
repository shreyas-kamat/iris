/// The person's saved choices, as providers.
///
/// [initialPreferencesProvider] is the snapshot `main` read before the first
/// frame; [preferencesProvider] is the live copy every change goes through,
/// so a value set now is what the next rebuild reads, and the store is
/// written behind it.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs/preferences_store.dart';
import '../demo/demo_mode.dart';

/// Where choices are written. In memory unless `main` wires the database, so
/// tests and goldens never need one.
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => MemoryPreferencesStore(),
);

/// What was saved when the app started.
final initialPreferencesProvider = Provider<Map<PreferenceKey, String>>(
  (ref) => const {},
);

final preferencesProvider =
    NotifierProvider<PreferencesController, Map<PreferenceKey, String>>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<Map<PreferenceKey, String>> {
  @override
  Map<PreferenceKey, String> build() => ref.watch(initialPreferencesProvider);

  String? get(String scope, String key) => state[(scope, key)];

  /// Saves [value], or forgets the key when it is null.
  void set(String scope, String key, String? value) {
    if (state[(scope, key)] == value) return;
    final next = Map.of(state);
    if (value == null) {
      next.remove((scope, key));
    } else {
      next[(scope, key)] = value;
    }
    state = next;
    // The demo is a look around: what is chosen there lasts the session and is
    // never written to disk.
    if (scope == demoServer.id) return;
    unawaited(ref.read(preferencesStoreProvider).write(scope, key, value));
  }
}
