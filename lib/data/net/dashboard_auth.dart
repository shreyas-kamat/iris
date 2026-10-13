/// Signing in to a Hermes dashboard.
///
/// The dashboard uses a cookie session for REST and a single-use ticket for the
/// live WebSocket. So signing in is two steps: exchange a username and password
/// for a session cookie, then exchange the cookie for a ticket each time a
/// socket opens. The cookie stays in the connection's jar; nothing else in the
/// app handles it.
///
/// Discovery comes first so the connect screen asks only for what this
/// dashboard actually wants, and can name the reason when it cannot proceed.
library;

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'api_client.dart';

/// What a dashboard needs before it will open a live connection.
enum DashboardAccess {
  /// A username and password, exchanged for a session cookie.
  password,

  /// Nothing: auth is not configured. Common on a private network.
  open,

  /// Only browser (OAuth) sign-in is offered. Not supported yet.
  browserOnly,

  /// An access proxy (Cloudflare Access) stands in front and wants a service
  /// token before anything reaches Hermes.
  accessGate,

  /// Something answered, but it is not a Hermes dashboard.
  notHermes,

  /// Nothing answered: wrong address, server down, or no route from here.
  unreachable,
}

/// The outcome of looking at a dashboard's front door.
@immutable
final class DashboardProbe {
  const DashboardProbe({required this.access, this.version, this.failure});

  final DashboardAccess access;

  /// What `/api/status` reported, for confirmation on screen.
  final String? version;

  /// The failure behind [DashboardAccess.unreachable] or
  /// [DashboardAccess.accessGate], for the explanation shown.
  final IrisFailure? failure;
}

/// Performs dashboard authentication over one connection's client.
final class DashboardAuth {
  const DashboardAuth(this._client);

  static const _log = IrisLog('auth');

  final ApiClient _client;

  /// Asks the dashboard what it needs, without sending a login.
  ///
  /// Never fails: every outcome, including no answer at all, is a
  /// [DashboardAccess] the connect screen can explain.
  Future<DashboardProbe> probe() async {
    final providers = await _client.get('/api/auth/providers');
    switch (providers) {
      case Err(:final failure) when failure.kind == FailureKind.accessGate:
        return DashboardProbe(
          access: DashboardAccess.accessGate,
          failure: failure,
        );
      case Err(:final failure) when _isRedirect(failure):
        return DashboardProbe(
          access: DashboardAccess.browserOnly,
          failure: failure,
        );
      case Err(:final failure) when failure.kind == FailureKind.notFound:
        // Dashboards from before auth providers existed have no such route but
        // still answer /api/status. A 404 there too means this is not Hermes.
        final status = await _client.get('/api/status');
        return switch (status) {
          Ok(:final value) when value.isMap => DashboardProbe(
            access: DashboardAccess.open,
            version: value['version'].stringOrNull,
          ),
          _ => DashboardProbe(
            access: DashboardAccess.notHermes,
            failure: failure,
          ),
        };
      case Err(:final failure):
        return DashboardProbe(
          access: failure.kind == FailureKind.unauthorized
              ? DashboardAccess.browserOnly
              : DashboardAccess.unreachable,
          failure: failure,
        );
      case Ok(:final value):
        // A 2xx only means "Hermes" when it carries the provider list. A router
        // admin page or a captive portal answers 200 too.
        if (!value['providers'].isList) {
          return const DashboardProbe(access: DashboardAccess.notHermes);
        }
        final list = value['providers'].list;
        final version = await _version();
        if (list.any((p) => p['supports_password'].boolean())) {
          return DashboardProbe(
            access: DashboardAccess.password,
            version: version,
          );
        }
        return DashboardProbe(
          access: list.isEmpty
              ? DashboardAccess.open
              : DashboardAccess.browserOnly,
          version: version,
        );
    }
  }

  Future<String?> _version() async => switch (await _client.get(
    '/api/status',
  )) {
    Ok(:final value) => value['version'].stringOrNull,
    Err() => null,
  };

  /// Exchanges a username and password for a session cookie.
  ///
  /// On success the cookie is in the connection's jar. Nothing here retains
  /// the password; the caller decides whether to keep it in the keystore.
  Future<Result<void>> signIn({
    required String username,
    required String password,
  }) async {
    const path = '/auth/password-login';
    final result = await _client.post(
      path,
      body: {'provider': 'basic', 'username': username, 'password': password},
    );
    switch (result) {
      case Ok():
        _log.info('signed in');
        return const Ok(null);
      // Some deployments answer a form-style login with a redirect home. The
      // cookie is already in the jar; minting a ticket proves it.
      case Err(:final failure) when _isRedirect(failure):
        return const Ok(null);
      case Err(:final failure)
          when failure.kind == FailureKind.unauthorized ||
              failure.statusCode == 400:
        return Err(
          IrisFailure(
            FailureKind.unauthorized,
            message:
                failure.message ?? 'That username or password was not accepted.',
            statusCode: failure.statusCode,
            endpoint: path,
          ),
        );
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// Mints a single-use ticket for one WebSocket connect.
  ///
  /// An expired session reads as [FailureKind.unauthorized], whether the
  /// dashboard says 401 or redirects to its login page, so the caller knows to
  /// sign in again rather than retry.
  Future<Result<String>> mintTicket() async {
    const path = '/api/auth/ws-ticket';
    final result = await _client.post(path);
    switch (result) {
      case Ok(:final value):
        final ticket = value['ticket'].stringOrNull?.trim();
        if (ticket == null || ticket.isEmpty) {
          return const Err(
            IrisFailure.malformed(
              message: 'The dashboard did not issue a connection ticket.',
              endpoint: path,
            ),
          );
        }
        return Ok(ticket);
      case Err(:final failure) when _isRedirect(failure):
        return Err(
          IrisFailure(
            FailureKind.unauthorized,
            message: 'Sign in to the dashboard again.',
            statusCode: failure.statusCode,
            endpoint: path,
          ),
        );
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// A plain 3xx: not an access gate, which keeps its own kind.
  static bool _isRedirect(IrisFailure failure) {
    final status = failure.statusCode;
    return failure.kind != FailureKind.accessGate &&
        status != null &&
        status >= 300 &&
        status < 400;
  }
}
