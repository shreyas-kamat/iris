/// The push controller: what it tells the server and when. It never throws into the chat.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/push/push_api.dart';
import 'package:iris/data/push/push_controller.dart';
import 'package:iris/data/push/push_models.dart';

final class _RecordingApi implements PushApi {
  final calls = <String>[];
  Object? lastSettings;
  String? lastToken;
  String? lastPlatform;
  Result<void> result = const Ok(null);

  @override
  Future<Result<void>> register(
    String deviceId, {
    required String platform,
    String? apnsToken,
    required String appVersion,
    required PushSettings settings,
  }) async {
    calls.add('register:$deviceId');
    lastPlatform = platform;
    lastToken = apnsToken;
    lastSettings = settings;
    return result;
  }

  @override
  Future<Result<void>> updateSettings(
    String deviceId,
    PushSettings settings,
  ) async {
    calls.add('updateSettings:$deviceId');
    lastSettings = settings;
    return result;
  }

  @override
  Future<Result<void>> unregister(String deviceId) async {
    calls.add('unregister:$deviceId');
    return result;
  }

  @override
  Future<Result<void>> markActive(String storedSessionId) async {
    calls.add('markActive:$storedSessionId');
    return result;
  }

  @override
  Future<Result<void>> sendTest(String deviceId) async {
    calls.add('sendTest:$deviceId');
    return result;
  }
}

void main() {
  late _RecordingApi api;
  var enabled = true;
  var settings = PushSettings.defaults;
  String? token;

  PushController controller({String platform = 'android'}) => PushController(
    api,
    deviceId: 'dev1',
    platform: platform,
    appVersion: '1.0.0',
    enabled: () => enabled,
    settings: () => settings,
    apnsToken: () async => token,
  );

  setUp(() {
    api = _RecordingApi();
    enabled = true;
    settings = PushSettings.defaults;
    token = null;
  });

  group('markActive', () {
    test('tells the server the stored id once per call', () async {
      await controller().markActive('stored-1');
      expect(api.calls, ['markActive:stored-1']);
    });

    test('is skipped when push is off', () async {
      enabled = false;
      await controller().markActive('stored-1');
      expect(api.calls, isEmpty);
    });

    test('never throws, even when the server refuses', () async {
      api.result = const Err(IrisFailure(FailureKind.offline));
      await expectLater(controller().markActive('stored-1'), completes);
    });
  });

  group('setEnabled', () {
    test('on registers the device with its settings', () async {
      settings = settings.withEvent(
        PushEvent.reply,
        const PushEventSettings(on: true, text: 'Psst', mode: PushMode.text),
      );
      final result = await controller().setEnabled(on: true);
      expect(result.isOk, isTrue);
      expect(api.calls, ['register:dev1']);
      expect(api.lastPlatform, 'android');
      expect(
        (api.lastSettings! as PushSettings).of(PushEvent.reply).text,
        'Psst',
      );
    });

    test('on an iPhone sends the APNs token', () async {
      token = 'ab' * 32;
      await controller(platform: 'ios').setEnabled(on: true);
      expect(api.lastToken, 'ab' * 32);
      expect(api.lastPlatform, 'ios');
    });

    test('turning off unregisters', () async {
      enabled = false;
      final result = await controller().setEnabled(on: false);
      expect(result.isOk, isTrue);
      expect(api.calls, ['unregister:dev1']);
    });

    test('a failed registration is reported, not thrown', () async {
      api.result = const Err(IrisFailure(FailureKind.offline));
      final result = await controller().setEnabled(on: true);
      expect(result.isErr, isTrue);
    });
  });

  group('settings', () {
    test('a change is sent when push is on', () async {
      await controller().saveSettings();
      expect(api.calls, ['updateSettings:dev1']);
    });

    test('a change is kept locally when push is off', () async {
      enabled = false;
      await controller().saveSettings();
      expect(api.calls, isEmpty);
    });
  });

  test('a test notification is requested for this device', () async {
    final result = await controller(platform: 'ios').sendTest();
    expect(result.isOk, isTrue);
    expect(api.calls, ['sendTest:dev1']);
  });
}
