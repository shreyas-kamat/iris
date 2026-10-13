/// The three screens a person lives in, rendered at phone size in both
/// brightnesses of the default skin.
///
/// Like the gallery goldens, these are reviewed by eye. Run with
/// `--update-goldens`, then open every PNG and check it against the design.
/// Motion is off and the clock is fixed, so the same code renders the same
/// image on any day and at any hour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/settings/settings_screen.dart';

import '../support/fake_chat_backend.dart';
import '../support/fonts.dart';

/// A phone's logical size. The goldens are captured at this size and no other.
const _phone = Size(390, 844);

/// A fixed "now": an evening, so the greeting is deterministic and the
/// relative times below have a stable reference.
final _now = DateTime(2026, 10, 14, 20, 40);

/// Pins the skin and brightness, so the screens render the same way no matter
/// what the device is set to.
class _FixedTheme extends ThemeController {
  _FixedTheme(this._value);
  final ThemePreference _value;

  @override
  ThemePreference build() => _value;
}

/// Frames a screen as the app frames it: the Iris theme above the navigator,
/// the phone's size, and reduced motion so nothing is caught mid-animation.
Widget _framed(
  Widget screen, {
  required bool isDark,
  required List<Override> overrides,
}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: isDark);
  return ProviderScope(
    overrides: [
      themeControllerProvider.overrideWith(
        () => _FixedTheme(
          ThemePreference(
            mode: isDark ? BrightnessMode.dark : BrightnessMode.light,
          ),
        ),
      ),
      clockProvider.overrideWithValue(() => _now),
      ...overrides,
    ],
    child: MediaQuery(
      data: const MediaQueryData(size: _phone, disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        builder: (context, navigator) => IrisTheme(
          data: theme,
          child: Material(type: MaterialType.transparency, child: navigator),
        ),
        home: screen,
      ),
    ),
  );
}

/// The server, the live link and the profiles every screen reads.
List<Override> _sharedOverrides(FakeChatBackend backend) => [
  activeServerProvider.overrideWithValue(
    const ServerConfig(
      id: 's',
      baseUrl: 'https://hermes.shreyaskamat.in',
      label: 'Hermes Ops',
    ),
  ),
  activeLinkProvider.overrideWith(
    (ref) => Stream.value(const LinkState(LinkPhase.live)),
  ),
  activeChatProvider.overrideWith((ref) async => backend),
  profilesProvider.overrideWith(
    (ref) async => const [
      AgentProfile(name: 'default', isDefault: true, model: 'opus-4.5'),
      AgentProfile(name: 'ananta', model: 'gpt-6-luna'),
    ],
  ),
];

/// Five recent conversations out of seven, so "Show more" shows as it does
/// once a person has more history than the first page.
final _conversations = [
  ConversationSummary(
    id: '1',
    title: 'Investigate worker heartbeat gaps',
    startedAt: _now.subtract(const Duration(minutes: 12)),
    messageCount: 14,
    source: 'desktop',
  ),
  ConversationSummary(
    id: '2',
    title: 'Refactor billing to usage-based pricing',
    startedAt: _now.subtract(const Duration(hours: 2)),
    messageCount: 31,
    source: 'telegram',
  ),
  ConversationSummary(
    id: '3',
    title: 'Nightly backup to cold storage',
    startedAt: _now.subtract(const Duration(hours: 5)),
    messageCount: 6,
    source: 'cron',
  ),
  ConversationSummary(
    id: '4',
    title: 'Design review: onboarding flow',
    startedAt: _now.subtract(const Duration(days: 1)),
    messageCount: 22,
    source: 'desktop',
  ),
  ConversationSummary(
    id: '5',
    title: 'Add passkey support to auth service',
    startedAt: _now.subtract(const Duration(days: 2)),
    messageCount: 9,
    source: 'desktop',
  ),
];

/// A finished exchange with everything a transcript can show: a question, a
/// tool the agent ran, and a reply with reasoning and a fenced code block.
final _exchange = <TranscriptItem>[
  const UserTurn(
    id: 'u1',
    text: 'Why did the worker heartbeat miss three checks overnight?',
  ),
  const ToolCall(
    id: 't1',
    name: 'read_logs',
    arguments: 'worker-*.log --since 01:00 --until 05:00',
    output: '3 gaps · 1.4s',
  ),
  const AssistantTurn(
    id: 'a1',
    reasoning:
        'Pull heartbeat logs between 01:00 and 05:00, then line the gaps up '
        'against deploys, cron runs and node restarts.',
    text:
        'The gaps line up with the 02:00 backup job. It saturates the disk on '
        'node-3, the worker blocks on fsync, and the heartbeat misses its 30s '
        'window.\n\n'
        'The fix is to give the heartbeat its own writer:\n\n'
        '```yaml\n'
        'heartbeat:\n'
        '  interval: 30s\n'
        '  writer: async\n'
        '  grace: 2\n'
        '```',
  ),
];

void main() {
  setUpAll(loadIrisFonts);

  /// Pumps a frame, then lets the async providers resolve. Pumps rather than
  /// settles, so a loading indicator cannot hold the test open.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> capture(
    WidgetTester tester, {
    required Widget screen,
    required bool isDark,
    required List<Override> overrides,
    required String name,
  }) async {
    await tester.binding.setSurfaceSize(_phone);
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _framed(screen, isDark: isDark, overrides: overrides),
    );
    await settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/screen_${name}_${isDark ? 'dark' : 'light'}.png',
      ),
    );
  }

  for (final isDark in [true, false]) {
    final mode = isDark ? 'dark' : 'light';

    testWidgets('home with five conversations, $mode', (tester) async {
      final backend = FakeChatBackend()
        ..conversationsResult = Ok(_conversations)
        ..historyResult = const Ok([]);
      addTearDown(backend.close);
      await capture(
        tester,
        screen: const ConversationListScreen(),
        isDark: isDark,
        overrides: [
          ..._sharedOverrides(backend),
          conversationsProvider.overrideWith(
            (ref) async => ConversationPage(
              items: _conversations,
              total: 7,
            ),
          ),
        ],
        name: 'home',
      );
    });

    testWidgets('chat with a reply, a tool and code, $mode', (tester) async {
      final backend = FakeChatBackend()
        ..historyResult = Ok(_exchange);
      addTearDown(backend.close);
      await capture(
        tester,
        screen: ChatScreen(
          backend: backend,
          conversationId: 'stored-1',
          title: 'Investigate worker heartbeat gaps',
        ),
        isDark: isDark,
        overrides: _sharedOverrides(backend),
        name: 'chat',
      );
    });

    testWidgets('a new chat in its empty state, $mode', (tester) async {
      final backend = FakeChatBackend()
        ..historyResult = const Ok([]);
      addTearDown(backend.close);
      await capture(
        tester,
        screen: ChatScreen(backend: backend),
        isDark: isDark,
        overrides: _sharedOverrides(backend),
        name: 'chat_empty',
      );
    });

    testWidgets('settings, $mode', (tester) async {
      final backend = FakeChatBackend();
      addTearDown(backend.close);
      await capture(
        tester,
        screen: const SettingsScreen(),
        isDark: isDark,
        overrides: [
          ..._sharedOverrides(backend),
          conversationsProvider.overrideWith(
            (ref) async => const ConversationPage(items: [], total: 0),
          ),
        ],
        name: 'settings',
      );
    });
  }
}
