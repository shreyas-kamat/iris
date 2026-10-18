/// The microphone permission, behind a seam so the sheets and the call can be
/// tested without a phone.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

/// What the system says about the microphone. Iris only needs two answers:
/// it may record, or it may not (never asked, asked and refused, or turned
/// off since).
enum MicStatus { granted, denied }

abstract interface class MicPermission {
  /// The current state, without asking.
  Future<MicStatus> status();

  /// Shows the system prompt, once the person has said they are ready.
  Future<MicStatus> request();

  /// Opens this app's page in system Settings.
  Future<void> openSettings();
}

/// The real permission, through `permission_handler`.
final class PermissionHandlerMic implements MicPermission {
  const PermissionHandlerMic();

  static MicStatus _map(handler.PermissionStatus status) =>
      status.isGranted ? MicStatus.granted : MicStatus.denied;

  @override
  Future<MicStatus> status() async =>
      _map(await handler.Permission.microphone.status);

  @override
  Future<MicStatus> request() async =>
      _map(await handler.Permission.microphone.request());

  @override
  Future<void> openSettings() async {
    await handler.openAppSettings();
  }
}

final micPermissionProvider = Provider<MicPermission>(
  (ref) => const PermissionHandlerMic(),
);
