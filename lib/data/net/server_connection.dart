/// One server's HTTP identity: its cookie jar, its secrets, and the client
/// built from them.
///
/// Each server gets its own jar. Sharing one across servers would send a
/// session cookie issued by a home server to a work server, which at best fails
/// and at worst leaks a token to a host that should never see it.
library;

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'api_client.dart';
import 'credentials.dart';
import 'server_config.dart';

final class ServerConnection {
  ServerConnection._(this.config, this.secrets, this.client, this._jar);

  /// Builds the connection. [adapter] replaces the network, for tests.
  factory ServerConnection.create(
    ServerConfig config, {
    ServerSecrets secrets = ServerSecrets.none,
    HttpClientAdapter? adapter,
  }) {
    final jar = CookieJar();
    final dio = Dio()..interceptors.add(CookieManager(jar));
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    } else if (config.allowSelfSignedCertificate) {
      final io = dio.httpClientAdapter;
      if (io is IOHttpClientAdapter) {
        io.createHttpClient = () => _trusting(config);
      }
    }
    return ServerConnection._(
      config,
      secrets,
      ApiClient(server: config, dio: dio, secrets: secrets),
      jar,
    );
  }

  final ServerConfig config;
  final ServerSecrets secrets;
  final ApiClient client;
  final CookieJar _jar;

  /// The Access headers for a request to [uri]: none over cleartext.
  Map<String, String> accessHeadersFor(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'wss')
      ? secrets.accessHeaders
      : const {};

  /// An `HttpClient` for the WebSocket upgrade, with the same certificate
  /// policy as REST, so a self-signed server that works for sign-in does not
  /// then fail on the live connection.
  HttpClient socketHttpClient() =>
      config.allowSelfSignedCertificate ? _trusting(config) : HttpClient();

  /// Accepts a certificate that does not chain to a trusted root, for this
  /// connection's host only. A global override would disable validation for
  /// every request the app makes.
  static HttpClient _trusting(ServerConfig config) => HttpClient()
    ..badCertificateCallback = (cert, host, port) => host == config.uri.host;

  Future<void> clearSession() => _jar.deleteAll();

  void close() => client.close();
}
