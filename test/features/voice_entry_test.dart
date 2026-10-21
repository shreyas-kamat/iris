/// How voice is reached from the composer: the voice button, the first-run
/// tags and the microphone sheets (frames A2, A3a, A3b).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/data/prefs/preferences_store.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/composer.dart';
import 'package:iris/features/voice/mic_permission.dart';
import 'package:iris/features/voice/mic_permission_sheet.dart';

import '../support/fake_voice.dart';
import '../support/harness.dart';

void main() {
  late TextEditingController text;

  setUp(() => text = TextEditingController());
  tearDown(() => text.dispose());

  Widget composer({
    bool voiceMode = true,
    bool dictation = true,
    VoidCallback? onVoice,
    VoidCallback? onMic,
    bool enabled = true,
    Duration? recording,
  }) => Align(
    alignment: Alignment.bottomCenter,
    child: Composer(
      controller: text,
      running: false,
      onSend: () {},
      onStop: () {},
      enabled: enabled,
      onMic: dictation ? (onMic ?? () {}) : null,
      voiceMode: voiceMode,
      onVoice: voiceMode ? (onVoice ?? () {}) : null,
      recording: recording,
    ),
  );

  group('the buttons', () {
    testWidgets('voice button when voice mode and empty', (tester) async {
      final semantics = tester.ensureSemantics();
      var talked = 0;
      await tester.pumpWidget(themed(composer(onVoice: () => talked++)));

      expect(find.byKey(const ValueKey('voice')), findsOneWidget);
      expect(find.byKey(const ValueKey('send')), findsNothing);
      expect(find.bySemanticsLabel('Talk hands-free'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('voice'))),
        const Size(44, 44),
      );

      await tester.tap(find.byKey(const ValueKey('voice')));
      expect(talked, 1);
      semantics.dispose();
    });

    testWidgets('text turns it into Send, with the mic still to its left', (
      tester,
    ) async {
      await tester.pumpWidget(themed(composer()));
      text.text = 'hello';
      await tester.pump();

      expect(find.byKey(const ValueKey('send')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice')), findsNothing);
      final mic = tester.getTopLeft(find.byKey(const ValueKey('mic')));
      final send = tester.getTopLeft(find.byKey(const ValueKey('send')));
      expect(mic.dx, lessThan(send.dx));
    });

    testWidgets('the mic is a 44 pt square that sits left of the action', (
      tester,
    ) async {
      await tester.pumpWidget(themed(composer()));
      final mic = find.byKey(const ValueKey('mic'));
      expect(tester.getSize(mic), const Size(44, 44));
      expect(
        tester.getTopLeft(mic).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('voice'))).dx),
      );
    });

    testWidgets('absent without voice mode', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(themed(composer(voiceMode: false)));

      expect(find.byKey(const ValueKey('voice')), findsNothing);
      expect(find.bySemanticsLabel('Talk hands-free'), findsNothing);
      expect(find.byKey(const ValueKey('mic')), findsOneWidget);
      expect(find.bySemanticsLabel('Dictate'), findsOneWidget);
      // The action slot is a quiet Send, not a hole.
      expect(find.byKey(const ValueKey('send')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no dictation means no mic, and no voice either', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(composer(voiceMode: false, dictation: false)),
      );
      expect(find.byKey(const ValueKey('mic')), findsNothing);
      expect(find.byKey(const ValueKey('voice')), findsNothing);
    });

    testWidgets('both buttons are off while the chat cannot take a message', (
      tester,
    ) async {
      var talked = 0;
      var dictated = 0;
      await tester.pumpWidget(
        themed(
          composer(
            enabled: false,
            onVoice: () => talked++,
            onMic: () => dictated++,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('voice')));
      await tester.tap(find.byKey(const ValueKey('mic')));
      expect(talked + dictated, 0);
    });

    testWidgets('nothing but the recording bar shows while recording', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(composer(recording: const Duration(seconds: 3))),
      );
      expect(find.byKey(const ValueKey('recording-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice')), findsNothing);
      expect(find.byKey(const ValueKey('mic')), findsNothing);
    });

    testWidgets('no overflow at 320 pt wide and 200% text', (tester) async {
      await tester.pumpWidget(
        themed(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(width: 320, child: composer()),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('first-run tags', () {
    Widget scoped(
      MemoryPreferencesStore store, {
      Map<PreferenceKey, String> initial = const {},
    }) => ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        preferencesStoreProvider.overrideWithValue(store),
        initialPreferencesProvider.overrideWithValue(initial),
      ],
      child: themed(composer()),
    );

    testWidgets('first-run tags show once', (tester) async {
      final store = MemoryPreferencesStore();
      await tester.pumpWidget(scoped(store));
      await tester.pump();

      expect(find.text('Tap to dictate'), findsOneWidget);
      expect(find.text('Talk hands-free'), findsOneWidget);
      expect(store.values[('', 'voice.tagsSeen')], 'true');

      // A later visit, with the saved choice loaded, shows none.
      await tester.pumpWidget(scoped(store, initial: {...store.values}));
      await tester.pump();
      expect(find.text('Tap to dictate'), findsNothing);
      expect(find.text('Talk hands-free'), findsNothing);
    });

    testWidgets('they go when the person starts typing', (tester) async {
      await tester.pumpWidget(scoped(MemoryPreferencesStore()));
      await tester.pump();
      text.text = 'h';
      await tester.pump();
      expect(find.text('Tap to dictate'), findsNothing);
    });

    testWidgets('they go by themselves after a while', (tester) async {
      await tester.pumpWidget(scoped(MemoryPreferencesStore()));
      await tester.pump();
      expect(find.text('Tap to dictate'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Tap to dictate'), findsNothing);
    });

    testWidgets('without voice mode there are no tags and no scope needed', (
      tester,
    ) async {
      await tester.pumpWidget(themed(composer(voiceMode: false)));
      expect(find.text('Tap to dictate'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('microphone access', () {
    late MemoryPreferencesStore store;
    late FakeMicPermission permission;
    MicAccess? outcome;

    /// A button that asks for access, so the sheets have a context to open on.
    Widget asker({Map<PreferenceKey, String> initial = const {}}) {
      outcome = null;
      return ProviderScope(
        overrides: <Override>[
          preferencesStoreProvider.overrideWithValue(store),
          initialPreferencesProvider.overrideWithValue(initial),
          micPermissionProvider.overrideWithValue(permission),
        ],
        child: themed(
          Builder(
            builder: (context) => Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                key: const ValueKey('ask'),
                onTap: () async => outcome = await ensureMicAccess(context),
                child: const SizedBox(width: 80, height: 80),
              ),
            ),
          ),
        ),
      );
    }

    setUp(() {
      store = MemoryPreferencesStore();
      permission = FakeMicPermission();
    });

    testWidgets('granted passes straight through', (tester) async {
      await tester.pumpWidget(asker());
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();

      expect(outcome, MicAccess.granted);
      expect(find.text('Iris needs your microphone'), findsNothing);
      expect(permission.requests, 0);
    });

    testWidgets('the first time shows the primer, then the system prompt', (
      tester,
    ) async {
      permission
        ..current = MicStatus.denied
        ..onRequest = MicStatus.granted;
      await tester.pumpWidget(asker());
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();

      expect(find.text('Iris needs your microphone'), findsOneWidget);
      expect(
        find.textContaining('Audio goes to your own Hermes server'),
        findsOneWidget,
      );
      expect(permission.requests, 0, reason: 'the primer comes first');

      await tester.tap(find.text('Allow microphone'));
      await tester.pumpAndSettle();

      expect(permission.requests, 1);
      expect(store.values[('', 'voice.micAsked')], 'true');
      expect(outcome, MicAccess.granted);
    });

    testWidgets('Not now on the primer asks for nothing', (tester) async {
      permission.current = MicStatus.denied;
      await tester.pumpWidget(asker());
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(outcome, MicAccess.denied);
      expect(permission.requests, 0);
      expect(store.values.containsKey(('', 'voice.micAsked')), isFalse);
    });

    testWidgets('a refusal at the system prompt shows the denied sheet', (
      tester,
    ) async {
      permission
        ..current = MicStatus.denied
        ..onRequest = MicStatus.denied;
      await tester.pumpWidget(asker());
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow microphone'));
      await tester.pumpAndSettle();

      expect(find.text('The microphone is off'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(outcome, MicAccess.denied);
    });

    testWidgets('revoked permission shows the denied sheet', (tester) async {
      // Asked before; the person has since turned it off in system settings.
      permission.current = MicStatus.denied;
      await tester.pumpWidget(asker(initial: {('', 'voice.micAsked'): 'true'}));
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();

      expect(find.text('The microphone is off'), findsOneWidget);
      expect(
        find.textContaining('Iris can’t hear you because access is blocked'),
        findsOneWidget,
      );
      expect(find.text('Settings › Iris › Microphone'), findsOneWidget);
      expect(find.text('Iris needs your microphone'), findsNothing);
      expect(permission.requests, 0);

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(permission.settingsOpened, 1);
      expect(outcome, MicAccess.denied);
    });

    testWidgets('without a provider scope the recorder decides', (
      tester,
    ) async {
      MicAccess? bare;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                key: const ValueKey('ask'),
                onTap: () async => bare = await ensureMicAccess(context),
                child: const SizedBox(width: 80, height: 80),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();
      expect(bare, MicAccess.granted);
    });

    testWidgets('both sheets fit at 320 pt and 200% text', (tester) async {
      // Sheets are pushed on the root navigator, above `home`, so the narrow
      // window and the large text have to be set outside the app.
      final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
      for (final asked in [false, true]) {
        store = MemoryPreferencesStore();
        permission = FakeMicPermission(current: MicStatus.denied);
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: <Override>[
              preferencesStoreProvider.overrideWithValue(store),
              initialPreferencesProvider.overrideWithValue({
                if (asked) ('', 'voice.micAsked'): 'true',
              }),
              micPermissionProvider.overrideWithValue(permission),
            ],
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      key: const ValueKey('ask'),
                      onTap: () => unawaited(ensureMicAccess(context)),
                      child: const SizedBox(width: 80, height: 80),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('ask')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'asked=$asked');
        expect(
          find.text(
            asked ? 'The microphone is off' : 'Iris needs your microphone',
          ),
          findsOneWidget,
        );
      }
    });
  });
}
