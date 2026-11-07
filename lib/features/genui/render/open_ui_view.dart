/// Shows one OpenUI Lang program as native Iris widgets (plan 3.3).
///
/// Owns a [StreamingParser] and a [StateStore]. The program arrives whole (a tool call carries it complete), but the
/// view also takes a growing string: it re-parses incrementally and shows a skeleton for the part still to come.
/// When the program cannot be shown at all it falls back to the reply's own Markdown text.
library;

import 'package:flutter/material.dart';
import 'package:openui_lang/openui_lang.dart' hide Element;

import '../../../design/components/markdown.dart';
import '../../../design/components/primitives.dart';
import '../../../design/theme/iris_theme.dart';
import '../../../design/tokens/metrics.dart';
import 'iris_functions.dart';
import 'iris_library.dart';
import 'node_builder.dart';
import 'node_widgets.dart';

class OpenUiView extends StatefulWidget {
  const OpenUiView({
    required this.code,
    this.fallback,
    this.streaming = false,
    this.env = const NodeEnv(),
    this.maxHeight = 480,
    this.now,
    super.key,
  });

  /// The program text.
  final String code;

  /// The reply's Markdown text, shown when the program cannot be.
  final String? fallback;

  /// True while [code] is still growing.
  final bool streaming;

  final NodeEnv env;

  /// Taller displays are cut here with a "Show all" button.
  final double maxHeight;

  /// The clock `@Ago` measures from; tests pass a fixed one.
  final DateTime Function()? now;

  /// The v1 library, built once.
  static final LibrarySpec library = IrisLibrary.toLibrarySpec();

  @override
  State<OpenUiView> createState() => _OpenUiViewState();
}

class _OpenUiViewState extends State<OpenUiView> {
  final _parser = StreamingParser(OpenUiView.library);
  final _store = StateStore();
  late final void Function() _unlisten;
  late final Map<String, OpenUiFunction> _functions;

  ParseResult? _result;
  Evaluator? _evaluator;
  EvaluatedRoot? _evaluated;
  bool _overflowing = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _functions = irisFunctions(now: widget.now);
    _unlisten = _store.listen(() {
      final evaluator = _evaluator;
      if (evaluator != null && mounted) {
        setState(() => _evaluated = evaluator.evaluateRoot());
      }
    });
    _parse();
  }

  @override
  void didUpdateWidget(OpenUiView old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.streaming != widget.streaming) {
      _parse();
    }
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  void _parse() {
    final result = widget.streaming
        ? _parser.set(widget.code)
        : _parser.end(widget.code);
    final evaluator = Evaluator(
      result,
      OpenUiView.library,
      store: _store,
      functions: _functions,
    );
    _result = result;
    _evaluator = evaluator;
    _evaluated = evaluator.evaluateRoot();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result!;
    final evaluated = _evaluated!;
    final root = evaluated.root;
    final pending =
        widget.streaming || result.incomplete || result.unresolved.isNotEmpty;

    if (result.hasFatalError || (root == null && !pending)) {
      return _fallback(context);
    }
    if (root == null) {
      return const IrisSurfaceSkeleton();
    }

    final dropped = {
      ...result.errors,
      ...evaluated.errors,
    }.where((e) => !e.isFatal).length;
    final content = NodeBuilder(
      env: widget.env.copyWith(onAction: _run, store: _store),
    ).surface(context, root, pending: pending, errorCount: dropped);
    return _clamped(context, content);
  }

  /// Runs the steps of an action in order. `@Set` and `@Reset` change this display's own variables; a question for the
  /// assistant and a link go to the host, which owns the chat and the confirmation. A step the host does not handle
  /// (no [NodeEnv.onAsk]) is dropped, never thrown.
  void _run(ActionValue action, String component) {
    final evaluator = _evaluator;
    if (evaluator == null) return;
    final env = widget.env;
    for (final step in action.steps) {
      switch (step) {
        case SetStep():
          _store.set(step.target, evaluator.evaluateStepValue(step));
        case ResetStep():
          _store.reset(step.targets);
        case OpenUrlStep():
          env.onOpenUrl?.call(step.url);
        case ToAssistantStep():
          if (step.message.trim().isNotEmpty) {
            env.onAsk?.call(step.message, step.context, component);
          }
        case CustomStep(name: 'Ask'):
          final text = step.params['text'];
          if (text is String && text.trim().isNotEmpty) {
            env.onAsk?.call(text, step.params['context'], component);
          }
        case RunStep() || CustomStep():
          break; // no queries or mutations in v1, and no other library actions yet
      }
    }
  }

  Widget _fallback(BuildContext context) {
    final text = widget.fallback;
    if (text == null || text.trim().isEmpty) return const IrisCantShow();
    return IrisMarkdown(text, onTapLink: widget.env.onOpenUrl);
  }

  /// Cuts a tall display at [OpenUiView.maxHeight] and offers the rest. One widget structure is kept either way, so
  /// opening it does not rebuild (and so reset) the tabs and expanders inside.
  Widget _clamped(BuildContext context, Widget content) {
    final palette = context.palette;
    final cut = _overflowing && !_expanded;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        final over = n.metrics.maxScrollExtent > 0.5;
        if (over != _overflowing && n.metrics.axis == Axis.vertical) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _overflowing = over);
          });
        }
        return false;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _expanded ? double.infinity : widget.maxHeight,
                ),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: content,
                ),
              ),
              if (cut)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 36,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            palette.canvas.withValues(alpha: 0),
                            palette.canvas,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_overflowing)
            Align(
              alignment: Alignment.centerLeft,
              child: IrisPressable(
                onTap: () => setState(() => _expanded = !_expanded),
                semanticLabel: _expanded
                    ? 'Show less of this display'
                    : 'Show all of this display',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: IrisSpace.xs),
                    child: IrisLabel(
                      _expanded ? 'Show less' : 'Show all',
                      color: palette.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
