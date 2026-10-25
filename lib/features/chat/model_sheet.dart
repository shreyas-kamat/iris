/// Picking the model a conversation runs on.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/segmented.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'chat_controller.dart';
import 'chat_state.dart';

/// Lets the person pick a model for [chat], asking first when Hermes wants
/// the switch confirmed — a guarded pick changes nothing until it is.
Future<void> showModelPicker(BuildContext context, ChatController chat) async {
  final pick = await showIrisSheet<(String, String)>(
    context: context,
    builder: (_) => ModelSheet(
      load: chat.modelOptions,
      current: chat.value.model,
      // Effort and fast need a session, which a new chat lacks until it sends.
      state: chat.isLive ? chat : null,
      onEffort: (effort) => unawaited(chat.setEffort(effort)),
      onFast: (fast) => unawaited(chat.setFast(fast: fast)),
    ),
  );
  if (pick == null) return;
  final (model, provider) = pick;
  final first = await chat.switchModel(model, provider, confirmed: false);
  if (first case Ok(value: final change) when change.confirmRequired) {
    if (!context.mounted) return;
    final confirmed = await showIrisSheet<bool>(
      context: context,
      builder: (sheetContext) => IrisSheet(
        title: 'Switch to $model?',
        subtitle: change.confirmMessage.isEmpty
            ? 'Hermes asks you to confirm this model.'
            : change.confirmMessage,
        actions: IrisSheetActions(
          primary: IrisButton(
            label: 'Switch',
            tone: IrisButtonTone.primary,
            expand: true,
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          secondary: IrisButton(
            label: 'Cancel',
            expand: true,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
    if (confirmed ?? false) {
      await chat.switchModel(model, provider, confirmed: true);
    }
  }
}

/// The models a conversation can switch to, grouped by provider, with a
/// filter: a provider can offer eighty of them.
class ModelSheet extends StatefulWidget {
  const ModelSheet({
    required this.load,
    this.current,
    this.state,
    this.onEffort,
    this.onFast,
    super.key,
  });

  final Future<Result<ModelOptions>> Function() load;

  /// The model in use, marked in the list.
  final String? current;

  /// The conversation's live state, for the effort and fast controls. Null
  /// shows the model list alone.
  final ValueListenable<ChatState>? state;
  final ValueChanged<ReasoningEffort>? onEffort;
  final ValueChanged<bool>? onFast;

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  late final Future<Result<ModelOptions>> _options = widget.load();
  final _filter = TextEditingController();

  /// The effort when it was first changed mid-reply, so the note can say
  /// "from → to". Cleared once the reply ends.
  ReasoningEffort? _before;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return FutureBuilder<Result<ModelOptions>>(
      future: _options,
      builder: (context, snapshot) => IrisSheet(
        title: 'Model',
        subtitle: widget.current == null ? null : 'Now: ${widget.current}',
        child: switch (snapshot.data) {
          null => const Padding(
            padding: EdgeInsets.all(IrisSpace.xl),
            child: Center(child: IrisOrb(state: AgentState.thinking)),
          ),
          Err(:final failure) => Padding(
            padding: const EdgeInsets.symmetric(vertical: IrisSpace.lg),
            child: Text(
              failure.message ?? 'Could not read the models.',
              style: theme.typography.body.copyWith(
                color: theme.palette.inkMuted,
              ),
            ),
          ),
          Ok(value: final options) => _list(context, options),
        },
      ),
    );
  }

  Widget _list(BuildContext context, ModelOptions options) {
    final theme = context.iris;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _filter,
      builder: (context, filter, _) {
        final query = filter.text.trim().toLowerCase();
        final groups = [
          for (final provider in options.usable)
            (
              provider,
              [
                for (final model in provider.models)
                  if (query.isEmpty || model.toLowerCase().contains(query))
                    model,
              ],
            ),
        ].where((group) => group.$2.isNotEmpty).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The settings for this chat come first: a gateway can list
            // hundreds of models, and anything below them goes unseen.
            _controls(context, options),
            IrisField(controller: _filter, hint: 'Filter models'),
            const SizedBox(height: IrisSpace.md),
            if (groups.isEmpty)
              Text(
                'No models match.',
                style: theme.typography.body.copyWith(
                  color: theme.palette.inkMuted,
                ),
              ),
            for (final (provider, models) in groups) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: IrisSpace.sm,
                  bottom: IrisSpace.xs,
                ),
                child: IrisLabel(provider.name),
              ),
              for (final model in models)
                IrisListRow(
                  title: model,
                  selected: model == widget.current,
                  onTap: () =>
                      Navigator.of(context).pop((model, provider.slug)),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, ModelOptions options) {
    final notifier = widget.state;
    if (notifier == null) return const SizedBox.shrink();
    return ValueListenableBuilder<ChatState>(
      valueListenable: notifier,
      builder: (context, state, _) {
        if (!state.running) _before = null;
        final model = widget.current ?? options.model;
        final caps = model == null
            ? null
            : options.capsFor(
                model,
                provider: state.provider ?? options.provider,
              );
        // When the gateway does not describe the model, what the session
        // itself reported decides: nothing is shown on a guess.
        final showEffort = caps?.reasoning ?? (state.effort != null);
        final showFast = caps?.fast ?? (state.fast != null);
        if (!showEffort && !showFast) return const SizedBox.shrink();
        final palette = context.palette;
        final type = context.type;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showEffort) ...[
              const IrisLabel('Reasoning effort', small: true),
              const SizedBox(height: IrisSpace.xs),
              _EffortControl(
                selected: state.effort,
                onChanged: (e) {
                  _before ??= state.effort;
                  widget.onEffort?.call(e);
                },
              ),
            ],
            if (showFast) ...[
              const SizedBox(height: IrisSpace.sm),
              Container(
                constraints: const BoxConstraints(minHeight: 60),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Fast mode',
                            style: type.body.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: palette.ink,
                            ),
                          ),
                          Text(
                            'Quicker replies, costs more',
                            style: type.body.copyWith(
                              fontSize: 13,
                              color: palette.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IrisSwitch(
                      value: state.fast ?? false,
                      semanticLabel: 'Fast mode',
                      onChanged: (on) => widget.onFast?.call(on),
                    ),
                  ],
                ),
              ),
            ],
            if (state.running && _before != null && _before != state.effort)
              _MidTurnNote(from: _before!, to: state.effort),
            const SizedBox(height: IrisSpace.md),
          ],
        );
      },
    );
  }
}

/// A change made mid-reply waits for the next turn, and says so.
class _MidTurnNote extends StatelessWidget {
  const _MidTurnNote({required this.from, required this.to});

  final ReasoningEffort from;
  final ReasoningEffort? to;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Container(
      margin: const EdgeInsets.only(top: IrisSpace.sm),
      padding: const EdgeInsets.all(IrisSpace.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: IrisStroke.hairline),
      ),
      child: Row(
        children: [
          const IrisOrb(state: AgentState.streaming, size: 22),
          const SizedBox(width: IrisSpace.md),
          Expanded(
            child: Text(
              'Applies after this reply.',
              style: type.body.copyWith(fontSize: 13.5, color: palette.ink),
            ),
          ),
          Text(
            '${from.wire} → ${to?.wire ?? from.wire}',
            style: type.codeSmall.copyWith(
              fontSize: 11.5,
              color: palette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// None, Low, Medium, High, Max in one track. At large text the segments
/// wrap to two rows rather than clip.
class _EffortControl extends StatelessWidget {
  const _EffortControl({required this.selected, required this.onChanged});

  final ReasoningEffort? selected;
  final ValueChanged<ReasoningEffort> onChanged;

  @override
  Widget build(BuildContext context) => IrisSegmented<ReasoningEffort>(
    values: ReasoningEffort.values,
    selected: selected,
    labelOf: (effort) => effort.label,
    onChanged: onChanged,
    height: 42,
  );
}
