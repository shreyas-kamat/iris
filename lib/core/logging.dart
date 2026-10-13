/// Logging that cannot leak the user's secrets.
///
/// Iris talks to a server on the user's own hardware, and the things flowing
/// through it — bearer tokens, session cookies, workspace paths that contain a
/// real name, prompt text — are exactly what must never end up in a log buffer,
/// a crash report, or a screenshot of the debug console. So logging goes through
/// [IrisLog], which redacts before it writes, and writes nothing at all in
/// release builds unless the user has explicitly opted into diagnostics.
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel {
  trace(500, 'TRC'),
  debug(700, 'DBG'),
  info(800, 'INF'),
  warn(900, 'WRN'),
  error(1000, 'ERR');

  const LogLevel(this.severity, this.label);

  /// Maps onto `dart:developer`'s level scale so IDE consoles colourise it.
  final int severity;
  final String label;
}

/// A namespaced logger. Create one per subsystem: `IrisLog('sse')`.
final class IrisLog {
  const IrisLog(this.channel);

  final String channel;

  /// Below this level nothing is emitted. Defaults to quiet in release.
  static LogLevel minimumLevel = kReleaseMode ? LogLevel.warn : LogLevel.debug;

  /// Set true only when the user turns on diagnostics in Settings. Release
  /// builds emit nothing otherwise, regardless of [minimumLevel].
  static bool diagnosticsEnabled = false;

  void trace(String message, {Object? data}) =>
      _write(LogLevel.trace, message, data: data);

  void debug(String message, {Object? data}) =>
      _write(LogLevel.debug, message, data: data);

  void info(String message, {Object? data}) =>
      _write(LogLevel.info, message, data: data);

  void warn(String message, {Object? data}) =>
      _write(LogLevel.warn, message, data: data);

  void error(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
    Object? data,
  }) => _write(
    LogLevel.error,
    message,
    data: data,
    cause: cause,
    stackTrace: stackTrace,
  );

  void _write(
    LogLevel level,
    String message, {
    Object? data,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    if (kReleaseMode && !diagnosticsEnabled) return;
    if (level.severity < minimumLevel.severity) return;

    final buffer = StringBuffer(redact(message));
    if (data != null) buffer.write('  ${redact(data.toString())}');

    developer.log(
      buffer.toString(),
      name: 'iris.$channel',
      level: level.severity,
      error: cause == null ? null : redact(cause.toString()),
      stackTrace: stackTrace,
    );
  }

  // --- Redaction -----------------------------------------------------------

  /// Patterns applied to every logged string, in order.
  ///
  /// These are deliberately over-eager: a redacted log that is slightly harder
  /// to read costs a minute of debugging, while a leaked token costs the user
  /// their server. When adding a pattern, prefer matching too much.
  static final List<(RegExp, String)> _redactions = [
    // Authorization / bearer tokens, in headers or JSON.
    (
      RegExp(r'(bearer\s+)[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      r'$1<token>',
    ),
    // Cookie headers, whole value.
    (
      RegExp(r'(set-cookie|cookie)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
      r'$1: <cookie>',
    ),
    // Cloudflare Access service-token secret, as a header.
    (
      RegExp(r'(cf-access-client-secret)\s*[:=]\s*\S+', caseSensitive: false),
      r'$1: <secret>',
    ),
    // Any JSON field whose name suggests a secret.
    (
      RegExp(
        r'"(password|passwd|secret|token|ticket|api_?key|access_?key|authorization|client_secret|refresh_token|session_key)"\s*:\s*"[^"]*"',
        caseSensitive: false,
      ),
      r'"$1":"<redacted>"',
    ),
    // The same, as a query parameter.
    (
      RegExp(
        r"([?&](?:password|token|ticket|api_?key|key|secret)=)[^&\s']*",
        caseSensitive: false,
      ),
      r'$1<redacted>',
    ),
    // Absolute home paths — POSIX and Windows — keep only the leaf.
    (RegExp(r'(/(?:home|Users)/)[^/\s]+'), r'$1<user>'),
    (
      RegExp(r'([A-Za-z]:\\Users\\)[^\\\s]+', caseSensitive: false),
      r'$1<user>',
    ),
    // Bare high-entropy strings that look like keys (sk-…, ghp_…, and friends).
    (
      RegExp(r'\b(sk|pk|ghp|gho|github_pat|xox[baprs])[-_][A-Za-z0-9_\-]{16,}'),
      '<key>',
    ),
  ];

  /// Removes credentials and personal paths from [input].
  ///
  /// Exposed so the network layer can redact a request body before it is
  /// attached to an `IrisFailure` that may later be surfaced or reported.
  static String redact(String input) {
    var output = input;
    for (final (pattern, replacement) in _redactions) {
      output = output.replaceAllMapped(
        pattern,
        (match) => _expand(replacement, match),
      );
    }
    return output;
  }

  /// Expands `$1`-style group references in a replacement template.
  static String _expand(String template, Match match) =>
      template.replaceAllMapped(RegExp(r'\$(\d)'), (reference) {
        final index = int.parse(reference.group(1)!);
        return index <= match.groupCount ? (match.group(index) ?? '') : '';
      });

  /// Redacts a URL for logging: keeps scheme, host and path, drops query values
  /// and any userinfo component.
  static String redactUri(Uri uri) {
    final safe = uri.replace(
      userInfo: '',
      queryParameters: uri.queryParameters.isEmpty
          ? null
          : {for (final key in uri.queryParameters.keys) key: '…'},
    );
    return redact(safe.toString());
  }
}
