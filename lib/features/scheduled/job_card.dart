/// One job in the Scheduled list (frame A2).
library;

import 'package:flutter/material.dart';

import '../../data/automation/cron_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'schedule_text.dart';

class JobCard extends StatelessWidget {
  const JobCard({
    required this.job,
    required this.now,
    required this.onOpen,
    required this.onToggle,
    super.key,
  });

  final CronJob job;
  final DateTime now;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final status = statusOf(job);
    final line = statusLine(job, now);
    final lineColor = status == JobStatus.failed
        ? palette.colorFor(AgentState.failed)
        : palette.inkMuted;
    return IrisPressable(
      onTap: onOpen,
      semanticLabel: '${job.title}, ${job.scheduleText}, $line',
      child: IrisCard(
        padding: const EdgeInsets.fromLTRB(
          IrisSpace.lg,
          IrisSpace.md,
          IrisSpace.sm,
          IrisSpace.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: IrisSpace.sm),
                  Wrap(
                    spacing: IrisSpace.sm,
                    runSpacing: IrisSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Verbatim and in mono: IrisChip would uppercase a cron
                      // expression.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.surfaceSunken,
                          borderRadius: const BorderRadius.all(IrisRadius.xs),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: IrisSpace.sm - 1,
                            vertical: 3,
                          ),
                          child: Text(
                            job.scheduleText,
                            style: type.codeSmall.copyWith(
                              fontSize: 11,
                              color: palette.inkMuted,
                            ),
                          ),
                        ),
                      ),
                      if (line.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status == JobStatus.running) ...[
                              const IrisOrb(state: AgentState.working, size: 16),
                              const SizedBox(width: IrisSpace.xs),
                            ],
                            Text(
                              line,
                              style: type.caption.copyWith(
                                fontSize: 11.5,
                                color: lineColor,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // A 44 pt target around a 30 pt switch.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggle(!job.enabled),
              child: SizedBox(
                width: 60,
                height: 44,
                child: Center(
                  child: IrisSwitch(
                    value: job.enabled,
                    semanticLabel: 'Enabled, ${job.title}',
                    onChanged: onToggle,
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
