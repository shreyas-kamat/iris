/// "While Hermes is replying": what sending a message mid-reply does.
///
/// One Hermes setting with three modes, per profile, read from and written
/// to the server (`display.busy_input_mode`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

/// The profile's current mode, or null when the server has no such setting
/// (the row is then hidden) or there is no live link.
final busyModeProvider = FutureProvider.autoDispose<BusyMode?>((ref) async {
  final chat = await ref.watch(activeChatProvider.future);
  if (chat == null) return null;
  return (await chat.busyMode()).valueOrNull;
});

/// Shows the three modes and returns the one picked (the current one counts:
/// the sheet closes either way). The choice is saved by the caller.
Future<BusyMode?> showBusyPicker(
  BuildContext context, {
  required BusyMode current,
  required String profile,
  required String host,
}) => showIrisSheet<BusyMode>(
  context: context,
  builder: (sheetContext) =>
      _BusySheet(current: current, profile: profile, host: host),
);

class _BusySheet extends StatefulWidget {
  const _BusySheet({
    required this.current,
    required this.profile,
    required this.host,
  });

  final BusyMode current;
  final String profile;
  final String host;

  @override
  State<_BusySheet> createState() => _BusySheetState();
}

class _BusySheetState extends State<_BusySheet> {
  late BusyMode _selected = widget.current;

  void _pick(BusyMode mode) {
    setState(() => _selected = mode);
    // The sheet closes a beat after the choice, so the radio is seen to move.
    final wait = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    unawaited(
      Future<void>.delayed(wait, () {
        if (mounted) Navigator.of(context).pop(mode);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisSheet(
      title: 'While Hermes is replying',
      subtitle: 'What should happen when you send a message mid-reply?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in BusyMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: IrisSpace.xs),
              child: Semantics(
                button: true,
                selected: mode == _selected,
                label: '${mode.label}. ${mode.blurb}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pick(mode),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: mode == _selected ? palette.accentQuiet : null,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        _IrisRadio(selected: mode == _selected),
                        const SizedBox(width: IrisSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mode.label,
                                style: type.body.copyWith(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                  color: palette.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                mode.blurb,
                                style: type.body.copyWith(
                                  fontSize: 13.5,
                                  color: palette.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: IrisSpace.sm),
            child: Text(
              'Applies to the ${widget.profile} profile on ${widget.host}.',
              style: type.codeSmall.copyWith(
                fontSize: 11.5,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small iris as the radio: a ring, and a dot when chosen.
class _IrisRadio extends StatelessWidget {
  const _IrisRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? palette.accent : palette.lineStrong,
          width: selected ? 2.5 : 2,
        ),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
