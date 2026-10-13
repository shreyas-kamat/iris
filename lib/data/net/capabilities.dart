/// What one particular dashboard can actually do.
///
/// Hermes ships fast and users self-host, so no two dashboards Iris talks to
/// are guaranteed to be the same build, and plugins such as Kanban are
/// optional. Iris asks the dashboard what it supports and adapts, rather than
/// pinning a version and declaring a user's own machine unsupported.
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
  /// Named agent configurations, including bots.
  profiles('/api/profiles', 'Profiles'),

  /// Full-text search across sessions.
  sessionSearch('/api/sessions/search', 'Search'),

  /// Scheduled jobs and their runs.
  cronJobs('/api/cron/jobs', 'Scheduled jobs'),

  /// Installed skills.
  skills('/api/skills', 'Skills'),

  /// Toolsets, including speech providers.
  toolsets('/api/tools/toolsets', 'Tools'),

  /// The Kanban plugin's board.
  kanban('/api/plugins/kanban', 'Kanban'),

  /// Hermes Conduit's notifier plugin: push, live voice tokens, calls.
  conduitPlugin('/api/plugins/conduit_push/capabilities', 'Notifier plugin');

  const ServerCapability(this.probePath, this.label);

  /// A GET path whose response proves the capability exists.
  final String probePath;

  /// What the UI calls it.
  final String label;
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

  /// What /api/status reported, for display. Never used to gate a feature.
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

  /// Probes /api/status and every capability endpoint concurrently.
  ///
  /// Never fails: an unreachable server yields an empty capability set with the
  /// [ServerCapabilities.requiresAuth] flag set if that is why. Callers decide
  /// what to do about a server that supports nothing.
  Future<ServerCapabilities> run({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final status = await _client.get('/api/status');
    final version = switch (status) {
      Ok(:final value) => value['version'].stringOrNull,
      Err() => null,
    };
    final challenged = switch (status.failureOrNull?.kind) {
      FailureKind.unauthorized || FailureKind.accessGate => true,
      _ => false,
    };

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
