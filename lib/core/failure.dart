/// The single error type that crosses layer boundaries in Iris.
///
/// Repositories never let a `DioException`, `SocketException`, `FormatException`
/// or platform error escape — they translate it into an [IrisFailure]. That
/// keeps every feature layer dealing with one closed set of cases it can
/// exhaustively switch on to choose a message, an icon, and a recovery action.
library;

/// What went wrong, at the granularity the UI actually reacts to.
enum FailureKind {
  /// No route to the server: DNS, connection refused, airplane mode.
  offline,

  /// The server was reachable but did not answer in time.
  timeout,

  /// TLS handshake or certificate validation failed. Common with self-signed
  /// certs on home servers, so it gets its own recovery path.
  tls,

  /// Credentials are missing, wrong, or the session cookie expired (401/403).
  unauthorized,

  /// An access proxy in front of the server — Cloudflare Access — turned the
  /// request away before Hermes saw it. Fixed with a service token, not a
  /// password, so it is kept apart from [unauthorized].
  accessGate,

  /// The resource does not exist (404). Often a session deleted on another
  /// client, or an endpoint this server version does not implement.
  notFound,

  /// The request was rejected as invalid (400/409/422).
  rejected,

  /// The server errored (5xx).
  server,

  /// A response arrived but could not be understood as the expected shape.
  malformed,

  /// The operation was cancelled by the user or superseded.
  cancelled,

  /// Anything not otherwise classified.
  unknown,
}

/// A failure that can be shown to a person and acted on.
final class IrisFailure implements Exception {
  const IrisFailure(
    this.kind, {
    this.message,
    this.statusCode,
    this.endpoint,
    this.cause,
    this.stackTrace,
  });

  const IrisFailure.offline({String? message})
    : this(FailureKind.offline, message: message);

  const IrisFailure.malformed({String? message, String? endpoint})
    : this(FailureKind.malformed, message: message, endpoint: endpoint);

  const IrisFailure.cancelled() : this(FailureKind.cancelled);

  final FailureKind kind;

  /// Server-supplied or human-authored detail. Never contains credentials —
  /// see `logging.dart` for the redaction the network layer applies first.
  final String? message;

  final int? statusCode;

  /// The API path this failure came from, for diagnostics. Not shown to users.
  final String? endpoint;

  final Object? cause;
  final StackTrace? stackTrace;

  /// Whether retrying the identical request could plausibly succeed. Drives
  /// whether the UI offers a "Try again" affordance and whether the outbox
  /// keeps a queued send.
  bool get isRetryable => switch (kind) {
    FailureKind.offline ||
    FailureKind.timeout ||
    FailureKind.server ||
    FailureKind.unknown => true,
    FailureKind.tls ||
    FailureKind.unauthorized ||
    FailureKind.accessGate ||
    FailureKind.notFound ||
    FailureKind.rejected ||
    FailureKind.malformed ||
    FailureKind.cancelled => false,
  };

  /// Whether this failure means the server is unusable until the user acts,
  /// as opposed to one request having failed.
  bool get isConnectionLevel => switch (kind) {
    FailureKind.offline ||
    FailureKind.tls ||
    FailureKind.unauthorized ||
    FailureKind.accessGate => true,
    _ => false,
  };

  IrisFailure copyWith({String? message, String? endpoint}) => IrisFailure(
    kind,
    message: message ?? this.message,
    statusCode: statusCode,
    endpoint: endpoint ?? this.endpoint,
    cause: cause,
    stackTrace: stackTrace,
  );

  @override
  String toString() {
    final detail = message;
    final parts = <String>[
      kind.name,
      if (statusCode != null) 'HTTP $statusCode',
      ?endpoint,
      if (detail != null && detail.isNotEmpty) detail,
    ];
    return 'IrisFailure(${parts.join(' · ')})';
  }
}
