/// The call's live captions (frame C1): what the person said in sans and what
/// Iris says in serif, bottom-anchored over the orb's quiet state, fading
/// toward the top. The words Iris has started saying are ink; the rest of the
/// sentence waits in muted.
library;

import 'package:flutter/material.dart';

import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'voice_call.dart';

/// Older lines than this are not drawn: they have long since scrolled away.
const _shown = 8;

class CaptionsLayer extends StatelessWidget {
  const CaptionsLayer({required this.captions, super.key});

  final List<Caption> captions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final recent = captions.length > _shown
        ? captions.sublist(captions.length - _shown)
        : captions;
    return Semantics(
      container: true,
      label: 'Live captions',
      child: Stack(
        children: [
          ListView(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(
              IrisSpace.xl,
              IrisSpace.xl,
              IrisSpace.xl,
              IrisSpace.lg,
            ),
            children: [
              for (var i = recent.length - 1; i >= 0; i--)
                Padding(
                  padding: EdgeInsets.only(
                    top: i == recent.length - 1 ? 0 : 20,
                  ),
                  // The newest two are at full strength.
                  child: Opacity(
                    opacity: i >= recent.length - 2 ? 1 : .72,
                    child: _Line(recent[i]),
                  ),
                ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 90,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      palette.canvas,
                      palette.canvas.withValues(alpha: 0),
                    ],
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

class _Line extends StatelessWidget {
  const _Line(this.caption);

  final Caption caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final you = caption.you;
    final heard = caption.heard;
    final text = caption.text;

    final Widget body;
    if (you) {
      body = Text(
        text,
        style: type.body.copyWith(
          fontSize: 16,
          height: 1.45,
          color: palette.inkMuted,
        ),
      );
    } else {
      final base = type.serif.copyWith(
        fontSize: 23,
        height: 1.25,
        fontStyle: FontStyle.italic,
      );
      final ink = base.copyWith(color: palette.ink);
      final split = heard == null ? text.length : heard.clamp(0, text.length);
      body = split >= text.length
          ? Text(text, style: ink)
          : Text.rich(
              TextSpan(
                style: ink,
                children: [
                  if (split > 0)
                    TextSpan(text: text.substring(0, split), style: ink),
                  TextSpan(
                    text: text.substring(split),
                    style: base.copyWith(color: palette.inkMuted),
                  ),
                ],
              ),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          you ? 'YOU' : 'IRIS',
          style: type.codeSmall.copyWith(
            fontSize: 10,
            letterSpacing: 10 * .12,
            color: palette.inkMuted,
          ),
        ),
        const SizedBox(height: 5),
        body,
      ],
    );
  }
}
