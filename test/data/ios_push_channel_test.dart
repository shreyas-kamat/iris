/// The iOS side of push, through the `iris/push` method channel (native side mocked): the APNs token reaches the
/// server's registration, a tap (or an approval button) opens the right thing, and the chat on screen is passed down
/// so its notifications are not shown.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/push/ios_push_channel.dart';
import 'package:iris/data/push/push_api.dart';
import 'package:iris/data/push/push_controller.dart';
import 'package:iris/data/push/push_intents.dart';
import 'package:iris/data/push/push_models.dart';

const _channel = MethodChannel('iris/push');

final class _Api implements PushApi {
  final tokens = <String?>[];

  @override
  Future<Result<void>> register(
    String deviceId, {
    required String platform,
    String? apnsToken,
    required String appVersion,
    required PushSettings settings,
  }) async {
    tokens.add(apnsToken);
    return const Ok(null);
  }

  @override
  Future<Result<void>> markActive(String storedSessionId) async =>
      const Ok(null);

  @override
  Future<Result<void>> sendTest(String deviceId) async => const Ok(null);

  @override
  Future<Result<void>> unregister(String deviceId) async => const Ok(null);

  @override
  Future<Result<void>> updateSettings(
    String deviceId,
    PushSettings settings,
  ) async => const Ok(null);
}

/// Plays the native side: answers Dart's calls, and can call into Dart as iOS would.
final class _Native {
  _Native() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'requestPermission' => granted,
            'token' => token,
            _ => null,
          };
        });
  }

  final calls = <MethodCall>[];
  bool granted = true;
  String? token;

  /// iOS calling Dart.
  Future<void> send(String method, Object? arguments) async {
    final codec = const StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
  }

  void dispose() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Native native;
  late List<PushTap> taps;
  late List<String> tokens;
  late IosPushChannel push;

  setUp(() {
    native = _Native();
    taps = [];
    tokens = [];
    push = IosPushChannel(onToken: tokens.add, onTap: taps.add);
  });

  tearDown(() {
    push.detach();
    native.dispose();
  });

  test(
    'attach tells the native side Dart is ready for buffered taps',
    () async {
      await push.attach();
      expect(native.calls.map((c) => c.method), ['ready']);
    },
  );

  test(
    'token → register: a new APNs token is sent with the registration',
    () async {
      final api = _Api();
      late final IosPushChannel syncing;
      final controller = PushController(
        api,
        deviceId: 'd1',
        platform: 'ios',
        appVersion: '1.0.0',
        enabled: () => true,
        settings: () => PushSettings.defaults,
        apnsToken: () => syncing.token(),
      );
      syncing = IosPushChannel(
        onToken: (_) => controller.sync(),
        onTap: taps.add,
      );
      push.detach();
      await syncing.attach();

      await native.send('token', 'ab12cd');
      await pumpEventQueue();
      expect(api.tokens, ['ab12cd']);
      syncing.detach();
    },
  );

  test(
    'token() asks the native side once, then keeps what it learnt',
    () async {
      await push.attach();
      native.token = 'ff00';
      expect(await push.token(), 'ff00');
      await native.send('token', 'ee11');
      expect(tokens, ['ee11']);
      native.calls.clear();
      expect(await push.token(), 'ee11');
      expect(native.calls, isEmpty);
    },
  );

  test('requestPermission passes the answer back', () async {
    await push.attach();
    expect(await push.requestPermission(), isTrue);
    native.granted = false;
    expect(await push.requestPermission(), isFalse);
  });

  test('tap → PushRouter.open: a plain tap names the chat', () async {
    await push.attach();
    await native.send('tap', {
      'kind': 'reply',
      'session_id': 's1',
      'event_id': '4',
    });
    expect(taps.single.kind, 'reply');
    expect(taps.single.sessionId, 's1');
    expect(taps.single.action, isNull);
  });

  test('an approval button carries its action and the command shown', () async {
    await push.attach();
    await native.send('tap', {
      'kind': 'approval',
      'session_id': 's1',
      'action': 'once',
      'command': 'rm -rf build',
    });
    expect(taps.single.action, 'once');
    expect(taps.single.command, 'rm -rf build');
  });

  test('a tap that names nothing is dropped', () async {
    await push.attach();
    await native.send('tap', {'kind': 'reply'});
    await native.send('tap', 'nonsense');
    expect(taps, isEmpty);
  });

  test('the chat on screen is passed down, and cleared', () async {
    await push.attach();
    await push.setForegroundChat('s1');
    await push.setForegroundChat(null);
    final sent = native.calls.where((c) => c.method == 'setForegroundChat');
    expect(sent.map((c) => c.arguments), ['s1', null]);
  });

  test('a native side that is missing is not an error', () async {
    native.dispose();
    await push.attach();
    expect(await push.requestPermission(), isFalse);
    expect(await push.token(), isNull);
    await push.setForegroundChat('s1');
  });
}
