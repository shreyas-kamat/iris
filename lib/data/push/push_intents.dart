/// What a tap on a notification (or one of its buttons) asks Iris to do, read from the payload the server sent.
///
/// Android carries the payload as a JSON string on a local notification; iOS delivers the APNs `userInfo`, where the
/// plugin's own fields sit under `iris`. Either way the fields are the notice's: `kind`, `session_id` (the stored id),
/// `event_id`.
library;

import 'dart:convert';

final class PushTap {
  const PushTap({
    required this.kind,
    required this.sessionId,
    this.eventId,
    this.action,
    this.command,
  });

  /// `reply`, `approval`, `job` (or `test`, which opens nothing).
  final String kind;

  /// The stored id of the chat, or the `cron_<job id>_<date>_<time>` id of a job's run.
  final String sessionId;
  final String? eventId;

  /// The button pressed on an approval: `once` or `deny`. Null for a plain tap.
  final String? action;

  /// What the notification showed for an approval (the command, when the person chose to see it). Used only to pick
  /// the right one when more than one is waiting.
  final String? command;

  /// The actions a notification offers. Anything else is dropped: session and always stay in the app.
  static const actions = {'once', 'deny'};

  static final _cronSession = RegExp(r'^cron_(.+)_\d{8}_\d{4,6}$');

  /// The scheduled job behind a [kind] `job` notice, read from its run's session id.
  String? get jobId => _cronSession.firstMatch(sessionId)?.group(1);

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Null when there is nothing to open (no kind or no session).
  static PushTap? fromPayload(Map<String, Object?> payload) {
    final nested = payload['iris'];
    final source = nested is Map ? nested.cast<String, Object?>() : payload;
    final kind = _text(source['kind']);
    final session = _text(source['session_id']);
    if (kind == null || session == null) return null;
    final action = _text(source['action']);
    return PushTap(
      kind: kind,
      sessionId: session,
      eventId: _text(source['event_id']),
      action: actions.contains(action) ? action : null,
      command: _text(source['command']),
    );
  }

  /// [payload] as a local notification carries it: a JSON object in a string.
  static PushTap? fromJsonString(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map
          ? fromPayload(decoded.cast<String, Object?>())
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PushTap &&
      other.kind == kind &&
      other.sessionId == sessionId &&
      other.eventId == eventId &&
      other.action == action &&
      other.command == command;

  @override
  int get hashCode => Object.hash(kind, sessionId, eventId, action, command);
}
