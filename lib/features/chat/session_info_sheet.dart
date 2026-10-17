/// What is known about the open conversation (frame C3). A row with no data
/// is left out rather than filled in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/sheet.dart';
import '../../design/components/toast.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'relative_time.dart';

class SessionInfo {
  const SessionInfo({
    required this.title,
    required this.profile,
    this.model,
    this.lastActive,
    this.messages,
    this.contextPercent,
    this.contextUsed,
    this.contextMax,
    this.sessionId,
  });

  final String title;
  final String profile;
  final String? model;
  final DateTime? lastActive;
  final int? messages;
  final double? contextPercent;
  final int? contextUsed;
  final int? contextMax;
  final String? sessionId;
}

/// 950, 61.2k, 200k, 1.3M.
String compactTokens(int value) {
  String trim(double v) {
    final text = v.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  if (value >= 1000000) return '${trim(value / 1000000)}M';
  if (value >= 1000) return '${trim(value / 1000)}k';
  return '$value';
}

Future<void> showSessionInfo(BuildContext context, SessionInfo info) {
  unawaited(HapticFeedback.selectionClick());
  return showIrisSheet<void>(
    context: context,
    builder: (sheetContext) => IrisSheet(
      title: info.title,
      child: _SessionInfoBody(info: info),
    ),
  );
}

class _SessionInfoBody extends StatelessWidget {
  const _SessionInfoBody({required this.info});

  final SessionInfo info;

  String? get _context {
    final percent = info.contextPercent;
    if (percent == null) return null;
    final head = '${percent.round()}%';
    final used = info.contextUsed;
    final max = info.contextMax;
    if (used != null && max != null) {
      return '$head · ${compactTokens(used)} of ${compactTokens(max)}';
    }
    return head;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final now = DateTime.now();
    final id = info.sessionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IrisSettingsGroup(
          title: 'Session',
          children: [
            IrisSettingsRow(label: 'Profile', value: info.profile),
            if (info.model case final model?)
              IrisSettingsRow(label: 'Model', value: model),
            if (info.lastActive case final at?)
              IrisSettingsRow(
                label: 'Last active',
                value: relativeTime(at, now),
              ),
            if (info.messages case final count?)
              IrisSettingsRow(label: 'Messages', value: '$count'),
            if (_context case final usage?)
              IrisSettingsRow(label: 'Context', value: usage),
          ],
        ),
        if (id != null) ...[
          const SizedBox(height: IrisSpace.lg),
          IrisLabel('Session id', color: palette.inkFaint),
          const SizedBox(height: IrisSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: IrisSpace.md,
              vertical: IrisSpace.sm,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceSunken,
              borderRadius: const BorderRadius.all(IrisRadius.sm),
              border: Border.all(
                color: palette.line,
                width: IrisStroke.hairline,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    id,
                    style: type.code.copyWith(color: palette.ink),
                  ),
                ),
                IrisButton(
                  label: 'Copy',
                  tone: IrisButtonTone.ghost,
                  onPressed: () {
                    unawaited(Clipboard.setData(ClipboardData(text: id)));
                    showIrisToast(
                      context,
                      message: 'Copied session id',
                      top: true,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
