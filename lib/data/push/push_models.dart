/// What the person asked to be told about, in their own words. The server holds the same settings per device and
/// renders every notice from them, so a device in [PushMode.text] never receives content.
library;

import 'dart:convert';

/// The three things worth a notification.
enum PushEvent {
  /// A reply in a chat the person is waiting on.
  reply,

  /// The agent waits for an approval.
  approval,

  /// A scheduled job finished.
  job,
}

/// What a notification shows besides the person's own words.
enum PushMode {
  /// The person's text as the title, a line of what happened as the body.
  content,

  /// Only the person's text; nothing about the event leaves the server for this device.
  text;

  String get wire => name;

  static PushMode? fromWire(Object? value) =>
      value is String ? PushMode.values.asNameMap()[value] : null;
}

final class PushEventSettings {
  const PushEventSettings({
    required this.on,
    required this.text,
    required this.mode,
  });

  static const defaultText = 'Attention!';
  static const maxText = 100;

  final bool on;
  final String text;
  final PushMode mode;

  /// [raw] as the server stores it: trimmed, at most [maxText] characters, never empty.
  static String cleanText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return defaultText;
    final cut = trimmed.runes.length > maxText
        ? String.fromCharCodes(trimmed.runes.take(maxText))
        : trimmed;
    return cut.trimRight();
  }

  PushEventSettings copyWith({bool? on, String? text, PushMode? mode}) =>
      PushEventSettings(
        on: on ?? this.on,
        text: text ?? this.text,
        mode: mode ?? this.mode,
      );

  Map<String, Object?> toJson() => {'on': on, 'text': text, 'mode': mode.wire};

  /// [json] over [fallback]: a field that is missing or the wrong type keeps the fallback's value.
  static PushEventSettings read(Object? json, PushEventSettings fallback) {
    if (json is! Map) return fallback;
    final on = json['on'];
    final text = json['text'];
    return PushEventSettings(
      on: on is bool ? on : fallback.on,
      text: text is String ? cleanText(text) : fallback.text,
      mode: PushMode.fromWire(json['mode']) ?? fallback.mode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PushEventSettings &&
      other.on == on &&
      other.text == text &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(on, text, mode);
}

final class PushSettings {
  const PushSettings(this.events);

  /// The server's defaults.
  static const defaults = PushSettings({
    PushEvent.reply: PushEventSettings(
      on: true,
      text: PushEventSettings.defaultText,
      mode: PushMode.text,
    ),
    PushEvent.approval: PushEventSettings(
      on: true,
      text: PushEventSettings.defaultText,
      mode: PushMode.content,
    ),
    PushEvent.job: PushEventSettings(
      on: true,
      text: PushEventSettings.defaultText,
      mode: PushMode.content,
    ),
  });

  final Map<PushEvent, PushEventSettings> events;

  PushEventSettings of(PushEvent event) =>
      events[event] ?? defaults.events[event]!;

  PushSettings withEvent(PushEvent event, PushEventSettings settings) =>
      PushSettings({...events, event: settings});

  Map<String, Object?> toJson() => {
    for (final event in PushEvent.values) event.name: of(event).toJson(),
  };

  static PushSettings fromJson(Object? json) {
    final map = json is Map ? json : const <Object?, Object?>{};
    return PushSettings({
      for (final event in PushEvent.values)
        event: PushEventSettings.read(map[event.name], defaults.of(event)),
    });
  }

  /// Reads settings stored as a JSON string, or the defaults when there is none or it is damaged.
  static PushSettings decode(String? stored) {
    if (stored == null) return defaults;
    try {
      return fromJson(jsonDecode(stored));
    } on FormatException {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PushSettings &&
      PushEvent.values.every((event) => other.of(event) == of(event));

  @override
  int get hashCode => Object.hashAll(PushEvent.values.map(of));
}
