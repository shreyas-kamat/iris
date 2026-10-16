import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';

import '../support/fake_chat_backend.dart';
import '../support/fakes.dart';

void main() {
  test('only replying sessions are live, keyed by stored id', () async {
    final backend = FakeChatBackend()
      ..activeResult = const Ok([
        LiveStatus(runtimeId: 'r1', storedId: 's1', status: 'working'),
        LiveStatus(runtimeId: 'r2', storedId: 's2', status: 'idle'),
        LiveStatus(runtimeId: 'r3', storedId: 's3', status: 'waiting'),
      ]);
    final container = ProviderContainer(
      overrides: [
        activeChatProvider.overrideWith((ref) async => backend),
        liveIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(liveChatsProvider, (_, _) {});
    final live = await container.read(liveChatsProvider.future);
    expect(live.keys, {'s1', 's3'});
    expect(live['s3']!.waiting, isTrue);
  });

  test(
    'a server without session.active_list simply has nothing live',
    () async {
      final backend = FakeChatBackend();
      // IrisFailure with an RpcError(isMethodNotFound): build it the way
      // test/data/rpc_client_test.dart does for "unknown method".
      backend.activeResult = Err(unknownMethod('session.active_list'));
      final container = ProviderContainer(
        overrides: [
          activeChatProvider.overrideWith((ref) async => backend),
          liveIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(liveChatsProvider, (_, _) {});
      expect(await container.read(liveChatsProvider.future), isEmpty);
    },
  );

  test(
    'a server without session.active_list is asked once, not every 15 s',
    () async {
      final backend = FakeChatBackend()
        ..activeResult = Err(unknownMethod('session.active_list'));
      final container = ProviderContainer(
        overrides: [
          activeChatProvider.overrideWith((ref) async => backend),
          liveIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(liveChatsProvider, (_, _) {});
      await container.read(liveChatsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(backend.activeCalls, 1);
    },
  );
}
