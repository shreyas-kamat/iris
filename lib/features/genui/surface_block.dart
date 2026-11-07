/// A generated display in the transcript (plan 3.5): drawn from the program the `iris_ui` call carried, or from the
/// stored surface fetched by id when the call did not carry one (a template, or arguments that arrived cut short).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../data/genui/genui_models.dart';
import '../../data/genui/genui_parser.dart';
import '../../design/components/controls.dart';
import '../../design/components/markdown.dart';
import '../../design/tokens/metrics.dart';
import 'render/node_builder.dart';
import 'render/node_widgets.dart';
import 'render/open_ui_view.dart';

/// Fetches the stored display [surfaceId] of the open conversation, or null when it cannot be had.
typedef SurfaceLoader = Future<UiSurface?> Function(String surfaceId);

class SurfaceBlock extends StatefulWidget {
  const SurfaceBlock(
    this.item, {
    this.loadSurface,
    this.env = const NodeEnv(),
    this.onUiAction,
    super.key,
  });

  final UiSurfaceItem item;
  final SurfaceLoader? loadSurface;
  final NodeEnv env;

  /// The person asked the assistant something from this display: the sentence to send as their message and the
  /// hidden block that says where it came from. The host sends it as a chat message.
  final void Function(String text, IrisActionEnvelope action)? onUiAction;

  @override
  State<SurfaceBlock> createState() => _SurfaceBlockState();
}

class _SurfaceBlockState extends State<SurfaceBlock> {
  Future<UiSurface?>? _fetch;

  UiSurfaceRef get _ref => widget.item.ref;

  /// The call's own program, when it came whole and needs no expanding.
  bool get _hasCode =>
      (_ref.code?.trim().isNotEmpty ?? false) && _ref.template == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SurfaceBlock old) {
    super.didUpdateWidget(old);
    final was = old.item.ref;
    if (was.surfaceId != _ref.surfaceId ||
        was.rev != _ref.rev ||
        was.code != _ref.code) {
      _load();
    }
  }

  void _load() {
    final loader = widget.loadSurface;
    _fetch = _hasCode || loader == null
        ? null
        : loader(_ref.surfaceId).catchError((Object _) => null);
  }

  /// The host's env with the ask wired to this display: it adds which display and component it came from.
  NodeEnv get _env {
    final send = widget.onUiAction;
    if (send == null) return widget.env;
    return NodeEnv(
      onAsk: (text, context, component) => send(
        text,
        IrisActionEnvelope(
          surface: _ref.surfaceId,
          component: component,
          context: context,
        ),
      ),
      onOpenUrl: widget.env.onOpenUrl,
      maxDepth: widget.env.maxDepth,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reply kits sit above the composer, not in the transcript.
    if (_ref.placement == SurfacePlacement.replyKit) {
      return const SizedBox.shrink();
    }
    if (_hasCode) {
      return OpenUiView(code: _ref.code!, fallback: _ref.fallback, env: _env);
    }
    final fetch = _fetch;
    if (fetch == null) return _fallback(context);
    return FutureBuilder<UiSurface?>(
      future: fetch,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const IrisSurfaceSkeleton();
        }
        final surface = snapshot.data;
        final code = surface?.code;
        if (surface == null || code == null || code.trim().isEmpty) {
          return _fallback(context, retry: true);
        }
        return OpenUiView(
          code: code,
          fallback: surface.fallback ?? _ref.fallback,
          env: _env,
        );
      },
    );
  }

  /// The reply's own text for the display, or a quiet note that it cannot be shown.
  Widget _fallback(BuildContext context, {bool retry = false}) {
    final text = _ref.fallback;
    if (text != null && text.trim().isNotEmpty) {
      return IrisMarkdown(text, onTapLink: widget.env.onOpenUrl);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IrisCantShow(what: 'display'),
        if (retry && widget.loadSurface != null) ...[
          const SizedBox(height: IrisSpace.xs),
          IrisButton(
            label: 'Try again',
            tone: IrisButtonTone.ghost,
            onPressed: () => setState(_load),
          ),
        ],
      ],
    );
  }
}
