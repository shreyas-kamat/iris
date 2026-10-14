/// How full the conversation's context window is, in words and numbers.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

Future<void> showContextSheet(
  BuildContext context,
  ContextUsage usage, {
  String? model,
}) {
  unawaited(IrisHaptics.selection());
  return showIrisSheet<void>(
    context: context,
    builder: (_) => IrisSheet(
      title: 'Context window',
      child: _ContextDetail(usage: usage, model: model),
    ),
  );
}

/// `48210` as `48,210`.
String groupedNumber(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

class _ContextDetail extends StatelessWidget {
  const _ContextDetail({required this.usage, this.model});

  final ContextUsage usage;
  final String? model;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final used = usage.used;
    final max = usage.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${usage.percent.round()}%',
          style: type.serif.copyWith(fontSize: 44, color: palette.ink),
        ),
        const SizedBox(height: IrisSpace.sm),
        IrisGauge(value: usage.percent / 100, width: null),
        const SizedBox(height: IrisSpace.md),
        if (used != null && max != null)
          Text(
            '${groupedNumber(used)} of ${groupedNumber(max)} tokens',
            style: type.body.copyWith(color: palette.ink),
          ),
        if (model case final model?) ...[
          const SizedBox(height: IrisSpace.xs),
          Text(model, style: type.codeSmall.copyWith(color: palette.inkMuted)),
        ],
      ],
    );
  }
}
