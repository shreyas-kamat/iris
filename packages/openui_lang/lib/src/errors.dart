/// Structured errors (language.md §8.2, §8.3). `message` and `hint` are text for the model and never compared.
library;

class ErrorCode {
  const ErrorCode._();
  static const unknownComponent = 'unknown-component';
  static const missingRequired = 'missing-required';
  static const nullRequired = 'null-required';
  static const typeMismatch = 'type-mismatch';
  static const excessArgs = 'excess-args';
  static const inlineReserved = 'inline-reserved';
  static const unknownFunction = 'unknown-function';
  static const queryCycle = 'query-cycle';
  static const noRoot = 'no-root';
  static const parseFailed = 'parse-failed';
  static const parseException = 'parse-exception';
  static const runtimeError = 'runtime-error';
  static const renderError = 'render-error';
}

class OpenUiError {
  const OpenUiError({
    required this.code,
    this.source = 'parser',
    this.statementId,
    this.component,
    this.path,
    this.message = '',
    this.hint,
    this.warning = false,
  });

  final String source;
  final String code;
  final String? statementId;
  final String? component;
  final String? path;
  final String message;
  final String? hint;

  /// Only the non-fatal `no-root` is a warning: the page renders through it.
  final bool warning;

  bool get isFatal => !warning && (code == ErrorCode.noRoot || code == ErrorCode.parseFailed || code == ErrorCode.parseException);

  Map<String, Object?> toJson() => {
        'source': source,
        'code': code,
        if (statementId != null) 'statementId': statementId,
        if (component != null) 'component': component,
        if (path != null) 'path': path,
        'message': message,
        if (hint != null) 'hint': hint,
        if (warning) 'severity': 'warning',
      };

  @override
  String toString() => 'OpenUiError($code${statementId == null ? '' : ' in $statementId'}${path == null ? '' : ' $path'})';
}
