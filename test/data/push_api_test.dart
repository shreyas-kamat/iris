/// The hermes-iris plugin's push routes: paths, bodies and the `?profile=` query, and the settings model that goes
/// over the wire (its defaults equal the server's).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/push/push_api.dart';
import 'package:iris/data/push/push_models.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;

  setUp(() => http = FakeHttp());

  DashboardPushApi api({String profile = 'default'}) {
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
      adapter: http,
    );
    addTearDown(connection.close);
    return DashboardPushApi(connection.client, profile: profile);
  }

  group('PushSettings', () {
    test('defaults equal the server\'s', () {
      final defaults = PushSettings.defaults;
      expect(defaults.of(PushEvent.reply).on, isTrue);
      expect(defaults.of(PushEvent.reply).text, 'Attention!');
      expect(defaults.of(PushEvent.reply).mode, PushMode.text);
      expect(defaults.of(PushEvent.approval).mode, PushMode.content);
      expect(defaults.of(PushEvent.job).mode, PushMode.content);
    });

    test('round-trips through JSON', () {
      final settings = PushSettings.defaults.withEvent(
        PushEvent.job,
        const PushEventSettings(
          on: false,
          text: 'Done 🎉 "quoted"',
          mode: PushMode.text,
        ),
      );
      expect(PushSettings.fromJson(settings.toJson()), settings);
      expect(settings.toJson()['job'], {
        'on': false,
        'text': 'Done 🎉 "quoted"',
        'mode': 'text',
      });
    });

    test('missing or odd fields fall back to the defaults', () {
      final read = PushSettings.fromJson({
        'reply': {'on': 'yes', 'text': 5, 'mode': 'loud'},
        'approval': {'text': 'Look'},
      });
      expect(
        read.of(PushEvent.reply),
        PushSettings.defaults.of(PushEvent.reply),
      );
      expect(read.of(PushEvent.approval).text, 'Look');
      expect(read.of(PushEvent.approval).mode, PushMode.content);
      expect(read.of(PushEvent.job), PushSettings.defaults.of(PushEvent.job));
    });

    test('the text is trimmed to 100 characters and never empty', () {
      final long = 'a' * 130;
      expect(PushEventSettings.cleanText(long), hasLength(100));
      expect(PushEventSettings.cleanText('   '), 'Attention!');
      expect(PushEventSettings.cleanText('  hi  '), 'hi');
    });
  });

  group('DashboardPushApi', () {
    test('registers a device with its platform, token and settings', () async {
      http.on(
        'PUT',
        '/api/plugins/iris/push/devices/dev1',
        (_) => FakeReply.json({'ok': true}),
      );
      final result = await api(profile: 'research').register(
        'dev1',
        platform: 'ios',
        apnsToken: 'ab' * 32,
        appVersion: '1.0.0',
        settings: PushSettings.defaults,
      );
      expect(result.isOk, isTrue);
      final request = http.requests.single;
      expect(request.uri.queryParameters['profile'], 'research');
      final body = request.data as Map;
      expect(body['platform'], 'ios');
      expect(body['apns_token'], 'ab' * 32);
      expect(body['app_version'], '1.0.0');
      expect((body['settings'] as Map)['reply'], {
        'on': true,
        'text': 'Attention!',
        'mode': 'text',
      });
    });

    test('an Android registration sends no token', () async {
      http.on(
        'PUT',
        '/api/plugins/iris/push/devices/dev1',
        (_) => FakeReply.json({'ok': true}),
      );
      await api().register(
        'dev1',
        platform: 'android',
        appVersion: '1.0.0',
        settings: PushSettings.defaults,
      );
      expect(
        (http.requests.single.data as Map).containsKey('apns_token'),
        isFalse,
      );
      expect(http.requests.single.uri.queryParameters, isEmpty);
    });

    test('updates settings with a PATCH of the whole object', () async {
      http.on(
        'PATCH',
        '/api/plugins/iris/push/devices/dev1/settings',
        (_) => FakeReply.json({'ok': true, 'settings': <String, Object?>{}}),
      );
      final result = await api().updateSettings('dev1', PushSettings.defaults);
      expect(result.isOk, isTrue);
      expect((http.requests.single.data as Map).keys, [
        'reply',
        'approval',
        'job',
      ]);
    });

    test('unregisters with a DELETE', () async {
      http.on(
        'DELETE',
        '/api/plugins/iris/push/devices/dev1',
        (_) => FakeReply.json({'ok': true, 'deleted': true}),
      );
      expect((await api().unregister('dev1')).isOk, isTrue);
    });

    test('marks a chat active by its stored id', () async {
      http.on(
        'POST',
        '/api/plugins/iris/push/active/20261113_101500_ab12cd',
        (_) => FakeReply.json({'ok': true}),
      );
      final result = await api().markActive('20261113_101500_ab12cd');
      expect(result.isOk, isTrue);
    });

    test('sends a test notification', () async {
      http.on(
        'POST',
        '/api/plugins/iris/push/test/dev1',
        (_) => FakeReply.json({'ok': true, 'result': 'ok'}),
      );
      expect((await api().sendTest('dev1')).isOk, isTrue);
    });

    test('a test the server could not deliver is a failure', () async {
      http.on(
        'POST',
        '/api/plugins/iris/push/test/dev1',
        (_) => FakeReply.json({'ok': false, 'result': 'fail'}),
      );
      expect((await api().sendTest('dev1')).isErr, isTrue);
    });

    test('a server without the plugin answers 404 as a failure', () async {
      final result = await api().markActive('s1');
      expect(result.failureOrNull?.kind, FailureKind.notFound);
    });
  });
}
