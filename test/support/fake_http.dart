/// A scripted HTTP server for Dio, so the auth and REST layers are tested
/// against exact responses without a network.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One canned response.
final class FakeReply {
  const FakeReply(
    this.status, {
    this.body = '',
    this.headers = const {},
    this.contentType = 'application/json',
  });

  factory FakeReply.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => FakeReply(status, body: jsonEncode(body), headers: headers);

  factory FakeReply.html(String body, {int status = 200}) =>
      FakeReply(status, body: body, contentType: 'text/html');

  /// What Cloudflare Access answers to a request without a valid token.
  /// Copied from a real probe of an Access-protected host.
  factory FakeReply.cloudflareLogin() => const FakeReply(
    302,
    body: '<html><body>302 Found</body></html>',
    contentType: 'text/html',
    headers: {
      'location':
          'https://team.cloudflareaccess.com/cdn-cgi/access/login/h.example?kid=x&redirect_url=%2F',
      'www-authenticate':
          'Cloudflare-Access resource_metadata="https://h.example/.well-known/cloudflare-access-protected-resource/"',
    },
  );

  final int status;
  final String body;
  final Map<String, String> headers;
  final String contentType;
}

/// Routes requests by `METHOD /path` to scripted replies and records them.
final class FakeHttp implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, FakeReply Function(RequestOptions request)> _routes = {};

  /// Answers `method path` (path without query) with [reply].
  void on(
    String method,
    String path,
    FakeReply Function(RequestOptions request) reply,
  ) => _routes['$method $path'] = reply;

  /// Requests made to [path], in order.
  List<RequestOptions> to(String path) =>
      requests.where((r) => r.uri.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = _routes['${options.method} ${options.uri.path}'];
    final reply =
        handler?.call(options) ??
        FakeReply.json({'detail': 'Not Found'}, status: 404);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [reply.contentType],
        for (final entry in reply.headers.entries) entry.key: [entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
