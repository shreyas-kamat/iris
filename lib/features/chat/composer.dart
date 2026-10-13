/// Where the person writes to the agent, and stops it.
library;

import 'package:flutter/material.dart';

import '../../design/components/controls.dart';
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
    super.key,
  });

  final TextEditingController controller;

  /// A turn is in progress: the action becomes Stop.
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// False while the conversation cannot take a message.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gutter = context.window.gutter;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(
          top: BorderSide(color: palette.line, width: IrisStroke.hairline),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: IrisField(
                controller: controller,
                hint: 'Message your agent',
                // Starts one line tall and grows, so an empty composer does
                // not take a fifth of the screen.
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
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => IrisButton(
                  label: 'Send',
                  tone: IrisButtonTone.primary,
                  onPressed: enabled && value.text.trim().isNotEmpty
                      ? onSend
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
