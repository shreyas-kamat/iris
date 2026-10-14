/// Colours for highlighted code, derived from the active palette.
///
/// Code blocks belong to the skin rather than to a borrowed editor theme: the
/// roles come from the agent-state hues every skin already tunes, and each is
/// nudged toward ink until it clears AA on the code well. That nudge is why
/// the contrast test can never fail for a new skin.
library;

import 'package:flutter/widgets.dart';

import 'palette.dart';

@immutable
final class IrisCodeColors {
  const IrisCodeColors({
    required this.plain,
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.title,
    required this.type,
    required this.attr,
    required this.meta,
    required this.addition,
    required this.deletion,
  });

  static final Expando<IrisCodeColors> _cache = Expando();

  /// The code colours for [palette], computed once per palette.
  static IrisCodeColors of(IrisPalette palette) =>
      _cache[palette] ??= _derive(palette);

  static IrisCodeColors _derive(IrisPalette p) {
    final well = p.surfaceSunken;
    Color legible(Color color) => _legible(color, toward: p.ink, on: well);
    return IrisCodeColors(
      plain: p.ink,
      keyword: legible(p.colorFor(AgentState.thinking)),
      string: legible(p.colorFor(AgentState.done)),
      number: legible(p.colorFor(AgentState.working)),
      comment: legible(p.inkMuted),
      title: legible(p.accent),
      type: legible(p.colorFor(AgentState.streaming)),
      attr: legible(p.colorFor(AgentState.waiting)),
      meta: legible(p.inkMuted),
      addition: legible(p.colorFor(AgentState.done)),
      deletion: legible(p.colorFor(AgentState.failed)),
    );
  }

  /// [color], moved toward [toward] in small steps until it reaches 4.5:1 on
  /// [on]. [toward] is ink, which passes on every surface, so this ends.
  static Color _legible(
    Color color, {
    required Color toward,
    required Color on,
  }) {
    var current = color;
    for (var step = 1; step <= 10 && _contrast(current, on) < 4.5; step++) {
      current = Color.lerp(color, toward, step / 10)!;
    }
    return current;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  final Color plain;
  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color title;
  final Color type;
  final Color attr;
  final Color meta;
  final Color addition;
  final Color deletion;

  /// Every role, named, for the contrast test.
  List<(String, Color)> get roles => [
    ('plain', plain),
    ('keyword', keyword),
    ('string', string),
    ('number', number),
    ('comment', comment),
    ('title', title),
    ('type', type),
    ('attr', attr),
    ('meta', meta),
    ('addition', addition),
    ('deletion', deletion),
  ];

  /// The highlight.js classes `re_highlight` emits, mapped to these roles.
  /// A class not named here takes the plain colour.
  Map<String, TextStyle> get theme => {
    'root': TextStyle(color: plain),
    'keyword': TextStyle(color: keyword),
    'selector-tag': TextStyle(color: keyword),
    'name': TextStyle(color: keyword),
    'built_in': TextStyle(color: type),
    'type': TextStyle(color: type),
    'title.class_': TextStyle(color: type),
    'class-title': TextStyle(color: type),
    'literal': TextStyle(color: number),
    'number': TextStyle(color: number),
    'symbol': TextStyle(color: number),
    'string': TextStyle(color: string),
    'regexp': TextStyle(color: string),
    'template-variable': TextStyle(color: string),
    'comment': TextStyle(color: comment, fontStyle: FontStyle.italic),
    'quote': TextStyle(color: comment, fontStyle: FontStyle.italic),
    'doctag': TextStyle(color: comment),
    'title': TextStyle(color: title),
    'title.function_': TextStyle(color: title),
    'section': TextStyle(color: title),
    'attr': TextStyle(color: attr),
    'attribute': TextStyle(color: attr),
    'property': TextStyle(color: attr),
    'variable': TextStyle(color: attr),
    'meta': TextStyle(color: meta),
    'meta-string': TextStyle(color: string),
    'addition': TextStyle(color: addition),
    'deletion': TextStyle(color: deletion),
  };
}
