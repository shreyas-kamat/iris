/// The person's work profile and personal display templates, as the hermes-iris plugin keeps them. The agent proposes
/// them in a study; nothing is used until the person approves it in Iris.
library;

import 'dart:convert';

import '../../core/json.dart';

/// Where a proposal stands.
enum PersonalStatus {
  /// Written by the agent, waiting for the person.
  proposed,

  /// Kept by the person: the agent may use it.
  approved,

  /// Dropped by the person.
  retired;

  static PersonalStatus parse(String? wire) => switch (wire) {
    'approved' => approved,
    'retired' => retired,
    _ => proposed,
  };

  String get wire => name;
}

/// What a template makes.
enum TemplateKind {
  /// A card in the reply.
  display,

  /// Buttons or choices that dock above the composer.
  replyKit;

  static TemplateKind parse(String? wire) =>
      wire == 'reply_kit' ? replyKit : display;

  String get wire => this == replyKit ? 'reply_kit' : 'display';
}

/// One or two sentences about what the person does, and a few chips.
final class WorkProfile {
  const WorkProfile({
    required this.summary,
    required this.chips,
    required this.status,
    required this.rev,
    this.previousSummary,
    this.previousChips = const [],
  });

  static WorkProfile? fromJsonOrNull(Json json) {
    if (!json.isMap) return null;
    final summary = json['summary'].stringOrNull;
    if (summary == null) return null;
    final previous = json['previous'];
    return WorkProfile(
      summary: summary,
      chips: [for (final chip in json['chips'].list) ?chip.stringOrNull],
      status: PersonalStatus.parse(json['status'].stringOrNull),
      rev: json['rev'].integer(),
      previousSummary: previous['summary'].stringOrNull,
      previousChips: [
        for (final chip in previous['chips'].list) ?chip.stringOrNull,
      ],
    );
  }

  final String summary;
  final List<String> chips;
  final PersonalStatus status;
  final int rev;

  /// What the person had approved before this proposal replaced it, for a before-and-after.
  final String? previousSummary;
  final List<String> previousChips;
}

/// A stored OpenUI program that reads a top-level `data` object, with the schema of that object and made-up sample data
/// the review screen draws it with.
final class UiTemplate {
  const UiTemplate({
    required this.id,
    required this.name,
    required this.when,
    required this.kind,
    required this.status,
    required this.rev,
    required this.program,
    required this.dataSchema,
    required this.sampleData,
    this.updated,
  });

  static UiTemplate? fromJsonOrNull(Json json) {
    final id = json['id'].stringOrNull;
    final program = json['program'].stringOrNull;
    if (id == null || program == null) return null;
    return UiTemplate(
      id: id,
      name: json['name'].string(id),
      when: json['when'].string(),
      kind: TemplateKind.parse(json['kind'].stringOrNull),
      status: PersonalStatus.parse(json['status'].stringOrNull),
      rev: json['rev'].integer(),
      program: program,
      dataSchema: _object(json['data_schema']),
      sampleData: _object(json['sample_data']),
      updated: json['updated'].dateTimeOrNull,
    );
  }

  static Map<String, Object?> _object(Json json) {
    final raw = json.raw;
    return raw is Map ? Map<String, Object?>.from(raw) : const {};
  }

  final String id;
  final String name;

  /// One line saying when the agent should use it.
  final String when;
  final TemplateKind kind;
  final PersonalStatus status;
  final int rev;

  /// The OpenUI Lang program. It reads `data`; Iris binds the sample (or a reply's data) as `data = {...}` first.
  final String program;
  final Map<String, Object?> dataSchema;
  final Map<String, Object?> sampleData;
  final DateTime? updated;

  /// The program with [data] (the sample by default) bound as `data = {...}`, as the plugin expands it for a reply.
  String expanded([Map<String, Object?>? data]) =>
      'data = ${jsonEncode(data ?? sampleData)}\n$program';

  /// The names of the data the template takes, from its schema.
  List<String> get dataKeys {
    final properties = dataSchema['properties'];
    return properties is Map
        ? [for (final key in properties.keys) '$key']
        : const [];
  }
}
