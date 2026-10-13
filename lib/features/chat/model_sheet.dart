/// Picking the model a conversation runs on.
library;

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'chat_controller.dart';

/// Lets the person pick a model for [chat], asking first when Hermes wants
/// the switch confirmed — a guarded pick changes nothing until it is.
Future<void> showModelPicker(BuildContext context, ChatController chat) async {
  final pick = await showIrisSheet<(String, String)>(
    context: context,
    builder: (_) =>
        ModelSheet(load: chat.modelOptions, current: chat.value.model),
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
  const ModelSheet({required this.load, this.current, super.key});

  final Future<Result<ModelOptions>> Function() load;

  /// The model in use, marked in the list.
  final String? current;

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  late final Future<Result<ModelOptions>> _options = widget.load();
  final _filter = TextEditingController();

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
                  onTap: () => Navigator.of(context).pop((model, provider.slug)),
                ),
            ],
          ],
        );
      },
    );
  }
}
