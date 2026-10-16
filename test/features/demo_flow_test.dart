/// Into the demo, around it, and out again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/demo/demo_mode.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/home/link_status_screen.dart';
import 'package:iris/features/servers/server_gate.dart';
import 'package:iris/features/servers/welcome_screen.dart';
import 'package:iris/features/settings/settings_screen.dart';

import '../support/harness.dart';

void main() {
  Widget app() => ProviderScope(
    overrides: [
      // No database: the gate only reads the list, and an open drift stream
      // would hold teardown for minutes.
      serversProvider.overrideWith(
        (ref) => Stream.value(const <ServerConfig>[]),
      ),
    ],
    child: themed(ServerGate(connected: (_) => const ConversationListScreen())),
  );

  /// Lets providers resolve, and a demo turn play a little.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Opens the demo from the welcome screen. The caller disposes the handle.
  Future<SemanticsHandle> enterDemo(WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.text('Try the demo'));
    await settle(tester);
    return semantics;
  }

  testWidgets(
    'Try the demo opens home with the Demo pill and its conversations',
    (tester) async {
      final handle = await enterDemo(tester);
      expect(find.byType(ConversationListScreen), findsOneWidget);
      expect(find.text('DEMO'), findsWidgets);
      expect(find.text('Nightly backup to B2'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('a new demo chat offers the scripted prompts, and one plays', (
    tester,
  ) async {
    final handle = await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('New conversation'));
    await settle(tester);
    expect(find.text('Check disk space on my server'), findsOneWidget);
    await tester.tap(find.text("Summarise this week's GitHub issues"));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('acme/homelab-scripts'), findsWidgets);
    expect(find.text('Check disk space on my server'), findsNothing);
    handle.dispose();
  });

  testWidgets('the fallback link leaves the demo from inside a chat', (
    tester,
  ) async {
    final handle = await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('New conversation'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'hello there');
    // The send button enables on the next frame.
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tapOnText(
      find.textRange.ofSubstring('connect your own Hermes server'),
    );
    await settle(tester);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WelcomeScreen)),
    );
    expect(container.read(demoModeProvider), isFalse);
    handle.dispose();
  });

  testWidgets('Settings has Leave demo, and it returns to the welcome screen', (
    tester,
  ) async {
    final handle = await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Servers'), findsNothing);
    await tester.ensureVisible(find.text('Leave demo'));
    await tester.tap(find.text('Leave demo'));
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the connection screen in the demo offers no server switcher', (
    tester,
  ) async {
    final handle = await enterDemo(tester);
    await tester.tap(find.textContaining('demo.iris'));
    await settle(tester);
    expect(find.byType(LinkStatusScreen), findsOneWidget);
    await tester.tap(find.text('Demo').last);
    await settle(tester);
    expect(find.text('Add a server'), findsNothing);
    handle.dispose();
  });

  testWidgets('Deploy the docs site asks for the unlock, then settles it', (
    tester,
  ) async {
    final handle = await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('New conversation'));
    await settle(tester);
    await tester.ensureVisible(find.text('Deploy the docs site'));
    await tester.tap(find.text('Deploy the docs site'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('1Password is locked'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(IrisField),
        matching: find.byType(EditableText),
      ),
      'typed',
    );
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('Unlocked 1Password'), findsOneWidget);
    expect(find.text('1Password is locked'), findsNothing);
    handle.dispose();
  });
}
