/// Turning generated displays on for a conversation: the controller's rule, and the chat backend flagging a session
/// whenever it opens, is created or is resumed (which includes every reconnect).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/genui/genui_api.dart';
import 'package:iris/data/genui/genui_controller.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_genui_api.dart';
import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

/// Records the sessions it was asked to flag.
final class _RecordingApi extends FakeGenUiApi {
  final flagged = <String>[];
  Result<void> flagResult = const Ok(null);

  @override
  Future<Result<void>> flagSession(String sessionId) async {
    flagged.add(sessionId);
    return flagResult;
  }

  @override
  Future<Result<GenUiCapabilities>> capabilities() =>
      throw UnimplementedError();

  @override
  Future<Result<UiSurface>> surface(String sessionId, String surfaceId) =>
      throw UnimplementedError();

  @override
  Future<Result<List<UiSurface>>> surfaces(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> unflagSession(String sessionId) =>
      throw UnimplementedError();
}

void main() {
  group('GenUiController', () {
    test('flags the stored session when displays are on', () async {
      final api = _RecordingApi();
      await GenUiController(api, enabled: () => true).flag('stored-1');
      expect(api.flagged, ['stored-1']);
    });

    test('does nothing when displays are off', () async {
      final api = _RecordingApi();
      await GenUiController(api, enabled: () => false).flag('stored-1');
      expect(api.flagged, isEmpty);
    });

    test('reads the switch each time, so a change applies at once', () async {
      final api = _RecordingApi();
      var on = false;
      final controller = GenUiController(api, enabled: () => on);
      await controller.flag('a');
      on = true;
      await controller.flag('b');
      expect(api.flagged, ['b']);
    });

    test('sends again after a reconnect (flagging is idempotent)', () async {
      final api = _RecordingApi();
      final controller = GenUiController(api, enabled: () => true);
      await controller.flag('stored-1');
      await controller.flag('stored-1');
      expect(api.flagged, ['stored-1', 'stored-1']);
    });

    test(
      'a refusal never throws: the chat carries on without displays',
      () async {
        final api = _RecordingApi()
          ..flagResult = const Err(IrisFailure(FailureKind.notFound));
        await expectLater(
          GenUiController(api, enabled: () => true).flag('stored-1'),
          completes,
        );
      },
    );
  });

  group('DashboardChat', () {
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
          '/api/plugins/iris/sessions/stored-1/genui',
          (_) => FakeReply.json({'ok': true}),
        )
        ..on(
          'POST',
          '/api/plugins/iris/sessions/st-2/genui',
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
        genUi: GenUiController(
          DashboardGenUiApi(connection.client),
          enabled: () => on,
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

    test('resume flags the stored session', () async {
      final future = chat.resume('stored-1');
      await answer({'session_id': 'run-1'});
      expect((await future).isOk, isTrue);
      expect(http.to('/api/plugins/iris/sessions/stored-1/genui').length, 1);
    });

    test('a second resume (after a reconnect) flags it again', () async {
      for (var i = 0; i < 2; i++) {
        final future = chat.resume('stored-1');
        await answer({'session_id': 'run-1'});
        await future;
      }
      expect(http.to('/api/plugins/iris/sessions/stored-1/genui').length, 2);
    });

    test('create flags the new stored session before it returns', () async {
      final future = chat.create();
      await answer({'session_id': 'run-2', 'stored_session_id': 'st-2'});
      expect((await future).isOk, isTrue);
      expect(http.to('/api/plugins/iris/sessions/st-2/genui').length, 1);
    });

    test('nothing is sent while displays are off', () async {
      on = false;
      final future = chat.resume('stored-1');
      await answer({'session_id': 'run-1'});
      await future;
      expect(http.to('/api/plugins/iris/sessions/stored-1/genui'), isEmpty);
    });

    test('a failed resume flags nothing', () async {
      final future = chat.resume('stored-1');
      await Future<void>.delayed(Duration.zero);
      socket.replyToLast(error: {'code': 4001, 'message': 'gone'});
      await future;
      expect(http.to('/api/plugins/iris/sessions/stored-1/genui'), isEmpty);
    });
  });
}
