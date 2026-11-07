/// Turns an evaluated OpenUI tree into widgets on the Iris design tokens (plan 3.2).
///
/// Everything here is defensive: the tree has been validated, but the library may be newer than the app, and a value
/// that survived validation (a `Deferred` that evaluated to a list, say) can still be the wrong shape for a widget. A
/// part that cannot be built becomes a quiet "can't show this" chip; it never throws.
library;

import 'package:flutter/material.dart';
import 'package:openui_lang/openui_lang.dart' hide Element;
import 'package:openui_lang/openui_lang.dart' as oul show Element;

import '../../../design/components/controls.dart';
import '../../../design/components/markdown.dart';
import '../../../design/components/markdown_image.dart';
import '../../../design/components/primitives.dart';
import '../../../design/theme/iris_theme.dart';
import '../../../design/tokens/metrics.dart';
import '../../../design/tokens/palette.dart';
import 'chart_widgets.dart';
import 'input_widgets.dart';
import 'node_widgets.dart';

/// The OpenUI tree's element, named apart from Flutter's.
typedef UiElement = oul.Element;

/// What a component may ask of the surface it sits in. Phase 4 supplies the real ones; without them buttons are
/// disabled and links are plain text.
class NodeEnv {
  const NodeEnv({this.onAction, this.onOpenUrl, this.store, this.maxDepth = 8});

  /// Runs an action. `component` is the component type that raised it, for the `<iris-action>` envelope.
  final void Function(ActionValue action, String component)? onAction;

  /// Opens a web address after the host has asked the person to confirm it.
  final ValueChanged<String>? onOpenUrl;

  /// The display's variables. Inputs bound to a `$variable` read and write it; without one they keep their value
  /// locally. `OpenUiView` supplies its own.
  final StateStore? store;

  NodeEnv withStore(StateStore store) => NodeEnv(
    onAction: onAction,
    onOpenUrl: onOpenUrl,
    store: store,
    maxDepth: maxDepth,
  );

  /// Nesting beyond this is not drawn (the plugin enforces the same limit).
  final int maxDepth;
}

/// Builds widgets for [UiElement]s. Stateless; one instance serves a whole surface.
class NodeBuilder {
  const NodeBuilder({this.env = const NodeEnv()});

  final NodeEnv env;

  /// A whole surface. [pending] adds a skeleton below the content while more of the program is arriving or while
  /// references are still unresolved. [errorCount] > 0 with a root adds a quiet note that part is missing.
  Widget surface(
    BuildContext context,
    UiElement? root, {
    bool pending = false,
    int errorCount = 0,
  }) {
    final children = <Widget>[
      if (root != null)
        build(context, root)
      else if (!pending)
        const IrisCantShow(),
      if (pending) ...[
        if (root != null) const SizedBox(height: IrisSpace.md),
        const IrisSurfaceSkeleton(rows: 2),
      ],
      if (root != null && errorCount > 0 && !pending) ...[
        const SizedBox(height: IrisSpace.sm),
        const IrisCantShow(),
      ],
    ];
    if (children.length == 1) return children.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// One value as a widget: an [UiElement], or a literal that was put where a component was expected.
  Widget build(BuildContext context, Object? node, {int depth = 0}) {
    if (node == null) return const SizedBox.shrink();
    if (node is! UiElement) {
      return node is String || node is num || node is bool
          ? Text(jsString(node), style: context.type.body)
          : const IrisCantShow();
    }
    if (depth > env.maxDepth) return const IrisCantShow(what: 'too deep');
    try {
      return _element(context, node, depth) ?? IrisCantShow(what: node.type);
    } on Object {
      return IrisCantShow(what: node.type);
    }
  }

  // -- props ----------------------------------------------------------------------------------------------------------

  static String? _s(UiElement e, String name) {
    final v = e.props[name];
    return switch (v) {
      null => null,
      String() => v,
      num() || bool() => jsString(v),
      _ => null,
    };
  }

  static double? _n(UiElement e, String name) {
    final v = e.props[name];
    return v is num ? v.toDouble() : null;
  }

  static bool _b(UiElement e, String name, {bool or = false}) {
    final v = e.props[name];
    return v is bool ? v : or;
  }

  static List<Object?> _list(UiElement e, String name) {
    final v = e.props[name];
    return v is List ? v : const [];
  }

  /// The elements of a list prop, of one type when [type] is given; anything else in the list is skipped.
  static List<UiElement> _elements(UiElement e, String name, [String? type]) =>
      [
        for (final x in _list(e, name))
          if (x is UiElement && (type == null || x.type == type)) x,
      ];

  List<Widget> _children(
    BuildContext context,
    UiElement e,
    int depth, [
    String name = 'children',
  ]) => [
    for (final x in _list(e, name))
      if (x != null) build(context, x, depth: depth + 1),
  ];

  static const _gaps = {
    's': IrisSpace.sm,
    'm': IrisSpace.md,
    'l': IrisSpace.lg,
  };

  Widget _column(List<Widget> children, {double gap = IrisSpace.md}) =>
      children.length == 1
      ? children.single
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );

  // -- components -----------------------------------------------------------------------------------------------------

  Widget? _element(BuildContext context, UiElement e, int depth) {
    final palette = context.palette;
    final type = context.type;

    switch (e.type) {
      case 'Stack':
        final kids = _children(context, e, depth);
        if (kids.isEmpty) return const SizedBox.shrink();
        final gap = _gaps[_s(e, 'gap')] ?? IrisSpace.md;
        if (_s(e, 'direction') == 'row') {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: kids,
          );
        }
        return _column(kids, gap: gap);

      case 'Card':
        final title = _s(e, 'title');
        final kids = _children(context, e, depth);
        return IrisCard(
          child: _column([
            if (title != null)
              Semantics(header: true, child: Text(title, style: type.heading)),
            ...kids,
          ], gap: IrisSpace.sm),
        );

      case 'Section':
        final title = _s(e, 'title');
        if (title == null) return null;
        return _column([
          Semantics(header: true, child: IrisLabel(title)),
          ..._children(context, e, depth),
        ], gap: IrisSpace.sm);

      case 'Divider':
        return const IrisDivider();

      case 'Tabs':
        final tabs = _elements(e, 'items', 'Tab');
        if (tabs.isEmpty) return const SizedBox.shrink();
        return IrisTabsView(
          labels: [for (final t in tabs) _s(t, 'label') ?? ''],
          pages: [
            for (final t in tabs) _column(_children(context, t, depth + 1)),
          ],
        );

      case 'Tab': // outside Tabs: just its content
        return _column(_children(context, e, depth));

      case 'Expander':
        final title = _s(e, 'title');
        if (title == null) return null;
        return IrisExpanderView(
          title: title,
          initiallyOpen: _b(e, 'open'),
          child: _column(_children(context, e, depth), gap: IrisSpace.sm),
        );

      case 'Text':
        final value = _s(e, 'value');
        if (value == null) return null;
        return switch (_s(e, 'variant')) {
          'title' => Semantics(
            header: true,
            child: Text(value, style: type.title),
          ),
          'caption' => Text(
            value,
            style: type.caption.copyWith(color: palette.inkMuted),
          ),
          'mono' => Text(value, style: type.code),
          _ => Text(value, style: type.body),
        };

      case 'Markdown':
        final value = _s(e, 'value');
        return value == null
            ? null
            : IrisMarkdown(value, onTapLink: env.onOpenUrl);

      case 'KeyValue':
        final key = _s(e, 'key');
        final value = _s(e, 'value');
        if (key == null || value == null) return null;
        return Semantics(
          container: true,
          label: '$key: $value',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                flex: 2,
                child: Text(
                  key,
                  style: type.caption.copyWith(color: palette.inkMuted),
                ),
              ),
              const SizedBox(width: IrisSpace.md),
              Flexible(
                flex: 3,
                child: Text(value, style: type.body, textAlign: TextAlign.end),
              ),
            ],
          ),
        );

      case 'Stat':
        return _stat(context, e);

      case 'StatRow':
        final stats = [
          for (final s in _elements(e, 'stats', 'Stat')) _stat(context, s),
        ];
        if (stats.isEmpty) return const SizedBox.shrink();
        final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (big || stats.length > 4) {
          return _column(stats);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: IrisSpace.md),
                Expanded(child: stats[i]),
              ],
            ],
          ),
        );

      case 'StatusPill':
        final label = _s(e, 'label');
        if (label == null) return null;
        final state = switch (_s(e, 'tone')) {
          'good' => AgentState.done,
          'warn' => AgentState.waiting,
          'bad' => AgentState.failed,
          _ => null,
        };
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: state == null
              ? IrisChip(label)
              : IrisChip.state(label, state, palette),
        );

      case 'Table':
        return _table(context, e);

      case 'ListRow':
        final title = _s(e, 'title');
        if (title == null) return null;
        final subtitle = _s(e, 'subtitle');
        final trailing = _s(e, 'trailing');
        return Semantics(
          container: true,
          label: [title, ?subtitle, ?trailing].join(', '),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: IrisSpace.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: type.body),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: type.caption.copyWith(color: palette.inkMuted),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: IrisSpace.md),
                  Text(
                    trailing,
                    style: type.numeric.copyWith(color: palette.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        );

      case 'Timeline':
        final items = _elements(e, 'items', 'TimelineItem');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              IrisTimelineRow(
                title: _s(items[i], 'title') ?? '',
                time: _s(items[i], 'time'),
                detail: _s(items[i], 'detail'),
                first: i == 0,
                last: i == items.length - 1,
              ),
          ],
        );

      case 'TimelineItem': // outside Timeline
        return IrisTimelineRow(
          title: _s(e, 'title') ?? '',
          time: _s(e, 'time'),
          detail: _s(e, 'detail'),
          first: true,
          last: true,
        );

      case 'Checklist':
        final items = _elements(e, 'items', 'ChecklistItem');
        return _column([
          for (final i in items) _checkRow(context, i),
        ], gap: IrisSpace.xs);

      case 'ChecklistItem':
        return _checkRow(context, e);

      case 'Progress':
        final raw = _n(e, 'value');
        if (raw == null) return null;
        final fraction = (raw / 100).clamp(0.0, 1.0);
        final label = _s(e, 'label');
        if (_s(e, 'style') == 'ring') {
          return Row(
            children: [
              IrisRing(
                value: fraction,
                size: 28,
                color: palette.accent,
                semanticLabel:
                    '${label ?? 'Progress'}: ${(fraction * 100).round()} percent',
              ),
              if (label != null) ...[
                const SizedBox(width: IrisSpace.sm),
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(label, style: type.caption),
                  ),
                ),
              ],
            ],
          );
        }
        // The gauge shades toward the failure hue as it fills, which suits a context window and not a task's progress.
        return IrisGauge(
          value: fraction,
          label: label,
          width: null,
          tint: palette.accent,
        );

      case 'CodeBlock':
        final code = _s(e, 'code');
        if (code == null) return null;
        final language = _s(e, 'language') ?? '';
        // A fence longer than any run of backticks inside the code cannot be closed early by it.
        var ticks = 3;
        for (final m in RegExp('`+').allMatches(code)) {
          if (m.group(0)!.length >= ticks) ticks = m.group(0)!.length + 1;
        }
        final fence = '`' * ticks;
        return IrisMarkdown(
          '$fence${language.replaceAll(RegExp(r'\s'), '')}\n$code\n$fence',
        );

      case 'Diff':
        final before = _s(e, 'before');
        final after = _s(e, 'after');
        if (before == null || after == null) return null;
        return IrisDiffView(before: before, after: after);

      case 'Image':
        final url = _s(e, 'url');
        if (url == null || !MarkdownImage.canShow(url)) return null;
        return MarkdownImage(url: url, alt: _s(e, 'alt'));

      case 'Link':
        final label = _s(e, 'label');
        final url = _s(e, 'url');
        if (label == null || url == null) return null;
        final style = type.body.copyWith(
          color: env.onOpenUrl == null ? palette.ink : palette.accent,
          decoration: TextDecoration.underline,
          decorationColor: palette.accent,
        );
        if (env.onOpenUrl == null || !MarkdownImage.canShow(url)) {
          return Text(label, style: style);
        }
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Semantics(
            link: true,
            child: IrisPressable(
              onTap: () => env.onOpenUrl!(url),
              semanticLabel: label,
              child: ExcludeSemantics(child: Text(label, style: style)),
            ),
          ),
        );

      case 'Sparkline':
        final values = cleanValues(_list(e, 'values'));
        return values.isEmpty ? null : IrisSparkline(values: values);

      case 'Series': // outside a chart: nothing to say it belongs to
        return null;

      case 'LineChart':
      case 'BarChart':
        final series = _series(e);
        if (series.isEmpty) return null;
        final labels = [for (final l in _list(e, 'labels')) jsString(l)];
        if (e.type == 'BarChart') {
          return IrisBarChart(series: series, labels: labels);
        }
        // A line needs two points to be a line; one point alone is not a chart.
        if (series.every((s) => s.values.length < 2)) return null;
        return IrisLineChart(series: series, labels: labels);

      case 'Donut':
        final slices = _slices(e);
        return slices.isEmpty ? null : IrisDonut(slices: slices);

      case 'Slice':
        return null;

      case 'ChoiceChips':
        final options = [
          for (final o in _list(e, 'options'))
            if (o != null) jsString(o),
        ];
        if (options.isEmpty) return null;
        final multi = _b(e, 'multi');
        return _bound(
          e,
          (value, set) => IrisChoiceChips(
            options: options,
            value: value,
            onChanged: set,
            multi: multi,
            label: _s(e, 'label'),
          ),
        );

      case 'Input':
        final label = _s(e, 'label');
        if (label == null) return null;
        return _bound(
          e,
          (value, set) => IrisTextInput(
            label: label,
            value: value,
            onChanged: set,
            placeholder: _s(e, 'placeholder'),
            kind: switch (_s(e, 'kind')) {
              'number' => InputKind.number,
              'multiline' => InputKind.multiline,
              _ => InputKind.text,
            },
          ),
        );

      case 'Slider':
        final label = _s(e, 'label');
        final lo = _n(e, 'min');
        final hi = _n(e, 'max');
        if (label == null || lo == null || hi == null || !(hi > lo)) {
          return null;
        }
        return _bound(
          e,
          (value, set) => IrisSliderRow(
            label: label,
            min: lo,
            max: hi,
            value: value is num ? value : null,
            step: _n(e, 'step'),
            onChanged: set,
          ),
        );

      case 'Toggle':
        final label = _s(e, 'label');
        if (label == null) return null;
        return _bound(
          e,
          (value, set) =>
              IrisToggleRow(label: label, value: value == true, onChanged: set),
        );

      case 'DatePicker':
        final label = _s(e, 'label');
        if (label == null) return null;
        return _bound(
          e,
          (value, set) =>
              IrisDatePickerRow(label: label, value: value, onChanged: set),
        );

      case 'Stepper':
        final label = _s(e, 'label');
        if (label == null) return null;
        final step = _n(e, 'step');
        return _bound(
          e,
          (value, set) => IrisStepperRow(
            label: label,
            value: value is num ? value : null,
            min: _n(e, 'min'),
            max: _n(e, 'max'),
            step: step != null && step > 0 ? step : 1,
            onChanged: set,
          ),
        );

      case 'ApproveReject':
        final approve = _s(e, 'approveLabel');
        final reject = _s(e, 'rejectLabel');
        if (approve == null || reject == null) return null;
        final ask = _s(e, 'askLabel');
        final run = env.onAction;
        VoidCallback? send(String label, String decision) => run == null
            ? null
            : () => run(
                ActionValue([
                  CustomStep('Ask', {
                    'text': label,
                    'context': {'decision': decision},
                  }),
                ]),
                'ApproveReject',
              );
        // At large text three buttons side by side would clip their labels, so they stack and fill the width.
        final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        // IrisButton centres its content, so side by side each needs to shrink to fit its label.
        Widget button(String label, String decision, IrisButtonTone tone) {
          final b = IrisButton(
            label: label,
            tone: tone,
            expand: stacked,
            onPressed: send(label, decision),
          );
          return stacked ? b : IntrinsicWidth(child: b);
        }

        final buttons = [
          button(approve, 'approve', IrisButtonTone.primary),
          button(reject, 'reject', IrisButtonTone.secondary),
          if (ask != null) button(ask, 'ask', IrisButtonTone.secondary),
        ];
        return stacked
            ? _column(buttons, gap: IrisSpace.sm)
            : Wrap(
                spacing: IrisSpace.sm,
                runSpacing: IrisSpace.sm,
                children: buttons,
              );

      case 'Submit':
        final label = _s(e, 'label');
        final action = e.props['action'];
        if (label == null || action is! ActionValue) return null;
        final run = env.onAction;
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: IrisButton(
            label: label,
            tone: IrisButtonTone.primary,
            onPressed: run == null || action.steps.isEmpty
                ? null
                : () => run(action, 'Submit'),
          ),
        );

      case 'Button':
        final label = _s(e, 'label');
        if (label == null) return null;
        final action = e.props['action'];
        final run = env.onAction;
        // Without an action a button sends its label, as `@Ask(label)`.
        final value = action is ActionValue
            ? action
            : ActionValue([
                CustomStep('Ask', {'text': label}),
              ]);
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: IrisButton(
            label: label,
            tone: _s(e, 'variant') == 'primary'
                ? IrisButtonTone.primary
                : IrisButtonTone.secondary,
            onPressed: run == null || value.steps.isEmpty
                ? null
                : () => run(value, 'Button'),
          ),
        );
    }
    return null; // a component this app does not know yet
  }

  /// An input's value: the `$variable` the program bound, else the literal it wrote, else nothing.
  Widget _bound(
    UiElement e,
    Widget Function(Object? value, ValueChanged<Object?> set) build,
  ) {
    final v = e.props['value'];
    return BoundValue(
      store: env.store,
      name: v is Binding ? v.name : null,
      initial: v is Binding ? null : v,
      builder: (context, value, set) => build(value, set),
    );
  }

  List<ChartSeries> _series(UiElement e) => [
    for (final s in _elements(e, 'series', 'Series'))
      if (cleanValues(_list(s, 'values')) case final v when v.isNotEmpty)
        ChartSeries(_s(s, 'name') ?? '', v),
  ].take(kMaxSeries).toList();

  List<ChartSlice> _slices(UiElement e) => [
    for (final s in _elements(e, 'slices', 'Slice'))
      if (_n(s, 'value') case final v? when v > 0 && v.isFinite)
        ChartSlice(_s(s, 'label') ?? '', v),
  ].take(kMaxSlices).toList();

  Widget _stat(BuildContext context, UiElement e) {
    final palette = context.palette;
    final type = context.type;
    final label = _s(e, 'label') ?? '';
    final value = _s(e, 'value') ?? '';
    final delta = _s(e, 'delta');
    final trend = _s(e, 'trend');
    final trendColor = switch (trend) {
      'up' => palette.colorFor(AgentState.done),
      'down' => palette.colorFor(AgentState.failed),
      _ => palette.inkMuted,
    };
    final glyph = switch (trend) {
      'up' => '▲ ',
      'down' => '▼ ',
      'flat' => '– ',
      _ => '',
    };
    return Semantics(
      container: true,
      label: [
        label,
        value,
        ?delta == null ? null : '$delta${trend == null ? '' : ', $trend'}',
      ].join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisLabel(label, small: true),
          const SizedBox(height: IrisSpace.xs),
          Text(
            value,
            style: type.title.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (delta != null)
            Text(
              '$glyph$delta',
              style: type.caption.copyWith(color: trendColor),
            ),
        ],
      ),
    );
  }

  Widget _checkRow(BuildContext context, UiElement e) {
    final palette = context.palette;
    final done = _b(e, 'done');
    final label = _s(e, 'label') ?? '';
    return Semantics(
      container: true,
      label: '$label, ${done ? 'done' : 'not done'}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: IrisSize.icon,
            color: done ? palette.colorFor(AgentState.done) : palette.inkFaint,
          ),
          const SizedBox(width: IrisSpace.sm),
          Expanded(
            child: Text(
              label,
              style: context.type.body.copyWith(
                color: done ? palette.inkMuted : palette.ink,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _table(BuildContext context, UiElement e) {
    final columns = [for (final c in _list(e, 'columns')) jsString(c)];
    if (columns.isEmpty) return null;
    final palette = context.palette;
    final type = context.type;
    final rows = [
      for (final r in _list(e, 'rows'))
        if (r is List) r,
    ];
    TableRow row(List<Widget> cells, {bool header = false}) => TableRow(
      decoration: header
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: palette.line,
                  width: IrisStroke.hairline,
                ),
              ),
            ),
      children: cells,
    );
    Widget cell(String text, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IrisSpace.sm,
        vertical: IrisSpace.sm,
      ),
      child: header
          ? IrisLabel(text, small: true)
          : Text(text, style: type.body),
    );

    return Semantics(
      container: true,
      label: 'Table, ${columns.length} columns, ${rows.length} rows',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            row([for (final c in columns) cell(c, header: true)], header: true),
            for (final r in rows)
              row([
                for (var i = 0; i < columns.length; i++)
                  cell(i < r.length && r[i] != null ? jsString(r[i]) : ''),
              ]),
          ],
        ),
      ),
    );
  }
}
