/// The connect flow asks for exactly what the dashboard wants.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/net/connection_mode.dart';
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

  Widget harness({ConnectionMode mode = ConnectionMode.cloudflare}) {
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
            child: IrisTheme(
              data: theme,
              child: ConnectScreen(mode: mode),
            ),
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

  testWidgets('each mode shows its own example and help', (tester) async {
    await tester.pumpWidget(harness(mode: ConnectionMode.lan));
    expect(find.text('SAME WI-FI'), findsOneWidget);
    expect(find.text('http://192.168.1.20:9119'), findsOneWidget);
    expect(find.textContaining('ip addr'), findsOneWidget);

    await tester.pumpWidget(harness(mode: ConnectionMode.tailscale));
    expect(find.text('http://100.101.102.103:9119'), findsOneWidget);
    expect(find.textContaining('Tailscale app'), findsOneWidget);
  });

  testWidgets(
    'a public address over plain http is refused before any request',
    (tester) async {
      await tester.pumpWidget(harness(mode: ConnectionMode.lan));
      await submitAddress(tester, 'http://hermes.example.com');
      expect(
        find.text('Use https for an address on the internet.'),
        findsOneWidget,
      );
      expect(http.requests, isEmpty);
    },
  );

  testWidgets('a bare LAN address goes out over http', (tester) async {
    await tester.pumpWidget(harness(mode: ConnectionMode.lan));
    await submitAddress(tester, '192.168.1.20:9119');
    expect(http.requests, isNotEmpty);
    expect(http.requests.first.uri.scheme, 'http');
    expect(http.requests.first.uri.host, '192.168.1.20');
  });

  testWidgets('Change goes back', (tester) async {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    await tester.pumpWidget(
      ProviderScope(
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
            builder: (context, navigator) => IrisTheme(
              data: theme,
              child: Material(
                type: MaterialType.transparency,
                child: navigator,
              ),
            ),
            home: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ConnectScreen(mode: ConnectionMode.lan),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsNothing);
  });

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
