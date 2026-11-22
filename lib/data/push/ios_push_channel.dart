/// iOS push from Dart: the `iris/push` channel to `AppDelegate.swift`.
///
/// Dart → iOS: `requestPermission` (asks once, then registers with APNs), `token` (the hex APNs token, or null before
/// one arrives), `setForegroundChat` (no banner for that chat while it is on screen), `ready` (deliver taps held since
/// launch). iOS → Dart: `token` (a new token), `tap` (the notice's `iris` fields, plus `action` for an approval button
/// and `command`, the text it showed).
///
/// Nothing here throws: without the native side (tests, Android) every call is a quiet no.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/logging.dart';
import 'push_intents.dart';

final class IosPushChannel {
  IosPushChannel({
    required void Function(String token) onToken,
    required void Function(PushTap tap) onTap,
    MethodChannel channel = const MethodChannel('iris/push'),
  }) : _onToken = onToken,
       _onTap = onTap,
       _channel = channel;

  static const _log = IrisLog('push.ios');

  final void Function(String) _onToken;
  final void Function(PushTap) _onTap;
  final MethodChannel _channel;
  String? _token;

  /// Starts listening, then tells iOS to deliver what it held (a tap that launched the app).
  Future<void> attach() async {
    _channel.setMethodCallHandler(_handle);
    await _invoke<void>('ready');
  }

  void detach() => _channel.setMethodCallHandler(null);

  /// Asks for permission to alert (the system asks only the first time) and registers with APNs when granted.
  Future<bool> requestPermission() async =>
      await _invoke<bool>('requestPermission') ?? false;

  /// The APNs token, once iOS has one.
  Future<String?> token() async => _token ??= await _invoke<String>('token');

  Future<void> setForegroundChat(String? storedId) =>
      _invoke<void>('setForegroundChat', storedId);

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      _log.warn('push channel', data: '$method ${error.code}');
      return null;
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'token':
        final token = call.arguments;
        if (token is String && token.isNotEmpty) {
          _token = token;
          _onToken(token);
        }
      case 'tap':
        final arguments = call.arguments;
        if (arguments is Map) {
          final tap = PushTap.fromPayload(arguments.cast<String, Object?>());
          if (tap != null) _onTap(tap);
        }
      case 'tokenError':
        _log.warn('APNs registration failed', data: call.arguments);
    }
    return null;
  }
}
