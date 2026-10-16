/// The one-line records prompts leave behind, built from what was asked and
/// how it ended, never from what was typed.
library;

import '../../data/chat/chat_models.dart';

String clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

PromptRecord recordForInput(
  InputRequest request,
  PromptOutcome outcome,
  DateTime at, {
  required String id,
}) {
  final time = clock(at);
  final name = request.displayName.isEmpty
      ? 'Password manager'
      : request.displayName;
  final site = request.site;
  if (outcome == PromptOutcome.expired) {
    final subject = switch (request.kind) {
      InputKind.vaultUnlock => '$name request',
      InputKind.vaultCode =>
        site.isEmpty ? 'Code request' : '$site code request',
      InputKind.sudo => 'sudo request',
      InputKind.secret =>
        request.envVar.isEmpty ? 'Secret request' : '${request.envVar} request',
    };
    return PromptRecord(
      id: id,
      title: '$subject withdrawn',
      detail: 'expired $time · Hermes stopped waiting',
      outcome: outcome,
    );
  }
  final answered = outcome == PromptOutcome.answered;
  final (title, detail) = switch (request.kind) {
    InputKind.sudo => (
      answered ? 'Ran with sudo' : 'Denied sudo',
      '${request.command.isEmpty ? 'sudo' : request.command} · $time',
    ),
    InputKind.secret => (
      answered
          ? 'Saved ${request.envVar.isEmpty ? 'the secret' : request.envVar}'
          : 'Skipped ${request.envVar.isEmpty ? 'the secret' : request.envVar}',
      answered ? 'value hidden · $time' : 'skipped · $time',
    ),
    InputKind.vaultUnlock => (
      answered ? 'Unlocked $name' : 'Skipped the $name unlock',
      '${answered ? 'answered' : 'skipped'} · $time',
    ),
    InputKind.vaultCode => (
      answered
          ? 'Sent the code${site.isEmpty ? '' : ' for $site'}'
          : 'Skipped the code${site.isEmpty ? '' : ' for $site'}',
      answered ? 'value hidden · $time' : 'skipped · $time',
    ),
  };
  return PromptRecord(id: id, title: title, detail: detail, outcome: outcome);
}

PromptRecord recordForLogin(
  LoginRequest request,
  PromptOutcome outcome,
  DateTime at, {
  required String id,
}) {
  final time = clock(at);
  final site = request.siteName;
  return switch (outcome) {
    PromptOutcome.answered => PromptRecord(
      id: id,
      title: 'Saved $site login',
      detail: 'value hidden · $time',
      outcome: outcome,
    ),
    PromptOutcome.skipped => PromptRecord(
      id: id,
      title: 'Skipped saving the $site login',
      detail: 'skipped · $time',
      outcome: outcome,
    ),
    PromptOutcome.expired => PromptRecord(
      id: id,
      title: '$site login request withdrawn',
      detail: 'expired $time · Hermes stopped waiting',
      outcome: outcome,
    ),
  };
}
