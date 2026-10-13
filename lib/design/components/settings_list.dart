/// Grouped settings rows: a mono label over a card of rows, each with an
/// optional value, chevron or control on the right.
///
/// This is the design's settings language. Groups are quiet cards with hairline
/// dividers between rows, so a long list reads as a few sections rather than as
/// a wall of identical lines.
library;

import 'package:flutter/material.dart';

import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import 'primitives.dart';

/// A labelled card of settings rows.
class IrisSettingsGroup extends StatelessWidget {
  const IrisSettingsGroup({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;

  /// Usually [IrisSettingsRow]s. Any widget works, but the dividers are placed
  /// between children, so each child should be one row.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IrisSpace.sm - 2),
          child: IrisLabel(title, color: palette.inkFaint),
        ),
        const SizedBox(height: IrisSpace.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.all(IrisRadius.lg),
            border: Border.all(color: palette.line, width: IrisStroke.hairline),
          ),
          // Clipped so a pressed row's ink stays inside the card's rounded
          // corners.
          child: ClipRRect(
            borderRadius: const BorderRadius.all(IrisRadius.lg),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  // The divider is drawn by the group rather than by each row,
                  // so the first row never needs to know it is first.
                  if (i > 0)
                    ColoredBox(
                      color: palette.line,
                      child: const SizedBox(
                        height: IrisStroke.hairline,
                        width: double.infinity,
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One settings row. Its right-hand side is, in order of precedence: a
/// [trailing] control, the [value] in mono, or a chevron when the row can be
/// tapped.
class IrisSettingsRow extends StatelessWidget {
  const IrisSettingsRow({
    required this.label,
    this.sub,
    this.value,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String label;

  /// A line of explanation under the label.
  final String? sub;

  /// The current value, shown in mono. Hidden when [trailing] is given.
  final String? value;

  /// A control such as an `IrisSwitch`. It replaces the value and the chevron,
  /// so a row never shows both a switch and a chevron that means something else.
  final Widget? trailing;

  /// Null makes the row static: no chevron and no press response.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;

    final Widget end;
    if (trailing != null) {
      end = trailing!;
    } else {
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value!,
              style: type.codeSmall.copyWith(
                fontSize: 12,
                color: palette.inkMuted,
              ),
            ),
          if (onTap != null) ...[
            if (value != null) const SizedBox(width: IrisSpace.sm),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: palette.lineStrong,
            ),
          ],
        ],
      );
    }

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IrisSpace.lg,
        vertical: IrisSpace.md + 1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: type.body.copyWith(
                    fontSize: 14.5,
                    height: 1.3,
                    color: palette.ink,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: IrisSpace.xxs),
                  Text(
                    sub!,
                    style: type.caption.copyWith(
                      fontSize: 12,
                      color: palette.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: IrisSpace.md),
          end,
        ],
      ),
    );

    if (onTap == null) return row;
    return IrisPressable(
      onTap: onTap,
      scale: 0.99,
      ensureTapTarget: false,
      child: row,
    );
  }
}
