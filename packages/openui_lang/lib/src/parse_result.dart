/// The outcome of parsing a program, in the canonical form the conformance fixtures compare.
class ParseResult {
  const ParseResult({
    required this.root,
    required this.errors,
    required this.unresolved,
    required this.orphans,
    required this.incomplete,
    this.state,
  });

  /// Rendered tree summary: `{type, props}`; null when there is no root.
  final Map<String, Object?>? root;

  /// `{code, statementId?}` for each error.
  final List<Map<String, Object?>> errors;
  final List<String> unresolved;
  final List<String> orphans;
  final bool incomplete;
  final Map<String, Object?>? state;
}
