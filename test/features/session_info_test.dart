import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/chat/session_info_sheet.dart';

import '../support/harness.dart';

void main() {
  Future<void> open(WidgetTester tester, SessionInfo info) async {
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showSessionInfo(context, info),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows what is known and leaves out what is not', (tester) async {
    await open(
      tester,
      const SessionInfo(
        title: 'Investigate heartbeat gaps',
        profile: 'default',
        model: 'opus-4.5',
        messages: 18,
        contextPercent: 42,
        contextUsed: 61200,
        contextMax: 200000,
        sessionId: 'sess_01JB8K2Q7M4X9V3N6T',
      ),
    );
    expect(find.text('default'), findsOneWidget);
    expect(find.text('opus-4.5'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('42% · 61.2k of 200k'), findsOneWidget);
    expect(find.text('sess_01JB8K2Q7M4X9V3N6T'), findsOneWidget);
    expect(find.text('Last active'), findsNothing);
  });

  testWidgets('a brand-new chat has no id yet and says nothing about one', (
    tester,
  ) async {
    await open(
      tester,
      const SessionInfo(title: 'New conversation', profile: 'default'),
    );
    expect(find.text('Session id'), findsNothing);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('Copy puts the id on the clipboard and says so', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(
      tester,
      const SessionInfo(title: 't', profile: 'default', sessionId: 'sess_1'),
    );
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'sess_1');
    expect(find.text('Copied session id'), findsOneWidget);
  });

  test('compactTokens', () {
    expect(compactTokens(950), '950');
    expect(compactTokens(61200), '61.2k');
    expect(compactTokens(200000), '200k');
    expect(compactTokens(1250000), '1.3M');
  });
}
