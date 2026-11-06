/// What the hermes-iris plugin tells Iris about generated displays.
library;

import '../../core/json.dart';

/// Where a display sits.
enum SurfacePlacement {
  /// In the reply, among the text.
  inline,

  /// Above the composer, as quick replies.
  replyKit;

  static SurfacePlacement parse(String? wire) =>
      wire == 'reply_kit' ? replyKit : inline;
}

/// `GET /api/plugins/iris/capabilities`.
final class GenUiCapabilities {
  const GenUiCapabilities({
    required this.version,
    required this.openui,
    required this.libraryIds,
    required this.features,
  });

  static GenUiCapabilities? fromJsonOrNull(Json json) {
    if (!json.isMap) return null;
    final version = json['version'].stringOrNull;
    if (version == null) return null;
    return GenUiCapabilities(
      version: version,
      openui: json['openui'].stringOrNull,
      libraryIds: [for (final id in json['library_ids'].list) ?id.stringOrNull],
      features: {
        for (final feature in json['features'].list) ?feature.stringOrNull,
      },
    );
  }

  final String version;

  /// The OpenUI Lang version the plugin validates against.
  final String? openui;
  final List<String> libraryIds;
  final Set<String> features;

  /// The component library Iris renders.
  static const libraryId = 'https://iris.shreyaskamat.in/genui/library/v1';

  /// Whether the plugin knows the library this build of Iris draws.
  bool get speaksIrisLibrary => libraryIds.contains(libraryId);

  bool has(String feature) => features.contains(feature);
}

/// A display the agent made, as the plugin stored it.
final class UiSurface {
  const UiSurface({
    required this.surfaceId,
    required this.rev,
    required this.placement,
    this.template,
    this.code,
    this.fallback,
    this.updated,
  });

  static UiSurface? fromJsonOrNull(Json json) {
    final id = json['surface_id'].stringOrNull;
    if (id == null) return null;
    return UiSurface(
      surfaceId: id,
      rev: json['rev'].integer(),
      placement: SurfacePlacement.parse(json['placement'].stringOrNull),
      template: json['template'].stringOrNull,
      code: json['code'].stringOrNull,
      fallback: json['fallback'].stringOrNull,
      updated: json['updated'].dateTimeOrNull,
    );
  }

  final String surfaceId;

  /// Counts up each time the agent reuses the id to change the display.
  final int rev;
  final SurfacePlacement placement;
  final String? template;

  /// The OpenUI Lang program. Absent in a list, present when one is fetched.
  final String? code;

  /// The same content as Markdown, for places that cannot draw the display.
  final String? fallback;
  final DateTime? updated;
}

/// A mention of a display in the transcript: an `iris_ui` call, before or without its program.
///
/// A tool call carries the program in its arguments, but the arguments can arrive cut short, so the stored surface
/// (by [surfaceId]) is the source of truth and [code] is only a head start.
final class UiSurfaceRef {
  const UiSurfaceRef({
    required this.surfaceId,
    this.placement = SurfacePlacement.inline,
    this.code,
    this.fallback,
    this.template,
    this.deleted = false,
    this.accepted,
    this.rev,
  });

  final String surfaceId;
  final SurfacePlacement placement;

  /// The program from the call's arguments, when it came whole.
  final String? code;
  final String? fallback;
  final String? template;

  /// The agent asked to remove this display.
  final bool deleted;

  /// What the plugin answered: true when it stored the display, false when it refused, null when the answer is not
  /// known or could not be read. The server's surface list decides what is drawn; this is advice.
  final bool? accepted;

  /// The revision the plugin stored, when it said.
  final int? rev;

  UiSurfaceRef copyWith({bool? accepted, int? rev}) => UiSurfaceRef(
    surfaceId: surfaceId,
    placement: placement,
    code: code,
    fallback: fallback,
    template: template,
    deleted: deleted,
    accepted: accepted ?? this.accepted,
    rev: rev ?? this.rev,
  );
}
