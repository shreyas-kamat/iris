/// The connect flow asks for exactly what the dashboard wants.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/repositories/server_repository.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/servers/connect_screen.dart';

import '../support/fake_http.dart';
import '../support/fakes.dart';

void main() {
  late FakeHttp http;
  late IrisDatabase db;
  late ServerRepository repository;

  setUp(() {
    http = FakeHttp();
    db = IrisDatabase(NativeDatabase.memory());
    repository = ServerRepository(
      database: db,
      credentials: FakeCredentialStore(),
      connect: (config, {required secrets}) =>
          ServerConnection.create(config, secrets: secrets, adapter: http),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  Widget harness() {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        serverRepositoryProvider.overrideWithValue(repository),
      ],
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: theme.materialTheme,
          home: Material(
            type: MaterialType.transparency,
            child: IrisTheme(data: theme, child: const ConnectScreen()),
          ),
        ),
      ),
    );
  }

  Future<void> submitAddress(WidgetTester tester, String address) async {
    await tester.enterText(find.byType(EditableText).first, address);
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('an access-gated address asks for a service token', (
    tester,
  ) async {
    http.on('GET', '/api/auth/providers', (_) => FakeReply.cloudflareLogin());
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    expect(find.text('CLIENT ID'), findsOneWidget);
    expect(find.text('CLIENT SECRET'), findsOneWidget);
    expect(find.textContaining('did not accept'), findsNothing);
  });

  testWidgets('a rejected token says so', (tester) async {
    http.on('GET', '/api/auth/providers', (_) => FakeReply.cloudflareLogin());
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    await tester.enterText(find.byType(EditableText).at(1), 'id.access');
    await tester.enterText(find.byType(EditableText).at(2), 'wrong');
    // The default test view is 800x600, and the button sits below its edge
    // once the token fields are shown; scroll it into view before tapping.
    await tester.ensureVisible(find.text('Continue'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('did not accept'), findsOneWidget);
  });

  testWidgets('a password dashboard asks for a username and password', (
    tester,
  ) async {
    http
      ..on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.json({
          'providers': [
            {'name': 'basic', 'supports_password': true},
          ],
        }),
      )
      ..on('GET', '/api/status', (_) => FakeReply.json({'version': '0.9.1'}));
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    expect(find.text('USERNAME'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.textContaining('0.9.1'), findsOneWidget);
  });

  testWidgets('a non-Hermes address explains the port', (tester) async {
    http.on('GET', '/api/auth/providers', (_) => FakeReply.html('<html/>'));
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    // IrisLabel renders titles in capitals.
    expect(find.text('NOT A HERMES DASHBOARD'), findsOneWidget);
  });
}
