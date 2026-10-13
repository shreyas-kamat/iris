/// A success-or-failure value used for every repository call in Iris.
///
/// Repositories return `Result<T>` rather than throwing, so a caller cannot
/// forget to handle the error path: there is no way to read the value without
/// first acknowledging that a failure is possible. Pattern matching over the
/// sealed hierarchy makes the compiler enforce it.
///
/// ```dart
/// final result = await sessions.load(id);
/// switch (result) {
///   case Ok(:final value):     showSession(value);
///   case Err(:final failure):  showError(failure);
/// }
/// ```
library;

import 'failure.dart';

/// The outcome of an operation that can fail with an [IrisFailure].
sealed class Result<T> {
  const Result();

  /// Runs [body], converting an [IrisFailure] it throws into an [Err].
  ///
  /// Only [IrisFailure] is caught: an unexpected `TypeError` or `StateError` is
  /// a bug in Iris, not a condition to render, and must keep propagating to the
  /// error zone so it is reported rather than silently swallowed.
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on IrisFailure catch (failure) {
      return Err(failure);
    }
  }

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  /// The value, or `null` if this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The failure, or `null` if this is an [Ok].
  IrisFailure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  /// The value, or [fallback] if this is an [Err].
  T or(T fallback) => valueOrNull ?? fallback;

  /// Transforms a success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok(transform(value)),
    Err<T>(:final failure) => Err(failure),
  };

  /// Chains another fallible operation onto a success.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => transform(value),
    Err<T>(:final failure) => Err(failure),
  };

  /// Collapses both cases into a single value.
  R fold<R>({
    required R Function(T value) ok,
    required R Function(IrisFailure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };
}

/// A successful outcome carrying [value].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T> && other.value == value);

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// A failed outcome carrying [failure].
final class Err<T> extends Result<T> {
  const Err(this.failure);

  final IrisFailure failure;

  /// Re-types a failure for a different success type, so an error can be
  /// forwarded through a layer that changes `T`.
  Err<R> cast<R>() => Err<R>(failure);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T> && other.failure == failure);

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
