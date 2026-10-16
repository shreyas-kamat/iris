/// What the agent wants to connect, one row per target (frame A8).
///
/// Each row shows a state chip and only the controls it needs right now.
/// The countdown to Hermes's deadline sits in the header in mono. The card
/// does only what a phone can: sign in through the browser, type the
/// credentials an MCP server needs, enable a skill. Everything else says to
/// finish on Hermes Desktop and can be skipped.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/connection_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

class ConnectionCard extends StatefulWidget {
  const ConnectionCard({
    required this.request,
    required this.onAnswer,
    required this.onContinue,
    required this.onOpenSignIn,
    required this.onExpired,
    this.now = DateTime.now,
    super.key,
  });

  final ConnectionRequest request;
  final ValueChanged<TargetAnswer> onAnswer;

  /// Settles the card; whatever is still open counts as skipped.
  final VoidCallback onContinue;
  final ValueChanged<ConnectionTarget> onOpenSignIn;

  /// Called once, when the deadline passes.
  final VoidCallback onExpired;

  /// The wall clock, so tests can move time.
  final DateTime Function() now;

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  Timer? _tick;
  bool _expiredReported = false;

  /// Rows whose sign-in page was opened: they wait for Hermes to report
  /// the result in a `connection.update`, without polling.
  final Set<String> _waiting = {};

  /// Credential fields, by target then variable. Disposed with the card;
  /// their values go only into an answer.
  final Map<String, Map<String, TextEditingController>> _env = {};

  Duration get _left => widget.request.deadline.difference(widget.now());

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted) return;
    if (_left <= Duration.zero && !_expiredReported) {
      _expiredReported = true;
      _tick?.cancel();
      widget.onExpired();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final fields in _env.values) {
      for (final controller in fields.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  String get _countdown {
    final left = _left.isNegative ? Duration.zero : _left;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(left.inMinutes)}:${two(left.inSeconds % 60)}';
  }

  TextEditingController _field(String target, String name) =>
      (_env[target] ??= {})[name] ??= TextEditingController();

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final palette = context.palette;
    final type = context.type;
    final needs = palette.colorFor(AgentState.waiting);
    final settled = request.targets.every((t) => t.state.resolved);
    final borderColor = settled ? palette.colorFor(AgentState.done) : needs;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor.withValues(alpha: settled ? .4 : .45),
          width: IrisStroke.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: IrisLabel(
                    'Connect · ${request.targets.length} items',
                    color: needs,
                    small: true,
                  ),
                ),
                Text(
                  _countdown,
                  style: type.codeSmall.copyWith(fontSize: 11, color: needs),
                ),
              ],
            ),
            const SizedBox(height: IrisSpace.xs),
            for (final (index, target) in request.targets.indexed) ...[
              if (index > 0) const IrisDivider(),
              _TargetRow(
                key: ValueKey('target-${target.name}'),
                target: target,
                waiting: _waiting.contains(target.name),
                field: (name) => _field(target.name, name),
                onSignIn: () {
                  setState(() => _waiting.add(target.name));
                  widget.onOpenSignIn(target);
                },
                onAnswer: widget.onAnswer,
              ),
            ],
            const SizedBox(height: IrisSpace.sm),
            Semantics(
              button: true,
              label: 'Continue',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onContinue,
                child: Container(
                  key: ValueKey(settled ? 'continue-filled' : 'continue-ghost'),
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: settled ? palette.accent : null,
                    borderRadius: BorderRadius.circular(16),
                    border: settled
                        ? null
                        : Border.all(
                            color: palette.lineStrong,
                            width: IrisStroke.hairline,
                          ),
                  ),
                  child: Text(
                    'Continue',
                    style: type.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: settled ? palette.accentInk : palette.inkMuted,
                    ),
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

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.target,
    required this.waiting,
    required this.field,
    required this.onSignIn,
    required this.onAnswer,
    super.key,
  });

  final ConnectionTarget target;
  final bool waiting;
  final TextEditingController Function(String name) field;
  final VoidCallback onSignIn;
  final ValueChanged<TargetAnswer> onAnswer;

  static String _kind(TargetKind kind) => switch (kind) {
    TargetKind.connector => 'connector',
    TargetKind.mcp => 'MCP server',
    TargetKind.plugin => 'plugin',
    TargetKind.skill => 'skill',
    TargetKind.other => 'item',
  };

  static String _action(TargetAction action) => switch (action) {
    TargetAction.authorize => 'authorise',
    TargetAction.connect => 'connect',
    TargetAction.enable => 'enable',
    TargetAction.install => 'install',
    TargetAction.reconnect => 'reconnect',
    TargetAction.other => 'set up',
  };

  (String, AgentState) _chip() => switch (target.state) {
    TargetState.pending => ('Pending', AgentState.waiting),
    TargetState.initiated => ('Opened', AgentState.loading),
    TargetState.connected => ('Connected', AgentState.done),
    TargetState.failed => ('Failed', AgentState.failed),
    TargetState.skipped => ('Skipped', AgentState.rest),
    TargetState.expired => ('Expired', AgentState.offline),
    TargetState.notConnected => ('Not connected', AgentState.rest),
    TargetState.other => ('Pending', AgentState.waiting),
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final (label, state) = _chip();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surfaceSunken,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  switch (target.kind) {
                    TargetKind.connector => Icons.link,
                    TargetKind.mcp => Icons.dns_outlined,
                    TargetKind.plugin => Icons.extension_outlined,
                    TargetKind.skill => Icons.auto_awesome_outlined,
                    TargetKind.other => Icons.help_outline,
                  },
                  size: 18,
                  color: palette.ink,
                ),
              ),
              const SizedBox(width: IrisSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.name,
                      style: type.body.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    Text(
                      '${_kind(target.kind)} · ${_action(target.action)}',
                      style: type.codeSmall.copyWith(
                        fontSize: 11,
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: IrisSpace.xs),
              IrisChip.state(label, state, palette),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: _controls(context),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    Widget skip() => IrisPressable(
      onTap: () => onAnswer(TargetAnswer.skipped(target.name)),
      semanticLabel: 'Skip ${target.name}',
      child: Text('Skip', style: type.label.copyWith(color: palette.accent)),
    );
    switch (target.control) {
      case TargetControl.none:
        return target.detail.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: IrisSpace.xs),
                child: Text(
                  target.detail,
                  style: type.codeSmall.copyWith(
                    fontSize: 11.5,
                    color: target.state == TargetState.failed
                        ? palette.colorFor(AgentState.failed)
                        : palette.inkMuted,
                  ),
                ),
              );
      case TargetControl.signIn:
        // Opened here, or Hermes says the sign-in is under way (a card that
        // came back with a resume).
        if (waiting || target.state == TargetState.initiated) {
          return Padding(
            padding: const EdgeInsets.only(top: IrisSpace.sm),
            child: Container(
              padding: const EdgeInsets.all(IrisSpace.md),
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const IrisOrb(state: AgentState.loading, size: 22),
                  const SizedBox(width: IrisSpace.md),
                  Expanded(
                    child: Text(
                      'Waiting for sign-in…',
                      style: type.body.copyWith(
                        fontSize: 13.5,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  IrisPressable(
                    onTap: onSignIn,
                    semanticLabel: 'Reopen sign-in',
                    child: Text(
                      'Reopen',
                      style: type.label.copyWith(color: palette.accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return _ActionRow(
          primary: _RowButton(
            label: 'Open sign-in',
            filled: false,
            onPressed: onSignIn,
          ),
          skip: skip(),
        );
      case TargetControl.credentials:
        return _Credentials(target: target, field: field, onAnswer: onAnswer);
      case TargetControl.approve:
        return _ActionRow(
          primary: _RowButton(
            label: target.action == TargetAction.enable ? 'Enable' : 'Approve',
            onPressed: () => onAnswer(TargetAnswer.approved(target.name)),
          ),
          skip: skip(),
        );
      case TargetControl.desktopOnly:
        return Padding(
          padding: const EdgeInsets.only(top: IrisSpace.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: IrisSpace.md,
              vertical: IrisSpace.sm,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceSunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.desktop_windows_outlined,
                  size: 16,
                  color: palette.inkMuted,
                ),
                const SizedBox(width: IrisSpace.sm),
                Expanded(
                  child: Text(
                    'Finish this on Hermes Desktop',
                    style: type.body.copyWith(
                      fontSize: 13,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: IrisSpace.sm),
                skip(),
              ],
            ),
          ),
        );
    }
  }
}

/// A row's main action with Skip at the far end. At large text the two
/// wrap onto separate lines rather than overflow.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.primary, required this.skip});

  final Widget primary;
  final Widget skip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: IrisSpace.sm),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: IrisSpace.md,
      runSpacing: IrisSpace.xs,
      children: [primary, skip],
    ),
  );
}

/// A row's button. Its label wraps rather than overflows at large text,
/// which a shared button sized to its label cannot do inside a narrow row.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Opacity(
      opacity: onPressed == null ? .45 : 1,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: IrisSize.control),
            padding: const EdgeInsets.symmetric(
              horizontal: IrisSpace.lg,
              vertical: IrisSpace.sm,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? palette.accent : null,
              borderRadius: const BorderRadius.all(IrisRadius.sm),
              border: filled
                  ? null
                  : Border.all(
                      color: palette.lineStrong,
                      width: IrisStroke.hairline,
                    ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: type.heading.copyWith(
                fontSize: 15,
                color: filled ? palette.accentInk : palette.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The values an MCP server needs, then Approve. Values live in controllers
/// that are disposed with the card and go straight into the answer.
class _Credentials extends StatelessWidget {
  const _Credentials({
    required this.target,
    required this.field,
    required this.onAnswer,
  });

  final ConnectionTarget target;
  final TextEditingController Function(String name) field;
  final ValueChanged<TargetAnswer> onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final controllers = [for (final f in target.requiredEnv) field(f.name)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, env) in target.requiredEnv.indexed) ...[
          const SizedBox(height: IrisSpace.sm),
          IrisLabel(env.name, small: true),
          const SizedBox(height: IrisSpace.xs),
          IrisField(
            controller: controllers[i],
            hint: env.fallback.isEmpty ? 'Value' : env.fallback,
            mono: true,
            obscure: env.secret,
            autocorrect: false,
            enableSuggestions: false,
          ),
          if (env.prompt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              env.prompt,
              style: type.body.copyWith(fontSize: 12, color: palette.inkMuted),
            ),
          ],
        ],
        if (target.detail.isNotEmpty) ...[
          const SizedBox(height: IrisSpace.xs),
          Text(
            target.detail,
            style: type.codeSmall.copyWith(
              fontSize: 11.5,
              color: palette.colorFor(AgentState.failed),
            ),
          ),
        ],
        ListenableBuilder(
          listenable: Listenable.merge(controllers),
          builder: (context, _) {
            final ready = [
              for (final (i, env) in target.requiredEnv.indexed)
                if (env.required) controllers[i].text.isNotEmpty,
            ].every((ok) => ok);
            return _ActionRow(
              primary: _RowButton(
                label: 'Approve',
                onPressed: ready
                    ? () => onAnswer(
                        TargetAnswer.approved(
                          target.name,
                          env: {
                            for (final (i, env) in target.requiredEnv.indexed)
                              if (controllers[i].text.isNotEmpty)
                                env.name: controllers[i].text,
                          },
                        ),
                      )
                    : null,
              ),
              skip: IrisPressable(
                onTap: () => onAnswer(TargetAnswer.skipped(target.name)),
                semanticLabel: 'Skip ${target.name}',
                child: Text(
                  'Skip',
                  style: type.label.copyWith(color: palette.accent),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
