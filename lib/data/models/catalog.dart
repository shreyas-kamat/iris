/// The things a server offers rather than stores: skills, models, providers,
/// profiles, workspaces, and the agent's memory documents.
library;

import '../../core/json.dart';

/// An installed agent skill.
final class Skill {
  const Skill({
    required this.name,
    this.description,
    this.category,
    this.path,
    this.content,
    this.modifiedAt,
  });

  static Skill? fromJsonOrNull(Json json) {
    // The list endpoint returns objects; some builds return bare name strings.
    final name = json.isMap
        ? json.any(['name', 'id', 'slug']).stringOrNull
        : json.stringOrNull;
    if (name == null || name.isEmpty) return null;
    if (!json.isMap) return Skill(name: name);
    return Skill(
      name: name,
      description: json.any(['description', 'summary']).stringOrNull,
      category: json.any(['category', 'group']).stringOrNull,
      path: json['path'].stringOrNull,
      content: json.any(['content', 'body']).stringOrNull,
      modifiedAt: json.any([
        'mtime',
        'modified_at',
        'updated_at',
      ]).dateTimeOrNull,
    );
  }

  final String name;
  final String? description;
  final String? category;
  final String? path;

  /// The SKILL.md body, present only when fetched from the content endpoint.
  final String? content;
  final DateTime? modifiedAt;

  Skill withContent(String body, {String? path, DateTime? modifiedAt}) => Skill(
    name: name,
    description: description,
    category: category,
    path: path ?? this.path,
    content: body,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );
}

/// A model the server is configured to reach.
final class AgentModel {
  const AgentModel({required this.id, this.label, this.provider});

  static AgentModel? fromJsonOrNull(Json json) {
    final id = json.isMap
        ? json.any(['id', 'model', 'name', 'value']).stringOrNull
        : json.stringOrNull;
    if (id == null || id.isEmpty) return null;
    return AgentModel(
      id: id,
      label: json.isMap
          ? json.any(['label', 'display_name', 'title']).stringOrNull
          : null,
      // Model ids are conventionally `provider/model`; fall back to that when
      // the server does not name the provider separately.
      provider: json.isMap
          ? json.any(['provider', 'vendor']).stringOrNull ?? _providerOf(id)
          : _providerOf(id),
    );
  }

  static String? _providerOf(String id) {
    final slash = id.indexOf('/');
    return slash > 0 ? id.substring(0, slash) : null;
  }

  final String id;
  final String? label;
  final String? provider;

  /// What to show in a picker: the server's label, else the part of the id
  /// after the provider prefix, else the whole id.
  String get displayName {
    final explicit = label;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final slash = id.indexOf('/');
    return slash > 0 && slash < id.length - 1 ? id.substring(slash + 1) : id;
  }
}

/// A named agent configuration.
final class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    this.active = false,
    this.model,
  });

  static AgentProfile? fromJsonOrNull(Json json) {
    final id = json.isMap
        ? json.any(['id', 'name', 'slug']).stringOrNull
        : json.stringOrNull;
    if (id == null || id.isEmpty) return null;
    if (!json.isMap) return AgentProfile(id: id, name: id);
    return AgentProfile(
      id: id,
      name: json.any(['name', 'label', 'id']).string(id),
      active: json.any(['active', 'is_active', 'current']).boolean(),
      model: json['model'].stringOrNull,
    );
  }

  final String id;
  final String name;
  final bool active;
  final String? model;
}

/// A registered workspace root the agent can be pointed at.
final class WorkspaceRoot {
  const WorkspaceRoot({required this.path, this.name});

  static WorkspaceRoot? fromJsonOrNull(Json json) {
    final path = json.isMap ? json['path'].stringOrNull : json.stringOrNull;
    if (path == null || path.isEmpty) return null;
    return WorkspaceRoot(
      path: path,
      name: json.isMap ? json['name'].stringOrNull : null,
    );
  }

  final String path;
  final String? name;

  /// The name the user gave it, else the trailing directory.
  String get displayName {
    final explicit = name;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }
}

/// One entry in a workspace directory listing.
final class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
    this.modifiedAt,
  });

  static FileEntry? fromJsonOrNull(Json json) {
    final name = json['name'].stringOrNull;
    if (name == null || name.isEmpty) return null;
    final type = json['type'].string().toLowerCase();
    return FileEntry(
      name: name,
      path: json['path'].string(name),
      isDirectory:
          type == 'dir' || type == 'directory' || json['is_dir'].boolean(),
      sizeBytes: json['size'].intOrNull,
      modifiedAt: json.any(['mtime', 'modified_at']).dateTimeOrNull,
    );
  }

  final String name;
  final String path;
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? modifiedAt;
}

/// The agent's long-lived memory documents.
final class AgentMemory {
  const AgentMemory({this.memory = '', this.user = '', this.soul = ''});

  factory AgentMemory.fromJson(Json json) => AgentMemory(
    memory: json['memory'].string(),
    user: json['user'].string(),
    soul: json['soul'].string(),
  );

  /// What the agent has learned.
  final String memory;

  /// What it knows about its user.
  final String user;

  /// Its standing instructions.
  final String soul;

  bool get isEmpty => memory.isEmpty && user.isEmpty && soul.isEmpty;
}
