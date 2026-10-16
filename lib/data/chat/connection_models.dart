/// The connection card's data: what the agent wants to connect, and the
/// answers Iris sends back.
///
/// Hermes's contract is wide (installs, catalog scans, plugin phases). Iris
/// reads only what the minimal card needs and keeps every enum value it does
/// not know as `other`, so a newer server never breaks the card: such a row
/// simply says to finish on Hermes Desktop.
library;

import 'package:flutter/foundation.dart';

import '../../core/json.dart';

enum TargetKind {
  connector,
  mcp,
  plugin,
  skill,
  other;

  static TargetKind fromWire(String? value) => switch (value?.trim()) {
    'connector' => connector,
    'mcp' => mcp,
    'plugin' => plugin,
    'skill' => skill,
    _ => other,
  };
}

enum TargetAction {
  authorize,
  connect,
  enable,
  install,
  reconnect,
  other;

  static TargetAction fromWire(String? value) => switch (value?.trim()) {
    'authorize' => authorize,
    'connect' => connect,
    'enable' => enable,
    'install' => install,
    'reconnect' => reconnect,
    _ => other,
  };
}

enum TargetState {
  pending,
  initiated,
  connected,
  skipped,
  failed,
  expired,
  notConnected,
  other;

  static TargetState fromWire(String? value) => switch (value?.trim()) {
    'pending' => pending,
    'initiated' => initiated,
    'connected' => connected,
    'skipped' => skipped,
    'failed' => failed,
    'expired' => expired,
    'not_connected' => notConnected,
    _ => other,
  };

  /// Nothing more to do for this target.
  bool get resolved => switch (this) {
    connected || skipped || failed || expired => true,
    _ => false,
  };
}

/// What a row offers the person, decided from its kind, action and fields.
enum TargetControl {
  /// Resolved: the chip says it all.
  none,

  /// Open the provider's sign-in page in the browser.
  signIn,

  /// Type the credentials the server needs, then Approve.
  credentials,

  /// One tap to approve.
  approve,

  /// Not something a phone can do: Skip only.
  desktopOnly,
}

/// One value an MCP server needs before it can connect.
@immutable
final class EnvField {
  const EnvField({
    required this.name,
    this.required = true,
    this.secret = true,
    this.prompt = '',
    this.fallback = '',
  });

  final String name;
  final bool required;
  final bool secret;

  /// Hermes's hint for the field.
  final String prompt;

  /// The server's default, shown as a placeholder only.
  final String fallback;
}

@immutable
final class ConnectionTarget {
  const ConnectionTarget({
    required this.name,
    required this.kind,
    required this.action,
    required this.state,
    this.detail = '',
    this.instructions = '',
    this.connectUrl,
    this.requiredEnv = const [],
  });

  /// A target, or null without a name (nothing could answer for it).
  static ConnectionTarget? parse(Json json) {
    final name = json['name'].stringOrNull?.trim();
    if (name == null || name.isEmpty) return null;
    final url = json['connect_url'].stringOrNull?.trim();
    return ConnectionTarget(
      name: name,
      kind: TargetKind.fromWire(json['kind'].stringOrNull),
      action: TargetAction.fromWire(json['action'].stringOrNull),
      state: TargetState.fromWire(json['state'].stringOrNull),
      detail: json['detail'].string().trim(),
      instructions: json['instructions'].string().trim(),
      connectUrl: url == null || url.isEmpty ? null : url,
      requiredEnv: [
        for (final field in json['required_env'].list)
          if (field['name'].stringOrNull case final String fieldName
              when fieldName.isNotEmpty)
            EnvField(
              name: fieldName,
              required: field['required'].boolOrNull ?? true,
              secret: field['secret'].boolOrNull ?? true,
              prompt: field['prompt'].string().trim(),
              fallback: field['default'].string(),
            ),
      ],
    );
  }

  final String name;
  final TargetKind kind;
  final TargetAction action;
  final TargetState state;

  /// Why a target failed, or what is happening ("Token rejected").
  final String detail;
  final String instructions;
  final String? connectUrl;
  final List<EnvField> requiredEnv;

  TargetControl get control {
    if (state.resolved) return TargetControl.none;
    final signsIn =
        action == TargetAction.authorize ||
        action == TargetAction.connect ||
        action == TargetAction.reconnect;
    if (connectUrl != null && signsIn) return TargetControl.signIn;
    if (kind == TargetKind.mcp && requiredEnv.isNotEmpty) {
      return TargetControl.credentials;
    }
    if (action == TargetAction.enable &&
        (kind == TargetKind.skill || kind == TargetKind.mcp)) {
      return TargetControl.approve;
    }
    if (kind == TargetKind.mcp &&
        (action == TargetAction.connect || action == TargetAction.install)) {
      return TargetControl.approve;
    }
    return TargetControl.desktopOnly;
  }

  ConnectionTarget withState(TargetState next, {String? detail}) =>
      ConnectionTarget(
        name: name,
        kind: kind,
        action: action,
        state: next,
        detail: detail ?? this.detail,
        instructions: instructions,
        connectUrl: connectUrl,
        requiredEnv: requiredEnv,
      );
}

@immutable
final class ConnectionRequest {
  const ConnectionRequest({
    required this.opId,
    required this.sessionId,
    required this.deadline,
    required this.targets,
    this.settled = false,
  });

  /// From a `connection.request` payload or a resume's `pending_connection`.
  /// Null without an op id.
  static ConnectionRequest? parse(
    Json json, {
    required String sessionId,
    DateTime? now,
  }) {
    final opId = json['op_id'].stringOrNull?.trim();
    if (opId == null || opId.isEmpty) return null;
    final at = json['deadline_at'].doubleOrNull;
    final timeout = json['timeout_seconds'].doubleOrNull ?? 300;
    final start = now ?? DateTime.now();
    return ConnectionRequest(
      opId: opId,
      sessionId: sessionId,
      deadline: at != null && at > 1e9
          ? DateTime.fromMillisecondsSinceEpoch((at * 1000).round(), isUtc: true)
          : start.add(Duration(milliseconds: (timeout * 1000).round())),
      targets: [
        for (final row in json['targets'].list) ?ConnectionTarget.parse(row),
      ],
    );
  }

  final String opId;
  final String sessionId;
  final DateTime deadline;
  final List<ConnectionTarget> targets;
  final bool settled;

  /// This request with [updates] merged in by name (a name not already here
  /// is added), and [settled] set.
  ConnectionRequest withTargets(
    List<ConnectionTarget> updates, {
    required bool settled,
  }) {
    final merged = [...targets];
    for (final update in updates) {
      final at = merged.indexWhere((t) => t.name == update.name);
      if (at < 0) {
        merged.add(update);
      } else {
        merged[at] = update;
      }
    }
    return ConnectionRequest(
      opId: opId,
      sessionId: sessionId,
      deadline: deadline,
      targets: merged,
      settled: settled || this.settled,
    );
  }
}

/// What the person decided for one target.
@immutable
final class TargetAnswer {
  const TargetAnswer.approved(this.name, {this.env = const {}})
    : approved = true;
  const TargetAnswer.skipped(this.name) : approved = false, env = const {};

  final String name;
  final bool approved;

  /// Credential values for an MCP install. Never stored: they go straight
  /// into `connection.respond`.
  final Map<String, String> env;

  Map<String, Object?> toWire() => {
    'name': name,
    'status': approved ? 'approved' : 'skipped',
    if (env.isNotEmpty) 'env': env,
  };
}
