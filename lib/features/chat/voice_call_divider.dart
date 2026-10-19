/// Where a voice call sits in the chat transcript (frame C2): a quiet line
/// before its first message, "voice · 4 min", and another after its last,
/// "call ended 4:12".
library;

import 'package:flutter/material.dart';

import '../../app/device_state.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

/// "40 s" under a minute, otherwise whole minutes ("4 min").
String callLengthLabel(Duration length) {
  final seconds = length.inSeconds;
  if (seconds < 60) return '$seconds s';
  return '${(seconds / 60).round()} min';
}

/// "4:12", or "1:02:03" past the hour.
String callEndedClock(Duration length) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = two(length.inSeconds % 60);
  if (length.inHours > 0) {
    return '${length.inHours}:${two(length.inMinutes % 60)}:$seconds';
  }
  return '${length.inMinutes}:$seconds';
}

/// Which messages of [itemCount] each of [spans] covers: the index each call
/// starts at and the index of its last message. A call that produced nothing,
/// or that lies past the transcript, is left out; one with no end recorded
/// ends where the next call or the transcript does.
({Map<int, VoiceCallSpan> starts, Map<int, VoiceCallSpan> ends}) callMarks(
  List<VoiceCallSpan> spans,
  int itemCount,
) {
  final starts = <int, VoiceCallSpan>{};
  final ends = <int, VoiceCallSpan>{};
  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    final next = i + 1 < spans.length ? spans[i + 1].fromIndex : itemCount;
    final to = (span.toIndex ?? next).clamp(0, itemCount);
    if (span.fromIndex >= itemCount || to <= span.fromIndex) continue;
    starts[span.fromIndex] = span;
    ends[to - 1] = span;
  }
  return (starts: starts, ends: ends);
}

/// One of the two lines, with a hairline either side.
class VoiceCallDivider extends StatelessWidget {
  const VoiceCallDivider.start(this.span, {super.key}) : ended = false;
  const VoiceCallDivider.end(this.span, {super.key}) : ended = true;

  final VoiceCallSpan span;

  /// The "call ended" line, not the "voice" one.
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = ended
        ? 'call ended ${callEndedClock(span.length)}'
        : 'voice · ${callLengthLabel(span.length)}';
    final rule = Expanded(
      child: Container(height: IrisStroke.hairline, color: palette.line),
    );
    return Row(
      children: [
        rule,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IrisSpace.md),
          child: Text(
            label,
            style: context.type.codeSmall.copyWith(
              fontSize: 11,
              color: palette.inkMuted,
            ),
          ),
        ),
        rule,
      ],
    );
  }
}
