/// First run: how the phone reaches the server.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/servers/connect_screen.dart';
import 'package:iris/features/servers/welcome_screen.dart';

import '../support/harness.dart';

void main() {
  testWidgets('offers the three ways to connect', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: themed(const WelcomeScreen(showDemo: false))),
    );
    expect(find.text('Same Wi-Fi'), findsOneWidget);
    expect(find.text('Tailscale'), findsOneWidget);
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(find.text('Try the demo'), findsNothing);
  });

  for (final (row, example) in [
    ('Same Wi-Fi', 'http://192.168.1.20:9119'),
    ('Tailscale', 'http://100.101.102.103:9119'),
    ('Cloudflare', 'https://hermes.example.com'),
  ]) {
    testWidgets('$row opens the connect screen for it', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: themed(const WelcomeScreen(showDemo: false))),
      );
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectScreen), findsOneWidget);
      expect(find.text(example), findsOneWidget);
    });
  }
}
