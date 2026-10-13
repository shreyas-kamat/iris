/// Signing in to a hermes-webui server.
///
/// Auth is optional upstream and layered: a server may be wide open, may want a
/// password, or may sit behind OIDC. Iris handles the first two and detects the
/// third well enough to explain it rather than failing opaquely.
///
/// The session is a signed HttpOnly cookie, so once login succeeds the cookie
/// jar carries it and nothing else in the app has to think about credentials
/// again. That is the reason to prefer the cookie over an Authorization header:
/// the secret stops flowing through application code entirely.
library;

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'api_client.dart';
import 'server_config.dart';

/// What a server wants before it will answer.
enum AuthRequirement {
  /// No credentials needed. The common case for a server on a private network.
  open,

  /// A password, exchanged for a session cookie.
  password,

  /// An external identity provider. Iris cannot complete this in-app and says
  /// so, rather than looping the user through a password prompt that will
  /// never succeed.
  externalIdentityProvider,

  /// The server could not be reached, so the requirement is unknown.
  unknown,
}

/// The outcome of probing a server's front door.
@immutable
final class AuthProbe {
  const AuthProbe({
    required this.requirement,
    this.serverVersion,
    this.detail,
  });

  final AuthRequirement requirement;
  final String? serverVersion;

  /// Human-readable context, shown when the requirement is one Iris cannot
  /// satisfy.
  final String? detail;
}

/// Performs authentication against one server.
final class SessionAuth {
  const SessionAuth(this._client);

  static const _log = IrisLog('auth');

  final ApiClient _client;

  /// Asks the server what it needs, without sending credentials.
  ///
  /// Uses `/health` because it is the one endpoint every version has and the
  /// cheapest thing to hit. A 200 means open; a 401 or 403 means guarded. The
  /// body is inspected for an OIDC hint so the failure can be explained.
  Future<AuthProbe> probe() async {
    final result = await _client.get('/health');
    return switch (result) {
      Ok(:final value) => AuthProbe(
        requirement: AuthRequirement.open,
        serverVersion: value
            .any(['version', 'server_version', 'build'])
            .stringOrNull,
      ),
      Err(:final failure) when failure.kind == FailureKind.unauthorized =>
        AuthProbe(
          requirement: _looksLikeOidc(failure)
              ? AuthRequirement.externalIdentityProvider
              : AuthRequirement.password,
          detail: failure.message,
        ),
      Err(:final failure) => AuthProbe(
        requirement: AuthRequirement.unknown,
        detail: failure.message,
      ),
    };
  }

  /// A server configured for OIDC answers an unauthenticated probe with a
  /// redirect or a body naming the provider. Matching on the message is coarse,
  /// but the alternative is telling the user their password is wrong when the
  /// server never wanted one.
  static bool _looksLikeOidc(IrisFailure failure) {
    final text = '${failure.message}'.toLowerCase();
    return text.contains('oidc') ||
        text.contains('oauth') ||
        text.contains('sso') ||
        text.contains('identity provider');
  }

  /// Exchanges [password] for a session cookie.
  ///
  /// On success the cookie is in the jar and subsequent requests are
  /// authenticated. The password is not retained here; the caller decides
  /// whether to persist it to the keystore.
  Future<Result<void>> signIn(String password) async {
    final result = await _client.post(
      '/api/auth/login',
      body: {'password': password},
    );

    return switch (result) {
      Ok(:final value) when value['ok'].boolean(true) => const Ok(null),
      Ok(:final value) => Err(
        IrisFailure(
          FailureKind.unauthorized,
          // The server's own wording, when it gave one. It knows things Iris
          // does not, such as a rate limit being in force.
          message: value['error'].stringOrNull ?? 'That password was rejected.',
          endpoint: '/api/auth/login',
        ),
      ),
      Err(:final failure) when failure.kind == FailureKind.notFound => Err(
        const IrisFailure(
          FailureKind.rejected,
          message:
              'This server does not accept password sign-in. It may be open, '
              'or it may use an identity provider.',
        ),
      ),
      Err(:final failure) => Err(
        failure.kind == FailureKind.rejected
            ? failure.copyWith(message: 'That password was rejected.')
            : failure,
      ),
    };
  }

  /// Ends the session and clears the cookie.
  Future<void> signOut() async {
    await _client.post('/api/auth/logout');
    _log.info('signed out');
  }
}

/// Builds a [Dio] for one server, with the cookie jar attached.
///
/// Each server gets its own jar. Sharing one across servers would send a
/// session cookie issued by a home server to a work server, which at best fails
/// and at worst leaks a token to a host that should never see it.
final class ServerConnection {
  ServerConnection._(this.config, this.client, this._jar);

  factory ServerConnection.create(ServerConfig config) {
    final jar = CookieJar();
    final dio = Dio()..interceptors.add(CookieManager(jar));

    if (config.allowSelfSignedCertificate) {
      _allowSelfSigned(dio, config);
    }

    return ServerConnection._(config, ApiClient(server: config, dio: dio), jar);
  }

  /// Accepts a certificate that does not chain to a trusted root.
  ///
  /// Scoped to this connection's host only. A global override would disable
  /// validation for every request the app makes, including any future one to a
  /// host the user never opted in for.
  static void _allowSelfSigned(Dio dio, ServerConfig config) {
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) =>
            host == config.uri.host;
        return client;
      };
    }
  }

  final ServerConfig config;
  final ApiClient client;
  final CookieJar _jar;

  SessionAuth get auth => SessionAuth(client);

  /// Whether a session cookie is currently held.
  Future<bool> get hasSession async {
    final cookies = await _jar.loadForRequest(config.uri);
    return cookies.isNotEmpty;
  }

  Future<void> clearSession() => _jar.deleteAll();

  void close() => client.close();
}
