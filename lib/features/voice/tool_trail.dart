/// B5's tool detail: the running tool in a mono pill, and the tools already
/// finished this turn beneath it in muted mono.
library;

import 'package:flutter/material.dart';

import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

/// "name · input" split at the first separator. A tool with no input is the
/// name alone.
(String name, String? input) splitTool(String tool) {
  const separator = ' · ';
  final at = tool.indexOf(separator);
  if (at < 0) return (tool, null);
  return (tool.substring(0, at), tool.substring(at + separator.length));
}

/// The running tool.
class ToolPill extends StatelessWidget {
  const ToolPill({required this.tool, super.key});

  final String tool;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (name, input) = splitTool(tool);
    final mono = context.type.codeSmall.copyWith(fontSize: 12.5);
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: IrisSpace.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: IrisSpace.sm,
        children: [
          Text(
            name,
            style: mono.copyWith(
              color: palette.voiceOrbColor(VoiceOrbMode.tool),
            ),
          ),
          if (input != null) ...[
            Text('·', style: mono.copyWith(color: palette.inkMuted)),
            Text(
              input,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(color: palette.ink),
            ),
          ],
        ],
      ),
    );
  }
}

/// The finished tools of this turn, oldest first, each with a tick.
class ToolTrail extends StatelessWidget {
  const ToolTrail({required this.tools, super.key});

  final List<String> tools;

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    final style = context.type.codeSmall.copyWith(
      fontSize: 11.5,
      color: palette.inkMuted,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tool in tools)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check,
                      size: 12,
                      color: palette.colorFor(AgentState.done),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(child: Text(tool, style: style)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
