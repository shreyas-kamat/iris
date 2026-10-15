/// The demo replaces the active server, link and chat, and nothing else.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/demo/demo_chat_backend.dart';
import 'package:iris/demo/demo_mode.dart';

import '../support/fakes.dart';

void main() {
  late IrisDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = IrisDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        credentialStoreProvider.overrideWithValue(FakeCredentialStore()),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('off by default: no server, an idle link, no chat', () async {
    final link = container.listen(activeLinkProvider, (_, _) {});
    addTearDown(link.close);
    final chat = container.listen(activeChatProvider, (_, _) {});
    addTearDown(chat.close);
    expect(container.read(demoModeProvider), isFalse);
    expect(container.read(activeServerProvider), isNull);
    expect(
      (await container.read(activeLinkProvider.future)).phase,
      LinkPhase.idle,
    );
    expect(await container.read(activeChatProvider.future), isNull);
  });

  test(
    'on: the demo server, a live link, a demo chat and no session',
    () async {
      container.read(demoSessionProvider.notifier).enter();
      final link = container.listen(activeLinkProvider, (_, _) {});
      addTearDown(link.close);
      final chat = container.listen(activeChatProvider, (_, _) {});
      addTearDown(chat.close);
      final session = container.listen(activeSessionProvider, (_, _) {});
      addTearDown(session.close);

      expect(container.read(demoModeProvider), isTrue);
      expect(container.read(activeServerProvider), demoServer);
      expect(
        (await container.read(activeLinkProvider.future)).phase,
        LinkPhase.live,
      );
      expect(
        await container.read(activeChatProvider.future),
        isA<DemoChatBackend>(),
      );
      expect(await container.read(activeSessionProvider.future), isNull);
    },
  );

  test('leaving puts everything back', () async {
    final notifier = container.read(demoSessionProvider.notifier)..enter();
    final chat = container.listen(activeChatProvider, (_, _) {});
    addTearDown(chat.close);
    await container.read(activeChatProvider.future);
    notifier.leave();
    expect(container.read(demoModeProvider), isFalse);
    expect(container.read(activeServerProvider), isNull);
    expect(await container.read(activeChatProvider.future), isNull);
  });
}
