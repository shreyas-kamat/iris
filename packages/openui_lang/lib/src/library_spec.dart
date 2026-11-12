/// A component library as OpenUI describes it (prompt.md §2). The key order of `properties` is the positional order,
/// so everything here keeps insertion order (Dart's default map is a LinkedHashMap).
library;

typedef Json = Map<String, Object?>;

Json _asMap(Object? o) => o is Map ? o.cast<String, Object?>() : <String, Object?>{};

/// One prop of a component, or one parameter of a function or action.
class PropSpec {
  const PropSpec({required this.name, required this.schema, required this.required, this.bindable = false});

  final String name;

  /// The JSON Schema fragment for this prop, untouched.
  final Json schema;
  final bool required;

  /// True when the signature prints `$binding<type>` for this prop (the schema has no marker).
  final bool bindable;

  Object? get defaultValue => schema['default'];
  bool get hasDefault => schema.containsKey('default');
}

List<PropSpec> _props(Json object, {Set<String> bindable = const {}}) {
  final properties = _asMap(object['properties']);
  final required = ((object['required'] as List?) ?? const []).cast<String>().toSet();
  return [
    for (final e in properties.entries)
      PropSpec(
        name: e.key,
        schema: _asMap(e.value),
        required: required.contains(e.key),
        bindable: bindable.contains(e.key),
      ),
  ];
}

class ComponentSpec {
  const ComponentSpec({required this.name, required this.description, required this.props});

  final String name;
  final String description;
  final List<PropSpec> props;
}

class FunctionSpec {
  const FunctionSpec({required this.name, required this.description, required this.params, this.returns});

  final String name;
  final String description;
  final List<PropSpec> params;
  final Json? returns;
}

/// A custom action has the same shape as a function, without `returns`.
typedef ActionSpec = FunctionSpec;

class LibrarySpec {
  LibrarySpec._(this.json, this.id, this.version, this.root, this.components, this.functions, this.actions);

  factory LibrarySpec.fromJson(Json json) {
    final schema = _asMap(json['schema']);
    final defs = _asMap(schema['\$defs']);
    final listed = _asMap(json['components']);

    final components = <String, ComponentSpec>{};
    for (final name in _asMap(schema['properties']).keys) {
      final def = _asMap(defs[name]);
      final signature = (_asMap(listed[name])['signature'] as String?) ?? '';
      components[name] = ComponentSpec(
        name: name,
        description: (def['description'] as String?) ?? (_asMap(listed[name])['description'] as String?) ?? '',
        props: _props(def, bindable: _bindableNames(signature)),
      );
    }

    FunctionSpec fn(String name, Object? raw) {
      final m = _asMap(raw);
      return FunctionSpec(
        name: name,
        description: (m['description'] as String?) ?? '',
        params: _props(_asMap(m['params'])),
        returns: m['returns'] is Map ? _asMap(m['returns']) : null,
      );
    }

    return LibrarySpec._(
      json,
      json['id'] as String?,
      json['version'] as String?,
      json['root'] as String?,
      components,
      {for (final e in _asMap(schema['functions']).entries) e.key: fn(e.key, e.value)},
      {for (final e in _asMap(schema['actions']).entries) e.key: fn(e.key, e.value)},
    );
  }

  final Json json;
  final String? id;
  final String? version;
  final String? root;
  final Map<String, ComponentSpec> components;
  final Map<String, FunctionSpec> functions;
  final Map<String, ActionSpec> actions;

  /// `$defs` entries, for resolving `$ref`s.
  Json get defs => _asMap(_asMap(json['schema'])['\$defs']);

  Json toJson() => json;

  /// Names in a signature written as `name: $binding<...>` or `name?: $binding<...>`.
  static Set<String> _bindableNames(String signature) =>
      RegExp(r'(\w+)\??:\s*\$binding<').allMatches(signature).map((m) => m.group(1)!).toSet();
}
