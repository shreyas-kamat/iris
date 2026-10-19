/// The server's voice list (frame E1a): the voices it offers, the current one
/// checked. A current voice the list does not know is kept, first, exactly as
/// the server has it.
library;

import 'package:flutter/material.dart';

import '../../data/voice/voice_catalog.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

/// [choices] with [current] first when it is not among them.
List<VoiceChoice> withCurrent(List<VoiceChoice> choices, String? current) {
  if (current == null || current.isEmpty) return choices;
  if (choices.any((choice) => choice.id == current)) return choices;
  return [VoiceChoice(current, current), ...choices];
}

/// The label for [current] in [choices], or the id verbatim; a dash when the
/// server has no voice set.
String currentVoiceLabel(List<VoiceChoice> choices, String? current) {
  if (current == null || current.isEmpty) return '—';
  for (final choice in choices) {
    if (choice.id == current) return choice.label;
  }
  return current;
}

/// Shows the voices and returns the one picked, or null when dismissed.
Future<VoiceChoice?> showVoicePicker(
  BuildContext context, {
  required List<VoiceChoice> choices,
  required String? current,
  required String server,
}) => showIrisSheet<VoiceChoice>(
  context: context,
  builder: (_) => _VoiceSheet(
    choices: withCurrent(choices, current),
    current: current,
    server: server,
  ),
);

class _VoiceSheet extends StatelessWidget {
  const _VoiceSheet({
    required this.choices,
    required this.current,
    required this.server,
  });

  final List<VoiceChoice> choices;
  final String? current;
  final String server;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisSheet(
      title: 'Voice',
      subtitle: 'Offered by $server',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .55,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final choice in choices)
              Semantics(
                button: true,
                selected: choice.id == current,
                label: choice.label,
                excludeSemantics: true,
                child: IrisPressable(
                  onTap: () => Navigator.of(context).pop(choice),
                  ensureTapTarget: false,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: IrisSpace.lg,
                      vertical: IrisSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      color: choice.id == current ? palette.accentQuiet : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                choice.label,
                                style: type.body.copyWith(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                  color: palette.ink,
                                ),
                              ),
                              if (choice.label != choice.id)
                                Text(
                                  choice.id,
                                  style: type.codeSmall.copyWith(
                                    fontSize: 11.5,
                                    color: palette.inkMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (choice.id == current)
                          Icon(Icons.check, size: 18, color: palette.accent),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
