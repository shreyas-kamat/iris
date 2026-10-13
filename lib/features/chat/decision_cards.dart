/// Cards for the moments the agent waits on the person: an approval, a
/// question.
library;

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    required this.request,
    required this.onChoose,
    super.key,
  });

  final ApprovalRequest request;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final waiting = palette.colorFor(AgentState.waiting);
    // The first choice that allows is the primary action; deny is marked as
    // the destructive one, whatever order the gateway sent.
    final primary = request.choices.firstWhere(
      (choice) => choice != 'deny',
      orElse: () => '',
    );
    return IrisCard(
      accent: waiting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisLabel('Approval needed', color: waiting),
          const SizedBox(height: IrisSpace.xs),
          Text(
            request.description,
            style: theme.typography.body.copyWith(color: palette.ink),
          ),
          if (request.command.isNotEmpty) ...[
            const SizedBox(height: IrisSpace.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: const BorderRadius.all(IrisRadius.xs),
              ),
              child: Padding(
                padding: const EdgeInsets.all(IrisSpace.sm),
                child: SelectableText(
                  request.command,
                  style: theme.typography.codeSmall.copyWith(
                    color: palette.ink,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: IrisSpace.md),
          Wrap(
            spacing: IrisSpace.sm,
            runSpacing: IrisSpace.sm,
            children: [
              for (final choice in request.choices)
                IrisButton(
                  label: ApprovalRequest.labelFor(choice),
                  tone: choice == 'deny'
                      ? IrisButtonTone.danger
                      : choice == primary
                      ? IrisButtonTone.primary
                      : IrisButtonTone.secondary,
                  onPressed: () => onChoose(choice),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ClarifyCard extends StatefulWidget {
  const ClarifyCard({required this.request, required this.onAnswer, super.key});

  final ClarifyRequest request;

  /// Called with the question being answered and the answer.
  final void Function(ClarifyQuestion question, String answer) onAnswer;

  @override
  State<ClarifyCard> createState() => _ClarifyCardState();
}

class _ClarifyCardState extends State<ClarifyCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send(ClarifyQuestion question, String answer) {
    if (answer.trim().isEmpty) return;
    _text.clear();
    widget.onAnswer(question, answer.trim());
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.request.questions;
    if (questions.isEmpty) return const SizedBox.shrink();
    final theme = context.iris;
    final palette = theme.palette;
    final waiting = palette.colorFor(AgentState.waiting);
    final question = questions.first;
    return IrisCard(
      accent: waiting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisLabel(
            questions.length > 1
                ? 'Question · ${questions.length} left'
                : 'Question',
            color: waiting,
          ),
          const SizedBox(height: IrisSpace.xs),
          Text(
            question.text,
            style: theme.typography.body.copyWith(color: palette.ink),
          ),
          if (question.choices.isNotEmpty) ...[
            const SizedBox(height: IrisSpace.md),
            Wrap(
              spacing: IrisSpace.sm,
              runSpacing: IrisSpace.sm,
              children: [
                for (final choice in question.choices)
                  IrisButton(
                    label: choice.label,
                    onPressed: () => _send(question, choice.value),
                  ),
              ],
            ),
          ],
          const SizedBox(height: IrisSpace.md),
          Row(
            children: [
              Expanded(
                child: IrisField(
                  controller: _text,
                  hint: question.choices.isEmpty
                      ? 'Your answer'
                      : 'Or type an answer',
                  onSubmitted: (text) => _send(question, text),
                ),
              ),
              const SizedBox(width: IrisSpace.sm),
              IrisButton(
                label: 'Answer',
                tone: IrisButtonTone.primary,
                onPressed: () => _send(question, _text.text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
