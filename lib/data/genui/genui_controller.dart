/// Decides whether a conversation gets generated displays, and tells the hermes-iris plugin so.
///
/// The plugin only offers `iris_ui` to sessions that are flagged, and it knows them by their **stored** id. Flagging is
/// idempotent, so the chat backend calls `flag` on every open, create, resume and reconnect rather than remembering
/// what it already sent.
library;

import '../../core/logging.dart';
import '../../core/result.dart';
import 'genui_api.dart';

final class GenUiController {
  GenUiController(this._api, {required bool Function() enabled})
    : _enabled = enabled;

  static const _log = IrisLog('genui');

  final GenUiApi _api;

  /// Read at every call: the person's switch for this server and profile, and a plugin that is confirmed on the
  /// server. A change in Settings applies from the next session that attaches.
  final bool Function() _enabled;

  /// Turns displays on for [storedSessionId] when they are enabled. Never throws: a refusal is logged and the chat
  /// carries on as plain text.
  Future<void> flag(String storedSessionId) async {
    if (!_enabled()) return;
    if (await _api.flagSession(storedSessionId) case Err(:final failure)) {
      _log.warn('could not flag a session', data: failure.kind.name);
    }
  }
}
