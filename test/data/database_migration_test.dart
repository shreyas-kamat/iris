/// Upgrading a database written by the hermes-webui build.
///
/// Dev installs already hold a v1 `servers` table. The upgrade must add the new
/// columns without losing rows, and must drop the webui capability probe, whose
/// names mean nothing to a dashboard.
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/prefs/preferences_store.dart';

void main() {
  test('a v1 database upgrades in place', () async {
    final db = IrisDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
CREATE TABLE servers (
  id TEXT NOT NULL,
  base_url TEXT NOT NULL,
  label TEXT NOT NULL,
  requires_password INTEGER NOT NULL DEFAULT 0 CHECK (requires_password IN (0, 1)),
  allow_self_signed INTEGER NOT NULL DEFAULT 0 CHECK (allow_self_signed IN (0, 1)),
  capabilities_json TEXT NOT NULL DEFAULT '[]',
  probed_at INTEGER NULL,
  last_connected_at INTEGER NULL,
  position INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
);''');
          raw.execute(
            'INSERT INTO servers (id, base_url, label, capabilities_json, probed_at) '
            "VALUES ('old', 'https://h.example', 'Old', '[\"crons\"]', 1700000000);",
          );
          raw.execute('PRAGMA user_version = 1;');
        },
      ),
    );
    addTearDown(db.close);

    final row = await db.select(db.servers).getSingle();
    expect(row.label, 'Old');
    expect(row.usesAccessToken, isFalse);
    expect(row.serverVersion, isNull);
    expect(row.capabilitiesJson, '[]');
    expect(row.probedAt, isNull);
    // v4 adds the connection mode; servers from before it have none.
    expect(row.connectionMode, isNull);

    // v3 adds the preferences table on the way up.
    final prefs = DriftPreferencesStore(db);
    await prefs.write('', PreferenceKeys.mode, 'light');
    expect(await prefs.loadAll(), {('', 'theme.mode'): 'light'});
  });

  test('a fresh database has the new columns', () async {
    final db = IrisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.servers)
        .insert(
          ServersCompanion.insert(
            id: 'new',
            baseUrl: 'https://h.example',
            label: 'New',
            usesAccessToken: const Value(true),
            serverVersion: const Value('0.9.1'),
          ),
        );
    final row = await db.select(db.servers).getSingle();
    expect(row.usesAccessToken, isTrue);
    expect(row.serverVersion, '0.9.1');
  });
}
