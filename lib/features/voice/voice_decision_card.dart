/// What the call shows while the agent waits on the person (frames B9a and
/// B9b): the command to approve, or the choices to a question. Everything
/// here can also be said aloud; a tap always works.
library;

import 'package:flutter/material.dart';

import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'spoken.dart';
import 'voice_call.dart';

class VoiceDecisionCard extends StatelessWidget {
  const VoiceDecisionCard({
    required this.decision,
    required this.onApprove,
    required this.onAnswer,
    super.key,
  });

  final CallDecision decision;
  final void Function(SpokenVerdict verdict) onApprove;
  final void Function(String answer) onAnswer;

  @override
  Widget build(BuildContext context) {
    return switch (decision) {
      final ApprovalDecision approval => _ApprovalCard(
        approval: approval,
        onApprove: onApprove,
      ),
      final QuestionDecision question => _QuestionCard(
        question: question,
        onAnswer: onAnswer,
      ),
    };
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.approval, required this.onApprove});

  final ApprovalDecision approval;
  final void Function(SpokenVerdict verdict) onApprove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mono = context.type.codeSmall.copyWith(fontSize: 12.5);
    final description = approval.request.description.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (approval.command.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: IrisSpace.md,
            ),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              approval.command,
              style: mono.copyWith(color: palette.ink),
            ),
          ),
        if (description.isNotEmpty && description != approval.command) ...[
          const SizedBox(height: IrisSpace.sm),
          Text(
            description,
            textAlign: TextAlign.center,
            style: context.type.caption.copyWith(color: palette.inkMuted),
          ),
        ],
        const SizedBox(height: IrisSpace.lg),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: _Buttons(
            // Side by side unless the text is so large that they would not
            // fit.
            stacked: MediaQuery.textScalerOf(context).scale(1) > 1.5,
            deny: IrisButton(
              label: 'Deny',
              expand: true,
              onPressed: () => onApprove(SpokenVerdict.deny),
            ),
            approve: IrisButton(
              label: 'Approve',
              tone: IrisButtonTone.primary,
              expand: true,
              onPressed: () => onApprove(SpokenVerdict.approve),
            ),
          ),
        ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.stacked,
    required this.deny,
    required this.approve,
  });

  final bool stacked;
  final Widget deny;
  final Widget approve;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        children: [
          approve,
          const SizedBox(height: IrisSpace.sm),
          deny,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: deny),
        const SizedBox(width: IrisSpace.md),
        Expanded(child: approve),
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.question, required this.onAnswer});

  final QuestionDecision question;
  final void Function(String answer) onAnswer;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final _text = TextEditingController();
  bool _typing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final answer = _text.text.trim();
    if (answer.isEmpty) return;
    widget.onAnswer(answer);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in widget.question.question.choices) ...[
            _ChoiceButton(
              label: choice.label,
              onTap: () => widget.onAnswer(choice.value),
            ),
            const SizedBox(height: IrisSpace.sm),
          ],
          if (_typing) ...[
            TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: context.type.body.copyWith(color: palette.ink),
              cursorColor: palette.accent,
              decoration: InputDecoration(
                hintText: 'Type your answer',
                hintStyle: context.type.body.copyWith(color: palette.inkFaint),
                filled: true,
                fillColor: palette.surfaceSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.line),
                ),
              ),
            ),
            const SizedBox(height: IrisSpace.sm),
            _ChoiceButton(label: 'Send', primary: true, onTap: _send),
          ] else
            _ChoiceButton(
              label: 'Something else…',
              quiet: true,
              onTap: () => setState(() => _typing = true),
            ),
        ],
      ),
    );
  }
}

/// A full-width answer. Unlike a button, its label wraps: the agent writes
/// the choices, and they can be as long as it likes.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: IrisPressable(
        onTap: onTap,
        ensureTapTarget: false,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
            horizontal: IrisSpace.lg,
            vertical: IrisSpace.md,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? palette.accent : palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: quiet ? null : Border.all(color: palette.lineStrong),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.type.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: primary
                  ? palette.accentInk
                  : quiet
                  ? palette.inkMuted
                  : palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}
