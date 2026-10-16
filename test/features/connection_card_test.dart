import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/connection_models.dart';
import 'package:iris/features/chat/connection_card.dart';

import '../support/harness.dart';

void main() {
  final now = DateTime(2026, 10, 16, 14);

  ConnectionRequest request({
    int seconds = 272,
    List<Map<String, Object?>>? targets,
  }) => ConnectionRequest.parse(
    Json.of({
      'op_id': 'op1',
      'timeout_seconds': seconds,
      'targets':
          targets ??
          [
            {
              'name': 'Linear',
              'kind': 'connector',
              'action': 'authorize',
              'state': 'pending',
              'connect_url': 'https://linear.app/oauth',
            },
            {
              'name': 'GitHub',
              'kind': 'mcp',
              'action': 'connect',
              'state': 'pending',
              'required_env': [
                {
                  'name': 'GITHUB_TOKEN',
                  'required': true,
                  'secret': true,
                  'default': '',
                  'prompt': 'Personal access token with repo scope.',
                },
              ],
            },
            {
              'name': 'release-notes',
              'kind': 'skill',
              'action': 'enable',
              'state': 'pending',
            },
            {
              'name': 'security-scan',
              'kind': 'plugin',
              'action': 'install',
              'state': 'pending',
            },
          ],
    }),
    sessionId: 's',
    now: now,
  )!;

  Future<void> pump(
    WidgetTester tester,
    ConnectionRequest r, {
    ValueChanged<TargetAnswer>? onAnswer,
    VoidCallback? onContinue,
    ValueChanged<ConnectionTarget>? onOpen,
    VoidCallback? onExpired,
  }) => tester.pumpWidget(
    themed(
      SingleChildScrollView(
        child: ConnectionCard(
          request: r,
          now: () => now,
          onAnswer: onAnswer ?? (_) {},
          onContinue: onContinue ?? () {},
          onOpenSignIn: onOpen ?? (_) {},
          onExpired: onExpired ?? () {},
        ),
      ),
    ),
  );

  Finder inRow(String target, Finder matching) => find.descendant(
    of: find.byKey(ValueKey('target-$target')),
    matching: matching,
  );

  testWidgets('a row per target with its kind, action and state chip', (
    tester,
  ) async {
    await pump(tester, request());
    expect(find.text('CONNECT · 4 ITEMS'), findsOneWidget);
    for (final name in ['Linear', 'GitHub', 'release-notes', 'security-scan']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('connector · authorise'), findsOneWidget);
    // IrisChip sets its label in caps.
    expect(find.text('PENDING'), findsNWidgets(4));
    expect(find.text('04:32'), findsOneWidget, reason: 'the countdown, mono');
  });

  testWidgets('sign-in opens the browser through the controller', (
    tester,
  ) async {
    ConnectionTarget? opened;
    await pump(tester, request(), onOpen: (t) => opened = t);
    await tester.tap(find.text('Open sign-in'));
    expect(opened?.name, 'Linear');
  });

  testWidgets(
    'after returning from sign-in the row waits for Hermes and offers Reopen',
    (tester) async {
      var opens = 0;
      await pump(tester, request(), onOpen: (_) => opens++);
      await tester.tap(find.text('Open sign-in'));
      await tester.pump();
      expect(find.text('Waiting for sign-in…'), findsOneWidget);
      await tester.tap(find.text('Reopen'));
      expect(opens, 2);
    },
  );

  testWidgets('a connected sign-in row stops waiting', (tester) async {
    await pump(tester, request());
    await tester.tap(find.text('Open sign-in'));
    await tester.pump();
    await pump(
      tester,
      request(
        targets: [
          {
            'name': 'Linear',
            'kind': 'connector',
            'action': 'authorize',
            'state': 'connected',
            'connect_url': 'https://linear.app/oauth',
          },
        ],
      ),
    );
    expect(find.text('Waiting for sign-in…'), findsNothing);
    expect(find.text('CONNECTED'), findsOneWidget);
  });

  testWidgets('credentials: masked field, hint, Approve sends the env', (
    tester,
  ) async {
    TargetAnswer? answered;
    await pump(tester, request(), onAnswer: (a) => answered = a);
    expect(find.text('GITHUB_TOKEN'), findsOneWidget);
    expect(find.text('Personal access token with repo scope.'), findsOneWidget);
    final field = inRow('GitHub', find.byType(EditableText));
    expect(tester.widget<EditableText>(field).obscureText, isTrue);
    await tester.enterText(field, 'ghp_x');
    await tester.pump();
    await tester.tap(inRow('GitHub', find.text('Approve')));
    expect(answered?.approved, isTrue);
    expect(answered?.env, {'GITHUB_TOKEN': 'ghp_x'});
  });

  testWidgets('Approve waits for the required values', (tester) async {
    TargetAnswer? answered;
    await pump(tester, request(), onAnswer: (a) => answered = a);
    await tester.tap(inRow('GitHub', find.text('Approve')));
    expect(answered, isNull);
  });

  testWidgets('an error from Hermes shows under the field', (tester) async {
    await pump(
      tester,
      request(
        targets: [
          {
            'name': 'GitHub',
            'kind': 'mcp',
            'action': 'connect',
            'state': 'failed',
            'detail': 'Token rejected · 401 Bad credentials',
            'required_env': [
              {'name': 'GITHUB_TOKEN', 'secret': true},
            ],
          },
        ],
      ),
    );
    expect(find.text('Token rejected · 401 Bad credentials'), findsOneWidget);
    expect(find.text('FAILED'), findsOneWidget);
  });

  testWidgets('enable is one tap, skip is one tap', (tester) async {
    final answers = <TargetAnswer>[];
    await pump(tester, request(), onAnswer: answers.add);
    await tester.tap(find.text('Enable'));
    expect(answers.single.name, 'release-notes');
    expect(answers.single.approved, isTrue);
  });

  testWidgets('desktop-only rows say so and can be skipped', (tester) async {
    final answers = <TargetAnswer>[];
    await pump(tester, request(), onAnswer: answers.add);
    expect(find.text('Finish this on Hermes Desktop'), findsOneWidget);
    // The four-row card is taller than the 600pt test window.
    await tester.ensureVisible(inRow('security-scan', find.text('Skip')));
    await tester.tap(inRow('security-scan', find.text('Skip')));
    expect(answers.single.name, 'security-scan');
    expect(answers.single.approved, isFalse);
  });

  testWidgets(
    'Continue is ghost while anything is pending and filled once settled',
    (tester) async {
      var continued = 0;
      await pump(tester, request(), onContinue: () => continued++);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      expect(
        continued,
        1,
        reason: 'Continue always works: open items count as skipped',
      );
      expect(find.byKey(const ValueKey('continue-ghost')), findsOneWidget);

      await pump(
        tester,
        request(
          targets: [
            {
              'name': 'Linear',
              'kind': 'connector',
              'action': 'authorize',
              'state': 'connected',
            },
          ],
        ),
      );
      expect(find.byKey(const ValueKey('continue-filled')), findsOneWidget);
    },
  );

  testWidgets('an unrecognised target falls back to desktop-only', (
    tester,
  ) async {
    await pump(
      tester,
      request(
        targets: [
          {
            'name': 'Mystery',
            'kind': 'teleporter',
            'action': 'beam',
            'state': 'glowing',
          },
        ],
      ),
    );
    expect(find.text('Finish this on Hermes Desktop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deadline already past reports expiry once', (tester) async {
    var expired = 0;
    await pump(tester, request(seconds: 0), onExpired: () => expired++);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(expired, 1);
  });

  testWidgets('the countdown ticks and reports expiry when it reaches zero', (
    tester,
  ) async {
    var clockNow = now;
    var expired = 0;
    await tester.pumpWidget(
      themed(
        SingleChildScrollView(
          child: ConnectionCard(
            request: request(seconds: 2),
            now: () => clockNow,
            onAnswer: (_) {},
            onContinue: () {},
            onOpenSignIn: (_) {},
            onExpired: () => expired++,
          ),
        ),
      ),
    );
    expect(find.text('00:02'), findsOneWidget);
    clockNow = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(expired, 1);
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('no overflow at 320pt and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      themed(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: SingleChildScrollView(
            child: ConnectionCard(
              request: request(),
              now: () => now,
              onAnswer: (_) {},
              onContinue: () {},
              onOpenSignIn: (_) {},
              onExpired: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
