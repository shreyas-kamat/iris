/// The Phase 1 home tells the truth about the link.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/home/link_status_screen.dart';

void main() {
  Widget harness(LinkState link, {ServerCapabilities? capabilities}) {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    return ProviderScope(
      overrides: [
        activeServerProvider.overrideWithValue(
          const ServerConfig(
            id: 's',
            baseUrl: 'https://h.example',
            label: 'Home',
          ),
        ),
        activeLinkProvider.overrideWith((ref) => Stream.value(link)),
        activeCapabilitiesProvider.overrideWith(
          (ref) => Stream.value(
            capabilities ?? const ServerCapabilities.unknown(),
          ),
        ),
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
            child: IrisTheme(data: theme, child: const LinkStatusScreen()),
          ),
        ),
      ),
    );
  }

  testWidgets('live shows connected and the version', (tester) async {
    await tester.pumpWidget(
      harness(
        const LinkState(LinkPhase.live),
        capabilities: ServerCapabilities(
          available: const {ServerCapability.profiles},
          probedAt: DateTime(2026),
          serverVersion: '0.9.1',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('0.9.1'), findsOneWidget);
    // IrisChip renders its label through IrisLabel, which is upper-cased.
    expect(find.text('PROFILES'), findsOneWidget);
  });

  testWidgets('an access gate is named', (tester) async {
    await tester.pumpWidget(
      harness(
        const LinkState(
          LinkPhase.blocked,
          failure: IrisFailure(FailureKind.accessGate),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Blocked by Cloudflare Access'), findsOneWidget);
    expect(find.text('Try again now'), findsOneWidget);
  });
}
