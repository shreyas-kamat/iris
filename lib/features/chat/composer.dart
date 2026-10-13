/// Where the person writes to the agent, stops it, and finds slash commands.
library;

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.running,
    required this.onSend,
    required this.onStop,
    this.enabled = true,
    this.commands = const [],
    super.key,
  });

  final TextEditingController controller;

  /// A turn is in progress: the action becomes Stop.
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// False while the conversation cannot take a message.
  final bool enabled;

  /// Slash commands to suggest while the person types one.
  final List<SlashCommand> commands;

  /// At most this many suggestions show, so they never hide the transcript.
  static const suggestions = 5;

  /// Commands matching what has been typed: a slash and the start of a name,
  /// before any argument.
  List<SlashCommand> _matching(String text) {
    if (!text.startsWith('/') || text.contains(' ') || commands.isEmpty) {
      return const [];
    }
    final query = text.toLowerCase();
    return commands
        .where((command) => command.name.toLowerCase().startsWith(query))
        .take(suggestions)
        .toList();
  }

  void _choose(SlashCommand command) {
    final text = '${command.name} ';
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final gutter = context.window.gutter;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final matching = _matching(value.text);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.canvas,
            border: Border(
              top: BorderSide(color: palette.line, width: IrisStroke.hairline),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              IrisSpace.sm,
              gutter,
              IrisSpace.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final command in matching)
                  IrisPressable(
                    onTap: () => _choose(command),
                    semanticLabel: '${command.name}, ${command.description}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: IrisSpace.xs,
                      ),
                      child: Row(
                        children: [
                          Text(
                            command.name,
                            style: theme.typography.code.copyWith(
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(width: IrisSpace.sm),
                          Expanded(
                            child: Text(
                              command.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.caption.copyWith(
                                color: palette.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (matching.isNotEmpty) const SizedBox(height: IrisSpace.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: IrisField(
                        controller: controller,
                        hint: 'Message your agent',
                        // Starts one line tall and grows, so an empty
                        // composer does not take a fifth of the screen.
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                    const SizedBox(width: IrisSpace.sm),
                    if (running)
                      IrisButton(
                        label: 'Stop',
                        tone: IrisButtonTone.danger,
                        onPressed: onStop,
                      )
                    else
                      IrisButton(
                        label: 'Send',
                        tone: IrisButtonTone.primary,
                        onPressed: enabled && value.text.trim().isNotEmpty
                            ? onSend
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
