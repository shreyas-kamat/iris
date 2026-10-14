/// Settings that outlive a launch: written, read back, replaced, removed.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/prefs/preferences_store.dart';

void main() {
  late IrisDatabase db;
  late DriftPreferencesStore store;

  setUp(() {
    db = IrisDatabase(NativeDatabase.memory());
    store = DriftPreferencesStore(db);
  });
  tearDown(() => db.close());

  test('a written value reads back under its scope and key', () async {
    await store.write('', PreferenceKeys.mode, 'dark');
    await store.write('s1', PreferenceKeys.profile, 'ananta');
    expect(await store.loadAll(), {
      ('', 'theme.mode'): 'dark',
      ('s1', 'profile'): 'ananta',
    });
  });

  test('writing again replaces; null removes', () async {
    await store.write('s1', PreferenceKeys.profile, 'ananta');
    await store.write('s1', PreferenceKeys.profile, 'indra');
    expect((await store.loadAll())[('s1', 'profile')], 'indra');
    await store.write('s1', PreferenceKeys.profile, null);
    expect(await store.loadAll(), isEmpty);
  });

  test('the same key under two servers is two values', () async {
    await store.write('s1', PreferenceKeys.profile, 'a');
    await store.write('s2', PreferenceKeys.profile, 'b');
    final all = await store.loadAll();
    expect(all[('s1', 'profile')], 'a');
    expect(all[('s2', 'profile')], 'b');
  });

  test('the memory store behaves the same', () async {
    final memory = MemoryPreferencesStore();
    await memory.write('', PreferenceKeys.skin, 'mono');
    expect(await memory.loadAll(), {('', 'theme.skin'): 'mono'});
    await memory.write('', PreferenceKeys.skin, null);
    expect(memory.values, isEmpty);
  });
}
