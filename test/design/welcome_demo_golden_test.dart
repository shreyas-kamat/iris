/// The welcome screen, demo home and a demo chat mid-turn, light and dark.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/demo/demo_mode.dart';
import 'package:iris/demo/demo_world.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/servers/welcome_screen.dart';

import '../support/fonts.dart';

const _phone = Size(390, 844);
final _now = DateTime(2026, 10, 15, 20, 40);

class _FixedTheme extends ThemeController {
  _FixedTheme(this._value);
  final ThemePreference _value;

  @override
  ThemePreference build() => _value;
}

/// A demo already running, on the fixed clock.
class _RunningDemo extends DemoSession {
  @override
  DemoWorld? build() => DemoWorld(clock: () => _now);
}

Widget _framed(
  Widget screen, {
  required bool isDark,
  List<Override> overrides = const [],
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
      serversProvider.overrideWith(
        (ref) => Stream.value(const <ServerConfig>[]),
      ),
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

void main() {
  setUpAll(loadIrisFonts);

  Future<void> pumpFor(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> sizeToPhone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_phone);
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final isDark in [true, false]) {
    final mode = isDark ? 'dark' : 'light';

    testWidgets('welcome, $mode', (tester) async {
      await sizeToPhone(tester);
      await tester.pumpWidget(_framed(const WelcomeScreen(), isDark: isDark));
      await pumpFor(tester, 4);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/screen_welcome_$mode.png'),
      );
    });

    testWidgets('demo home and a demo chat waiting on an approval, $mode', (
      tester,
    ) async {
      await sizeToPhone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _framed(
          const ConversationListScreen(),
          isDark: isDark,
          overrides: [demoSessionProvider.overrideWith(_RunningDemo.new)],
        ),
      );
      await pumpFor(tester, 4);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/screen_demo_home_$mode.png'),
      );

      await tester.tap(find.bySemanticsLabel('New conversation'));
      await pumpFor(tester, 4);
      await tester.tap(find.text('Check disk space on my server'));
      // The thinking and two tool calls play, then the approval card waits.
      await pumpFor(tester, 50);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/screen_demo_chat_$mode.png'),
      );
      handle.dispose();
    });
  }
}
