/// The Iris GenUI component library, defined once (spec D5). `IrisLibrary.toLibrarySpec()` is what the renderer, the
/// validator and the server plugin all read; `server/hermes-iris/catalog/v1.library.json` is its checked-in export.
///
/// Props are ordered: OpenUI Lang passes them positionally, so required props come first and optional ones last.
/// Descriptions say what the type does not: when to use the component, what a value means, what to avoid.
library;

import 'package:openui_lang/openui_lang.dart';

/// The type of one prop (or function parameter). Knows its JSON Schema and how a signature prints it.
sealed class IrisType {
  const IrisType();

  static const string = _Scalar('string');
  static const number = _Scalar('number');
  static const boolean = _Scalar('boolean');

  /// Anything: printed `any`, no schema constraint.
  static const any = _Any();

  /// A list of any library components, printed `any[]`.
  static const children = _Children();

  /// An action: `@Ask(...)`, `@Set(...)`, `@OpenUrl(...)` and so on.
  static const action = _Action();

  static IrisType oneOf(List<String> values) => _Enum(values);
  static IrisType listOf(IrisType item) => _List(item);

  /// A list of one component type, e.g. `Stat[]`.
  static IrisType components(String name) => _ComponentList(name);

  Map<String, Object?> get schema;
  String get signature;
}

class _Scalar extends IrisType {
  const _Scalar(this.name);
  final String name;

  @override
  Map<String, Object?> get schema => {'type': name};

  @override
  String get signature => name;
}

class _Any extends IrisType {
  const _Any();

  @override
  Map<String, Object?> get schema => <String, Object?>{};

  @override
  String get signature => 'any';
}

class _Children extends IrisType {
  const _Children();

  @override
  Map<String, Object?> get schema => {
    'type': 'array',
    'items': {r'$ref': '#/\$defs/Component'},
  };

  @override
  String get signature => 'any[]';
}

class _Action extends IrisType {
  const _Action();

  @override
  Map<String, Object?> get schema => {r'$ref': '#/\$defs/ActionExpression'};

  @override
  String get signature => 'ActionExpression';
}

class _Enum extends IrisType {
  const _Enum(this.values);
  final List<String> values;

  @override
  Map<String, Object?> get schema => {'type': 'string', 'enum': values};

  @override
  String get signature => values.map((v) => '"$v"').join(' | ');
}

class _List extends IrisType {
  const _List(this.item);
  final IrisType item;

  @override
  Map<String, Object?> get schema => {'type': 'array', 'items': item.schema};

  @override
  String get signature => '${item.signature}[]';
}

class _ComponentList extends IrisType {
  const _ComponentList(this.name);
  final String name;

  @override
  Map<String, Object?> get schema => {
    'type': 'array',
    'items': {r'$ref': '#/\$defs/$name'},
  };

  @override
  String get signature => '$name[]';
}

class IrisProp {
  const IrisProp(this.name, this.type, {this.required = true});

  /// An optional prop; it must come after every required one.
  const IrisProp.optional(this.name, this.type) : required = false;

  final String name;
  final IrisType type;
  final bool required;
}

class IrisComponent {
  IrisComponent(this.name, this.description, [this.props = const []]) {
    var seenOptional = false;
    for (final p in props) {
      assert(
        !(seenOptional && p.required),
        '$name: required prop ${p.name} after an optional one',
      );
      seenOptional = seenOptional || !p.required;
    }
  }

  final String name;
  final String description;
  final List<IrisProp> props;

  String get signature =>
      '$name(${props.map((p) => '${p.name}${p.required ? '' : '?'}: ${p.type.signature}').join(', ')})';

  Map<String, Object?> get schema => {
    'type': 'object',
    'description': description,
    'properties': {for (final p in props) p.name: p.type.schema},
    if (props.any((p) => p.required))
      'required': [
        for (final p in props)
          if (p.required) p.name,
      ],
  };
}

class IrisFunction {
  const IrisFunction(this.name, this.description, this.params, {this.returns});

  final String name;
  final String description;
  final List<IrisProp> params;

  /// The result type, or null for an action.
  final IrisType? returns;

  String get signature {
    final head =
        '$name(${params.map((p) => '${p.name}${p.required ? '' : '?'}: ${p.type.signature}').join(', ')})';
    return returns == null ? head : '$head → ${returns!.signature}';
  }

  Map<String, Object?> get schema => {
    'description': description,
    'params': {
      'type': 'object',
      'properties': {for (final p in params) p.name: p.type.schema},
      if (params.any((p) => p.required))
        'required': [
          for (final p in params)
            if (p.required) p.name,
        ],
    },
    if (returns != null) 'returns': returns!.schema,
  };
}

class IrisComponentGroup {
  const IrisComponentGroup(this.name, this.components, [this.notes = const []]);

  final String name;
  final List<String> components;
  final List<String> notes;
}

abstract final class IrisLibrary {
  static const id = 'https://iris.shreyaskamat.in/genui/library/v1';
  static const version = '0.1.0';
  static const root = 'Stack';

  static final List<IrisComponent> components = [
    // Layout
    IrisComponent(
      'Stack',
      'Lays out children in a column (default) or a row. Use it as the root of almost every display',
      [
        const IrisProp('children', IrisType.children),
        IrisProp.optional('direction', IrisType.oneOf(const ['column', 'row'])),
        IrisProp.optional('gap', IrisType.oneOf(const ['s', 'm', 'l'])),
      ],
    ),
    IrisComponent(
      'Card',
      'A bordered container with an optional title. One card per idea; do not nest cards',
      [
        const IrisProp('children', IrisType.children),
        const IrisProp.optional('title', IrisType.string),
      ],
    ),
    IrisComponent(
      'Section',
      'A heading followed by content, for grouping without a border',
      [
        const IrisProp('title', IrisType.string),
        const IrisProp('children', IrisType.children),
      ],
    ),
    IrisComponent(
      'Divider',
      'A thin line between groups. Prefer Section to a bare divider',
    ),
    IrisComponent(
      'Tabs',
      'Switches between Tab children, one visible at a time. Keep to 2 to 5 tabs',
      [IrisProp('items', IrisType.components('Tab'))],
    ),
    IrisComponent(
      'Tab',
      'One page of a Tabs; the label is the tab title and should be a word or two',
      [
        const IrisProp('label', IrisType.string),
        const IrisProp('children', IrisType.children),
      ],
    ),
    IrisComponent(
      'Expander',
      'A title that opens to reveal children; use for detail most people will not need',
      [
        const IrisProp('title', IrisType.string),
        const IrisProp('children', IrisType.children),
        const IrisProp.optional('open', IrisType.boolean),
      ],
    ),

    // Text and data
    IrisComponent(
      'Text',
      'A run of text; title is a heading, caption is small and muted, mono is for ids and paths',
      [
        const IrisProp('value', IrisType.string),
        IrisProp.optional(
          'variant',
          IrisType.oneOf(const ['body', 'title', 'caption', 'mono']),
        ),
      ],
    ),
    IrisComponent(
      'Markdown',
      'Formatted text (bold, lists, links, code); use when the content is already Markdown',
      [const IrisProp('value', IrisType.string)],
    ),
    IrisComponent(
      'KeyValue',
      'A label with its value on one line, for facts such as "Region: eu-west"',
      [
        const IrisProp('key', IrisType.string),
        const IrisProp('value', IrisType.string),
      ],
    ),
    IrisComponent(
      'Stat',
      'One big number with a label and an optional change; keep value short, such as "12" or "98%"',
      [
        const IrisProp('label', IrisType.string),
        const IrisProp('value', IrisType.string),
        const IrisProp.optional('delta', IrisType.string),
        IrisProp.optional(
          'trend',
          IrisType.oneOf(const ['up', 'down', 'flat']),
        ),
      ],
    ),
    IrisComponent(
      'StatRow',
      'A row of 2 to 4 Stat components that share the width',
      [IrisProp('stats', IrisType.components('Stat'))],
    ),
    IrisComponent(
      'StatusPill',
      'A small coloured status label; tone says how it feels, so pick it for meaning, not looks',
      [
        const IrisProp('label', IrisType.string),
        IrisProp.optional(
          'tone',
          IrisType.oneOf(const ['neutral', 'good', 'warn', 'bad']),
        ),
      ],
    ),
    IrisComponent(
      'Table',
      'A grid of text. columns are the headings; each row has one cell per column. Up to about 6 columns',
      [
        IrisProp('columns', IrisType.listOf(IrisType.string)),
        IrisProp('rows', IrisType.listOf(IrisType.listOf(IrisType.any))),
      ],
    ),
    IrisComponent(
      'ListRow',
      'A row with a title, an optional second line and trailing text, for lists of things',
      [
        const IrisProp('title', IrisType.string),
        const IrisProp.optional('subtitle', IrisType.string),
        const IrisProp.optional('trailing', IrisType.string),
      ],
    ),
    IrisComponent(
      'Timeline',
      'Events in time order, oldest first, joined by a line',
      [IrisProp('items', IrisType.components('TimelineItem'))],
    ),
    IrisComponent(
      'TimelineItem',
      'One event on a Timeline; time is shown as given, so write it the way a person would say it',
      [
        const IrisProp('title', IrisType.string),
        const IrisProp.optional('time', IrisType.string),
        const IrisProp.optional('detail', IrisType.string),
      ],
    ),
    IrisComponent(
      'Checklist',
      'A read-only list of items that are done or not yet done',
      [IrisProp('items', IrisType.components('ChecklistItem'))],
    ),
    IrisComponent(
      'ChecklistItem',
      'One line of a Checklist; done defaults to false',
      [
        const IrisProp('label', IrisType.string),
        const IrisProp.optional('done', IrisType.boolean),
      ],
    ),
    IrisComponent(
      'Progress',
      'A bar (or ring) showing a value from 0 to 100, not a fraction',
      [
        const IrisProp('value', IrisType.number),
        const IrisProp.optional('label', IrisType.string),
        IrisProp.optional('style', IrisType.oneOf(const ['bar', 'ring'])),
      ],
    ),
    IrisComponent(
      'CodeBlock',
      'Monospaced code with copy; language is a short name such as "dart" or "bash"',
      [
        const IrisProp('code', IrisType.string),
        const IrisProp.optional('language', IrisType.string),
      ],
    ),
    IrisComponent(
      'Diff',
      'Two versions of some text, with the changed lines marked. Use for edits, not for general comparison',
      [
        const IrisProp('before', IrisType.string),
        const IrisProp('after', IrisType.string),
      ],
    ),
    IrisComponent(
      'Image',
      'A picture from an allowed image host. alt is required and should describe it for a screen reader',
      [
        const IrisProp('url', IrisType.string),
        const IrisProp('alt', IrisType.string),
      ],
    ),
    IrisComponent(
      'Link',
      'Text that opens a web address after the person confirms. Use for sources, not for actions',
      [
        const IrisProp('label', IrisType.string),
        const IrisProp('url', IrisType.string),
      ],
    ),

    // Actions (the inputs and reply kits arrive in Phase 4)
    IrisComponent(
      'Button',
      'A button. Without an action it sends its label to the assistant as the person\'s next message',
      [
        const IrisProp('label', IrisType.string),
        const IrisProp.optional('action', IrisType.action),
        IrisProp.optional(
          'variant',
          IrisType.oneOf(const ['primary', 'secondary']),
        ),
      ],
    ),
  ];

  static final List<IrisFunction> functions = [
    IrisFunction(
      'Percent',
      'done as a percentage of total, rounded to a whole number',
      const [
        IrisProp('done', IrisType.number),
        IrisProp('total', IrisType.number),
      ],
      returns: IrisType.number,
    ),
    IrisFunction(
      'Money',
      'value formatted as money in the given ISO currency code, such as "GBP"',
      const [
        IrisProp('value', IrisType.number),
        IrisProp('currency', IrisType.string),
      ],
      returns: IrisType.string,
    ),
    IrisFunction(
      'Ago',
      'a timestamp (ISO 8601 text or epoch milliseconds) as relative time, such as "3 hours ago"',
      const [IrisProp('timestamp', IrisType.any)],
      returns: IrisType.string,
    ),
  ];

  static final List<IrisFunction> actions = [
    IrisFunction(
      'Ask',
      'Send a message to the assistant as if the person typed it; context is hidden data for it',
      const [
        IrisProp('text', IrisType.string),
        IrisProp.optional('context', IrisType.any),
      ],
    ),
  ];

  static final List<IrisComponentGroup> groups = [
    IrisComponentGroup('Layout', const [
      'Stack',
      'Card',
      'Section',
      'Divider',
      'Tabs',
      'Tab',
      'Expander',
    ]),
    IrisComponentGroup('Text and data', const [
      'Text',
      'Markdown',
      'KeyValue',
      'Stat',
      'StatRow',
      'StatusPill',
      'Table',
      'ListRow',
      'Timeline',
      'TimelineItem',
      'Checklist',
      'ChecklistItem',
      'Progress',
      'CodeBlock',
      'Diff',
      'Image',
      'Link',
    ]),
    IrisComponentGroup('Actions', const ['Button']),
  ];

  /// The library as OpenUI's `library.json`: the JSON Schema plus the pre-built signature text.
  static Map<String, Object?> toJson() {
    final names = [for (final c in components) c.name];
    return {
      'id': id,
      'version': version,
      'root': root,
      'schema': {
        'properties': {
          for (final n in names) n: {r'$ref': '#/\$defs/$n'},
        },
        r'$defs': {
          for (final c in components) c.name: c.schema,
          'Component': {
            'anyOf': [
              for (final n in names) {r'$ref': '#/\$defs/$n'},
            ],
          },
          'ActionExpression': _actionExpression,
        },
        'functions': {for (final f in functions) f.name: f.schema},
        'actions': {for (final a in actions) a.name: a.schema},
      },
      'components': {
        for (final c in components)
          c.name: {'signature': c.signature, 'description': c.description},
      },
      'functions': {
        for (final f in functions)
          f.name: {'signature': f.signature, 'description': f.description},
      },
      'actions': {
        for (final a in actions)
          a.name: {'signature': a.signature, 'description': a.description},
      },
      'componentGroups': [
        for (final g in groups)
          {
            'name': g.name,
            'components': g.components,
            if (g.notes.isNotEmpty) 'notes': g.notes,
          },
      ],
    };
  }

  static LibrarySpec toLibrarySpec() => LibrarySpec.fromJson(toJson());

  static final Map<String, Object?> _actionExpression = {
    'anyOf': [
      {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'const': 'open_url'},
          'url': {'type': 'string'},
        },
        'required': ['type', 'url'],
      },
      {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'const': 'continue_conversation'},
          'context': {'type': 'string'},
        },
        'required': ['type'],
      },
      {
        'type': 'object',
        'properties': {
          'type': {'type': 'string'},
          'params': {'type': 'object'},
        },
        'required': ['type'],
      },
    ],
  };
}
