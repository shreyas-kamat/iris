/// Keeping the screen on while the call screen is showing.
library;

import 'package:wakelock_plus/wakelock_plus.dart';

/// The one seam to the platform's screen wake lock, so the call screen can be
/// tested without a platform channel.
abstract interface class ScreenAwake {
  Future<void> hold();
  Future<void> release();
}

final class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> hold() => WakelockPlus.enable();

  @override
  Future<void> release() => WakelockPlus.disable();
}
