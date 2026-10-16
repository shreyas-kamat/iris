/// Cards for the moments the agent waits on the person: an approval, a
/// question.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/needs_you_card.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/platform_feel.dart';
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

/// A prompt for a value that must never be shown or kept: a sudo password, a
/// secret, a password-manager unlock or one-time code. It is a
/// [NeedsYouCard]; nothing typed outlives it, and the answer is handed over
/// and the field cleared in the same moment.
class InputCard extends StatefulWidget {
  const InputCard({required this.request, required this.onAnswer, super.key});

  final InputRequest request;

  /// Called with the value, or `''` to skip.
  final Future<void> Function(String value) onAnswer;

  /// Whether a code prompt wants six one-digit cells: only when Hermes's
  /// hint says six. Other codes (backup codes, longer ones) get one field.
  static bool wantsSixCells(String hint) =>
      RegExp(r'\b(6|six)\b', caseSensitive: false).hasMatch(hint);

  @override
  State<InputCard> createState() => _InputCardState();
}

class _InputCardState extends State<InputCard> {
  final _text = TextEditingController();
  bool _revealed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Something is waiting on the person; the phone says so once.
    unawaited(IrisHaptics.gate());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String value) async {
    if (_sending) return;
    if (value.isNotEmpty) unawaited(IrisHaptics.commit());
    setState(() => _sending = true);
    // Cleared before the answer leaves, so the value lives in no widget
    // while the request is in flight.
    _text.clear();
    await widget.onAnswer(value);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final palette = context.palette;
    final type = context.type;
    final (eyebrow, title, subtitle, skip, primary) = switch (request.kind) {
      InputKind.sudo => (
        'Needs you · sudo',
        'Run this as root?',
        null,
        'Deny',
        'Run',
      ),
      InputKind.secret => (
        'Needs you · secret',
        request.prompt.isEmpty ? 'Add a secret' : request.prompt,
        null,
        'Skip',
        'Save',
      ),
      InputKind.vaultUnlock => (
        'Needs you · unlock',
        request.title,
        'Hermes needs your login to carry on.',
        'Skip',
        'Unlock',
      ),
      InputKind.vaultCode => (
        'Needs you · one-time code',
        request.title,
        request.hint.isEmpty ? null : request.hint,
        'Skip',
        'Send',
      ),
    };
    final cells =
        request.kind == InputKind.vaultCode &&
        InputCard.wantsSixCells(request.hint);
    return NeedsYouCard(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      actions: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _text,
        builder: (context, value, _) => NeedsYouActions(
          skipLabel: skip,
          primaryLabel: primary,
          busy: _sending,
          onSkip: () => unawaited(_send('')),
          onPrimary: value.text.isEmpty
              ? null
              : () => unawaited(_send(_text.text)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (request.kind == InputKind.sudo && request.command.isNotEmpty) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: palette.line,
                  width: IrisStroke.hairline,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(IrisSpace.md),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r'$ ',
                        style: type.codeSmall.copyWith(
                          fontSize: 13,
                          color: palette.inkMuted,
                        ),
                      ),
                      Text(
                        request.command,
                        style: type.codeSmall.copyWith(
                          fontSize: 13,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: IrisSpace.md),
          ],
          if (request.kind == InputKind.secret &&
              request.envVar.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                request.envVar,
                style: type.codeSmall.copyWith(
                  fontSize: 13,
                  color: palette.ink,
                ),
              ),
            ),
            const SizedBox(height: IrisSpace.md),
          ],
          if (cells)
            _CodeCells(
              controller: _text,
              onFull: (code) => unawaited(_send(code)),
            )
          else
            IrisField(
              controller: _text,
              hint: switch (request.kind) {
                InputKind.sudo => 'Password',
                InputKind.secret => 'Value',
                InputKind.vaultUnlock => 'Master password',
                InputKind.vaultCode => 'Code',
              },
              mono: true,
              obscure: request.kind != InputKind.vaultCode && !_revealed,
              keyboardType: request.kind == InputKind.vaultCode
                  ? TextInputType.visiblePassword
                  : null,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              onSubmitted: (value) => unawaited(_send(value)),
              trailing: request.kind == InputKind.vaultCode
                  ? null
                  : IrisPressable(
                      onTap: () => setState(() => _revealed = !_revealed),
                      semanticLabel: _revealed
                          ? 'Hide password'
                          : 'Show password',
                      child: Icon(
                        _revealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: IrisSize.icon,
                        color: palette.inkMuted,
                      ),
                    ),
            ),
          if (request.kind == InputKind.secret) ...[
            const SizedBox(height: IrisSpace.sm),
            Text(
              'Stored on your server. Iris never shows it again.',
              style: type.codeSmall.copyWith(
                fontSize: 12,
                color: palette.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Six one-digit cells over one hidden numeric field. The sixth digit sends.
class _CodeCells extends StatefulWidget {
  const _CodeCells({required this.controller, required this.onFull});

  final TextEditingController controller;
  final ValueChanged<String> onFull;

  @override
  State<_CodeCells> createState() => _CodeCellsState();
}

class _CodeCellsState extends State<_CodeCells> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final needs = palette.colorFor(AgentState.waiting);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Stack(
        children: [
          // The real field: numeric, six long, invisible.
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 58,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (text) {
                  setState(() {});
                  if (text.length == 6) widget.onFull(text);
                },
              ),
            ),
          ),
          IgnorePointer(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) => Row(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: IrisSpace.xs),
                    Expanded(
                      child: Container(
                        key: const ValueKey('code-cell'),
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceSunken,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: i == value.text.length
                                ? needs
                                : palette.lineStrong,
                            width: i == value.text.length
                                ? 1.5
                                : IrisStroke.hairline,
                          ),
                        ),
                        child: Text(
                          i < value.text.length ? value.text[i] : '',
                          style: type.codeSmall.copyWith(
                            fontSize: 26,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
