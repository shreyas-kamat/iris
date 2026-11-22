/// Marking the chat the person just sent to as active, through the chat backend: the server's hooks know the stored
/// id, a send names the runtime one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/push/push_api.dart';
import 'package:iris/data/push/push_controller.dart';
import 'package:iris/data/push/push_models.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

void main() {
  late FakeHttp http;
  late FakeWireSocket socket;
  late DashboardSession session;
  late DashboardChat chat;
  var on = true;

  setUp(() async {
    on = true;
    http = FakeHttp()
      ..on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => FakeReply.json({'ticket': 't'}),
      )
      ..on(
        'POST',
        '/api/plugins/iris/push/active/stored-1',
        (_) => FakeReply.json({'ok': true}),
      )
      ..on(
        'POST',
        '/api/plugins/iris/push/active/st-2',
        (_) => FakeReply.json({'ok': true}),
      );
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'H'),
      adapter: http,
    );
    session = DashboardSession(
      http: connection,
      backoff: (_) => Duration.zero,
      connector: (uri, headers) async => socket = FakeWireSocket(),
    );
    await session.start();
    chat = DashboardChat(
      session,
      push: PushController(
        DashboardPushApi(connection.client),
        deviceId: 'dev1',
        platform: 'android',
        appVersion: '1.0.0',
        enabled: () => on,
        settings: () => PushSettings.defaults,
      ),
    );
    addTearDown(() async {
      await chat.dispose();
      await session.dispose();
      connection.close();
    });
  });

  Future<void> answer(Object? result) async {
    await Future<void>.delayed(Duration.zero);
    socket.replyToLast(result: result);
  }

  Future<void> resume() async {
    final future = chat.resume('stored-1');
    await answer({'session_id': 'run-1'});
    await future;
  }

  Future<void> send(String runtimeId) async {
    final future = chat.submit(runtimeId, 'hello');
    await answer({'status': 'streaming'});
    await future;
    // The mark is fire-and-forget: give its request time to reach the fake server.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('a send marks the stored chat active, once', () async {
    await resume();
    await send('run-1');
    expect(http.to('/api/plugins/iris/push/active/stored-1').length, 1);
  });

  test('every send marks it again', () async {
    await resume();
    await send('run-1');
    await send('run-1');
    expect(http.to('/api/plugins/iris/push/active/stored-1').length, 2);
  });

  test('a new conversation is marked by its stored id', () async {
    final future = chat.create();
    await answer({'session_id': 'run-2', 'stored_session_id': 'st-2'});
    await future;
    await send('run-2');
    expect(http.to('/api/plugins/iris/push/active/st-2').length, 1);
  });

  test('nothing is sent while notifications are off', () async {
    on = false;
    await resume();
    await send('run-1');
    expect(http.to('/api/plugins/iris/push/active/stored-1'), isEmpty);
  });

  test('a send to a chat this backend never opened marks nothing', () async {
    await send('run-unknown');
    expect(
      http.requests.where((r) => r.uri.path.contains('/push/active/')),
      isEmpty,
    );
  });

  test('the message still goes out when the server refuses the mark', () async {
    http.on(
      'POST',
      '/api/plugins/iris/push/active/stored-1',
      (_) => FakeReply.json({'detail': 'no'}, status: 500),
    );
    await resume();
    final future = chat.submit('run-1', 'hello');
    await answer({'status': 'streaming'});
    expect((await future).isOk, isTrue);
  });
}
