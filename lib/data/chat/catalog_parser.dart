/// Reads the dashboard's catalogues: profiles, conversation pages, models and
/// slash commands.
///
/// Shapes verified against Hermes 0.18.2 on 2026-10-13; see
/// `docs/superpowers/specs/2026-10-13-phase3-design.md`.
library;

import '../../core/json.dart';
import 'chat_models.dart';
import 'history_parser.dart';
import 'usage_parser.dart';

abstract final class CatalogParser {
  /// `GET /api/profiles`.
  static List<AgentProfile> profiles(Json body) {
    final rows = body.isList ? body.list : body['profiles'].list;
    return [
      for (final row in rows) ?_profile(row),
    ];
  }

  static AgentProfile? _profile(Json row) {
    final name = HistoryParser.firstText(row, const ['name', 'id']);
    if (name == null) return null;
    return AgentProfile(
      name: name,
      isDefault: row['is_default'].boolean(),
      model: HistoryParser.firstText(row, const ['model']),
      provider: HistoryParser.firstText(row, const ['provider']),
      running: row['gateway_running'].boolean(),
    );
  }

  /// `GET /api/profiles/sessions`.
  static ConversationPage conversationPage(Json body) {
    final items = HistoryParser.conversations(body);
    return ConversationPage(
      items: items,
      total: body['total'].intOrNull ?? items.length,
    );
  }

  /// `model.options`.
  static ModelOptions modelOptions(Json result) => ModelOptions(
    model: HistoryParser.firstText(result, const ['model']),
    provider: HistoryParser.firstText(result, const ['provider']),
    providers: [
      for (final row in result['providers'].list) ?_provider(row),
    ],
  );

  static ModelProvider? _provider(Json row) {
    final slug = HistoryParser.firstText(row, const ['slug', 'id', 'name']);
    if (slug == null) return null;
    return ModelProvider(
      slug: slug,
      name: HistoryParser.firstText(row, const ['name', 'display_name']) ?? slug,
      models: [
        for (final model in row['models'].list) ?_modelId(model),
      ],
      isCurrent: row['is_current'].boolean(),
      authenticated: row['authenticated'].boolOrNull ?? true,
      usage: UsageParser.providerUsage(row['usage']),
    );
  }

  /// A model entry: a bare id today, an object on some gateways.
  static String? _modelId(Json model) {
    final id =
        model.stringOrNull?.trim() ??
        HistoryParser.firstText(model, const ['id', 'name', 'model']);
    return id == null || id.isEmpty ? null : id;
  }

  /// `config.set` for the model. Hermes may echo the raw request, flags and
  /// all; only the model part is kept.
  static ModelSwitch modelSwitch(Json result, {required String requested}) {
    final raw = result['value'].string();
    final cut = raw.indexOf(' --');
    final value = (cut < 0 ? raw : raw.substring(0, cut)).trim();
    return ModelSwitch(
      model: value.isEmpty ? requested : value,
      confirmRequired: result['confirm_required'].boolean(),
      confirmMessage:
          HistoryParser.firstText(result, const ['confirm_message', 'warning']) ??
          '',
      deferred: result['deferred'].boolean(),
    );
  }

  /// `commands.catalog`: every command with its description, in the
  /// gateway's order, without duplicates.
  static List<SlashCommand> commands(Json result) {
    final seen = <String>{};
    final commands = <SlashCommand>[];
    for (final pair in result['pairs'].list) {
      final raw = pair.at(0).stringOrNull?.trim() ?? '';
      if (raw.isEmpty) continue;
      final name = raw.startsWith('/') ? raw : '/$raw';
      if (!seen.add(name)) continue;
      commands.add(
        SlashCommand(name: name, description: pair.at(1).string().trim()),
      );
    }
    return commands;
  }

  /// `slash.exec` or `command.dispatch`.
  static SlashOutcome slashOutcome(Json result) {
    if (result.stringOrNull case final plain?) {
      return SlashOutcome(kind: SlashKind.exec, text: plain);
    }
    final output = result.any(const ['output', 'message', 'notice']).string();
    return switch (result['type'].string().trim()) {
      'send' || 'skill' => SlashOutcome(
        kind: SlashKind.send,
        text: result.any(const ['message', 'output']).string(),
      ),
      'prefill' => SlashOutcome(
        kind: SlashKind.prefill,
        text: result.any(const ['message', 'output']).string(),
        notice: result['notice'].string(),
      ),
      'alias' => SlashOutcome(
        kind: SlashKind.alias,
        text: output,
        target:
            HistoryParser.firstText(result, const ['target', 'command', 'name']) ??
            '',
      ),
      _ => SlashOutcome(kind: SlashKind.exec, text: output),
    };
  }
}
