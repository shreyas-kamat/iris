/// What one particular server can actually do.
///
/// hermes-webui ships fast and users self-host, so no two servers Iris talks to
/// are guaranteed to be the same build. Two answers to that are possible: pin a
/// tested upstream commit and refuse anything else, or ask the server what it
/// supports and adapt. Iris takes the second, because the alternative means a
/// user's own machine can become "unsupported" by an app update they did not
/// ask for.
///
/// So features are gated on a probe, not on a version string — version numbers
/// lie about backported and locally-patched builds, while a 404 does not.
library;

import 'dart:async';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'api_client.dart';

/// A capability that may or may not exist on a given server.
///
/// Each names the endpoint that proves it. Keep this list ordered by how
/// central the feature is: the probe runs them in parallel, but the UI reports
/// progress in this order.
enum ServerCapability {
  /// Per-session resumable stream with `Last-Event-ID` cursors. Newer servers
  /// only; falls back to the legacy `/api/chat/stream` when absent.
  resumableSessionStream('/api/sessions/events'),

  /// Session search by title.
  sessionSearch('/api/sessions/search'),

  /// Scheduled runs — the Tasks panel.
  crons('/api/crons'),

  /// Installed agent skills.
  skills('/api/skills'),

  /// The agent's memory documents.
  memory('/api/memory'),

  /// Registered workspace roots.
  workspaces('/api/workspaces'),

  /// Named agent configurations.
  profiles('/api/profiles'),

  /// The configured model list for the model picker.
  models('/api/models');

  const ServerCapability(this.probePath);

  /// A GET path whose response proves the capability exists.
  final String probePath;
}

/// The probe result for one server.
///
/// Absence is remembered as explicitly absent, not as unknown, so a screen can
/// say "this server does not have Tasks" rather than showing an empty list that
/// looks like the user has none.
final class ServerCapabilities {
  const ServerCapabilities({
    required this.available,
    required this.probedAt,
    this.serverVersion,
    this.requiresAuth = false,
  });

  /// Nothing probed yet. Everything is attempted optimistically, because a
  /// first-run user should not wait on a probe to send their first message.
  const ServerCapabilities.unknown()
    : available = const {},
      probedAt = null,
      serverVersion = null,
      requiresAuth = false;

  final Set<ServerCapability> available;
  final DateTime? probedAt;

  /// Whatever `/health` reported, for the About screen. Never used to gate a
  /// feature — that is what [available] is for.
  final String? serverVersion;

  /// Whether an unauthenticated probe was challenged.
  final bool requiresAuth;

  bool get hasProbed => probedAt != null;

  /// Whether [capability] is known to exist. Before a probe completes this
  /// answers `true`, so features are attempted rather than pre-emptively
  /// hidden; a request that then 404s is handled as a normal failure.
  bool has(ServerCapability capability) =>
      !hasProbed || available.contains(capability);

  /// Whether the probe positively confirmed [capability]. Used where the UI
  /// must not offer something that will fail — an entry in a navigation bar,
  /// as opposed to a request it can recover from.
  bool confirmed(ServerCapability capability) =>
      hasProbed && available.contains(capability);
}

/// Asks a server what it supports.
final class CapabilityProbe {
  const CapabilityProbe(this._client);

  static const _log = IrisLog('probe');

  final ApiClient _client;

  /// Probes `/health` and every capability endpoint concurrently.
  ///
  /// Never fails: an unreachable server yields an empty capability set with the
  /// [ServerCapabilities.requiresAuth] flag set if that is why. Callers decide
  /// what to do about a server that supports nothing.
  Future<ServerCapabilities> run({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final health = await _client.get('/health');
    final version = switch (health) {
      Ok(:final value) => value.any([
        'version',
        'server_version',
        'build',
      ]).stringOrNull,
      Err() => null,
    };
    final challenged = health.failureOrNull?.kind == FailureKind.unauthorized;

    final probes = await Future.wait([
      for (final capability in ServerCapability.values)
        _probe(capability, timeout),
    ]);

    final available = <ServerCapability>{
      for (final (capability, supported) in probes)
        if (supported) capability,
    };

    _log.info(
      'probed ${_client.server.label}: '
      '${available.length}/${ServerCapability.values.length} capabilities',
    );

    return ServerCapabilities(
      available: available,
      probedAt: DateTime.now(),
      serverVersion: version,
      requiresAuth: challenged,
    );
  }

  /// A capability counts as present unless the server said it is not there.
  ///
  /// Only [FailureKind.notFound] is treated as absence. A timeout or a 500
  /// means the probe could not tell, and assuming absence would silently
  /// remove features from a momentarily busy server.
  Future<(ServerCapability, bool)> _probe(
    ServerCapability capability,
    Duration timeout,
  ) async {
    final result = await _client
        .get(capability.probePath)
        .timeout(
          timeout,
          onTimeout: () => const Err(IrisFailure(FailureKind.timeout)),
        );
    final failure = result.failureOrNull;
    final present = failure == null || failure.kind != FailureKind.notFound;
    return (capability, present);
  }
}
