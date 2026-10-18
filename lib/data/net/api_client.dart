/// The HTTP boundary between Iris and a Hermes dashboard.
///
/// Everything network-facing funnels through here so three guarantees hold in
/// exactly one place: nothing throws past this layer (every transport error
/// becomes an [IrisFailure]), nothing is logged unredacted, and every response
/// is handed onward as tolerant [Json] rather than a decoded type.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'credentials.dart';
import 'server_config.dart';

/// A configured client for one server.
final class ApiClient {
  ApiClient({
    required ServerConfig server,
    Dio? dio,
    ServerSecrets secrets = ServerSecrets.none,
  }) : _server = server,
       _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: server.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 45),
      // Iris inspects the status itself so it can build a precise failure;
      // letting Dio throw would lose the response body that explains why.
      validateStatus: (_) => true,
      // A redirect is an answer, not a detour: Cloudflare Access answers an
      // unauthenticated request with a 302 to its login page, and following it
      // would turn "you need a token" into a confusing 200 of HTML.
      followRedirects: false,
      headers: const {'Accept': 'application/json'},
    );
    if (secrets.hasAccessToken) {
      final headers = secrets.accessHeaders;
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // Over cleartext the long-lived Access secret would be readable by
            // anyone on the path, so it is withheld; a LAN dashboard does not
            // need it anyway.
            if (options.uri.scheme == 'https') options.headers.addAll(headers);
            handler.next(options);
          },
        ),
      );
    }
  }

  static const _log = IrisLog('net');

  final ServerConfig _server;
  final Dio _dio;

  ServerConfig get server => _server;

  /// The underlying Dio, for the streaming client which needs raw byte access.
  Dio get dio => _dio;

  /// GETs [path] and returns its body as tolerant JSON.
  Future<Result<Json>> get(
    String path, {
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) => _send(
    path,
    () => _dio.get<String>(
      path,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.plain),
    ),
  );

  /// POSTs a JSON body to [path] and returns its response as tolerant JSON.
  Future<Result<Json>> post(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) => _send(
    path,
    () => _dio.post<String>(
      path,
      data: _clean(body),
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
        receiveTimeout: receiveTimeout,
      ),
    ),
  );

  /// PATCHes a JSON body to [path] and returns its response as tolerant JSON.
  Future<Result<Json>> patch(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) => _send(
    path,
    () => _dio.patch<String>(
      path,
      data: _clean(body),
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
      ),
    ),
  );

  /// PUTs a JSON body to [path] and returns its response as tolerant JSON.
  Future<Result<Json>> put(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) => _send(
    path,
    () => _dio.put<String>(
      path,
      data: _clean(body),
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
      ),
    ),
  );

  /// DELETEs [path] and returns its response as tolerant JSON.
  Future<Result<Json>> delete(
    String path, {
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) => _send(
    path,
    () => _dio.delete<String>(
      path,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.plain),
    ),
  );

  /// GETs [path] as raw bytes, for file previews and image attachments.
  Future<Result<List<int>>> bytes(
    String path, {
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.bytes),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return Err(_failureForStatus(status, path, null, response.headers));
      }
      return Ok(response.data ?? const []);
    } on Object catch (error, stackTrace) {
      return Err(_translate(error, stackTrace, path));
    }
  }

  /// Uploads a file to the session's workspace as multipart form data.
  Future<Result<Json>> upload(
    String path, {
    required String sessionId,
    required String filename,
    required List<int> content,
    CancelToken? cancelToken,
  }) => _send(
    path,
    () => _dio.post<String>(
      path,
      data: FormData.fromMap({
        'session_id': sessionId,
        'file': MultipartFile.fromBytes(content, filename: filename),
      }),
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.plain),
    ),
  );

  Future<Result<Json>> _send(
    String path,
    Future<Response<String>> Function() request,
  ) async {
    try {
      final response = await request();
      final status = response.statusCode ?? 0;
      final body = Json.decode(response.data ?? '');

      if (status < 200 || status >= 300) {
        return Err(_failureForStatus(status, path, body, response.headers));
      }

      // A 200 carrying an `error` field is how several endpoints report a
      // rejected operation, so success is not status alone.
      final embeddedError = body['error'].stringOrNull;
      if (embeddedError != null && embeddedError.isNotEmpty) {
        return Err(
          IrisFailure(
            FailureKind.rejected,
            message: IrisLog.redact(embeddedError),
            endpoint: path,
          ),
        );
      }
      return Ok(body);
    } on Object catch (error, stackTrace) {
      return Err(_translate(error, stackTrace, path));
    }
  }

  IrisFailure _failureForStatus(
    int status,
    String path,
    Json? body,
    Headers headers,
  ) {
    if (isAccessGate(
      status,
      location: headers['location']?.first,
      challenge: headers['www-authenticate']?.first,
    )) {
      _log.warn('$path → stopped by an access proxy');
      return IrisFailure(
        FailureKind.accessGate,
        message: 'An access proxy in front of the server stopped the request.',
        statusCode: status,
        endpoint: path,
      );
    }
    // FastAPI reports errors as `detail`; older endpoints use `error` or
    // `message`.
    final message =
        body?['error'].stringOrNull ??
        body?['message'].stringOrNull ??
        body?['detail'].stringOrNull;
    final kind = switch (status) {
      401 || 403 => FailureKind.unauthorized,
      404 => FailureKind.notFound,
      >= 300 && < 400 => FailureKind.rejected,
      >= 400 && < 500 => FailureKind.rejected,
      >= 500 => FailureKind.server,
      _ => FailureKind.unknown,
    };
    _log.warn('$path → HTTP $status');
    return IrisFailure(
      kind,
      message: message == null ? null : IrisLog.redact(message),
      statusCode: status,
      endpoint: path,
    );
  }

  /// Whether a response is an access proxy turning the request away before it
  /// reached Hermes.
  ///
  /// Cloudflare Access marks its challenge with a `Www-Authenticate:
  /// Cloudflare-Access` header and redirects to `*.cloudflareaccess.com` or, on
  /// a custom team domain, to a `/cdn-cgi/access/` path. Any one is enough.
  static bool isAccessGate(int status, {String? location, String? challenge}) {
    if (challenge != null &&
        challenge.toLowerCase().startsWith('cloudflare-access')) {
      return true;
    }
    if (status < 300 || status >= 400 || location == null) return false;
    final target = Uri.tryParse(location);
    if (target == null) return false;
    return target.host.endsWith('.cloudflareaccess.com') ||
        target.path.contains('/cdn-cgi/access/');
  }

  /// Turns any transport error into a failure the UI can act on.
  ///
  /// The distinctions that matter to a person: is the server unreachable, is it
  /// slow, is the certificate untrusted, or did I get the password wrong. A
  /// generic "network error" would collapse four different fixes into one.
  IrisFailure _translate(Object error, StackTrace stackTrace, String path) {
    if (error is DioException) {
      final kind = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.transformTimeout => FailureKind.timeout,
        DioExceptionType.badCertificate => FailureKind.tls,
        DioExceptionType.cancel => FailureKind.cancelled,
        DioExceptionType.connectionError => FailureKind.offline,
        DioExceptionType.badResponse => FailureKind.server,
        DioExceptionType.unknown => _classifyUnknown(error),
      };
      _log.warn('$path → ${kind.name}', data: error.message);
      return IrisFailure(
        kind,
        message: error.message == null ? null : IrisLog.redact(error.message!),
        statusCode: error.response?.statusCode,
        endpoint: path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    _log.error('$path failed', cause: error, stackTrace: stackTrace);
    return IrisFailure(
      FailureKind.unknown,
      endpoint: path,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// `DioExceptionType.unknown` covers both socket failures and TLS handshake
  /// failures, which need different remedies, so the underlying error is
  /// inspected by name rather than by type — `HandshakeException` lives in
  /// `dart:io` and is not importable on every target.
  static FailureKind _classifyUnknown(DioException error) {
    final description = '${error.error?.runtimeType} ${error.message}';
    if (description.contains('Handshake') ||
        description.contains('CERTIFICATE') ||
        description.contains('certificate')) {
      return FailureKind.tls;
    }
    if (description.contains('SocketException') ||
        description.contains('Failed host lookup')) {
      return FailureKind.offline;
    }
    return FailureKind.unknown;
  }

  /// Drops null-valued entries so an absent optional is omitted from the wire
  /// rather than sent as an explicit null, which some endpoints treat as a
  /// request to clear the field.
  static Map<String, Object?>? _clean(Map<String, Object?>? source) {
    if (source == null) return null;
    final cleaned = <String, Object?>{
      for (final entry in source.entries)
        if (entry.value != null) entry.key: entry.value,
    };
    return cleaned.isEmpty ? null : cleaned;
  }

  void close() => _dio.close(force: true);
}
