import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/decision_cards.dart';
import 'package:iris/features/chat/login_card.dart';

import '../support/harness.dart';

void main() {
  InputRequest request(
    InputKind kind, {
    String hint = '',
    String site = '',
    String command = '',
    String envVar = '',
    String prompt = '',
    String displayName = '',
  }) => InputRequest(
    requestId: 'srq',
    sessionId: 's',
    kind: kind,
    hint: hint,
    site: site,
    command: command,
    envVar: envVar,
    prompt: prompt,
    displayName: displayName,
  );

  Future<List<String>> pumpInput(WidgetTester tester, InputRequest r) async {
    final answers = <String>[];
    await tester.pumpWidget(
      themed(
        SingleChildScrollView(
          child: InputCard(request: r, onAnswer: (v) async => answers.add(v)),
        ),
      ),
    );
    return answers;
  }

  group('unlock', () {
    testWidgets('masked field, Unlock sends it, Skip sends nothing', (
      tester,
    ) async {
      final answers = await pumpInput(
        tester,
        request(InputKind.vaultUnlock, displayName: '1Password'),
      );
      expect(find.text('1Password is locked'), findsOneWidget);
      expect(find.text('NEEDS YOU · UNLOCK'), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      await tester.enterText(find.byType(EditableText), 'hunter2');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(answers, ['hunter2']);
    });

    testWidgets('Skip sends an empty value', (tester) async {
      final answers = await pumpInput(
        tester,
        request(InputKind.vaultUnlock, displayName: '1Password'),
      );
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(answers, ['']);
    });

    testWidgets('Unlock waits for text', (tester) async {
      await pumpInput(
        tester,
        request(InputKind.vaultUnlock, displayName: '1Password'),
      );
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);
    });
  });

  group('one-time code', () {
    testWidgets(
      'a six-digit hint gives six cells and sends on the sixth digit',
      (tester) async {
        final answers = await pumpInput(
          tester,
          request(
            InputKind.vaultCode,
            site: 'GitHub',
            hint: '6 digits from your authenticator app',
          ),
        );
        expect(find.text('Code for GitHub'), findsOneWidget);
        expect(find.byKey(const ValueKey('code-cell')), findsNWidgets(6));
        await tester.enterText(find.byType(EditableText), '48153');
        await tester.pump();
        expect(answers, isEmpty);
        await tester.enterText(find.byType(EditableText), '481532');
        await tester.pumpAndSettle();
        expect(answers, ['481532']);
      },
    );

    testWidgets('only digits are accepted in the cells', (tester) async {
      final answers = await pumpInput(
        tester,
        request(InputKind.vaultCode, hint: '6 digits'),
      );
      await tester.enterText(find.byType(EditableText), 'ab12');
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '12',
      );
      expect(answers, isEmpty);
    });

    testWidgets('any other hint gives one plain field that sends on Send', (
      tester,
    ) async {
      final answers = await pumpInput(
        tester,
        request(InputKind.vaultCode, hint: 'a backup code'),
      );
      expect(find.byKey(const ValueKey('code-cell')), findsNothing);
      await tester.enterText(find.byType(EditableText), 'abcd-1234');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(answers, ['abcd-1234']);
    });
  });

  group('sudo and secret', () {
    testWidgets('sudo shows the command in mono and uses Deny and Run', (
      tester,
    ) async {
      final answers = await pumpInput(
        tester,
        request(InputKind.sudo, command: 'systemctl restart hermes-worker'),
      );
      expect(find.text('NEEDS YOU · SUDO'), findsOneWidget);
      expect(find.text('Run this as root?'), findsOneWidget);
      expect(find.text('systemctl restart hermes-worker'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'pw');
      await tester.pump();
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(answers, ['pw']);
    });

    testWidgets(
      'secret names the variable and says it is stored on the server',
      (tester) async {
        final answers = await pumpInput(
          tester,
          request(
            InputKind.secret,
            envVar: 'OPENAI_API_KEY',
            prompt: 'Add a secret',
          ),
        );
        expect(find.text('NEEDS YOU · SECRET'), findsOneWidget);
        expect(find.text('OPENAI_API_KEY'), findsWidgets);
        expect(
          find.text('Stored on your server. Iris never shows it again.'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(EditableText), 'sk-123');
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(answers, ['sk-123']);
      },
    );
  });

  group('save login', () {
    testWidgets('username and masked password; Save sends both', (
      tester,
    ) async {
      String? id;
      String? pw;
      await tester.pumpWidget(
        themed(
          SingleChildScrollView(
            child: LoginCard(
              request: const LoginRequest(
                requestId: 'srq',
                sessionId: 's',
                origin: 'https://github.com',
                site: 'GitHub',
              ),
              onSave: (identifier, password) async {
                id = identifier;
                pw = password;
              },
              onSkip: () async {},
            ),
          ),
        ),
      );
      expect(find.text('Save to your password manager?'), findsOneWidget);
      expect(find.text('https://github.com'), findsOneWidget);
      final fields = find.byType(EditableText);
      expect(tester.widget<EditableText>(fields.at(1)).obscureText, isTrue);
      await tester.enterText(fields.at(0), 'jamie@hermes.dev');
      await tester.enterText(fields.at(1), 'hunter2');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((id, pw), ('jamie@hermes.dev', 'hunter2'));
    });

    testWidgets(
      'Save waits for both fields, and the password can be revealed',
      (tester) async {
        await tester.pumpWidget(
          themed(
            SingleChildScrollView(
              child: LoginCard(
                request: const LoginRequest(
                  requestId: 'srq',
                  sessionId: 's',
                  origin: 'https://github.com',
                ),
                onSave: (_, _) async {},
                onSkip: () async {},
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(EditableText).at(0), 'jamie');
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Show password'));
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).at(1))
              .obscureText,
          isFalse,
        );
      },
    );
  });
}
