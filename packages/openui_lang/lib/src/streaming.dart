/// The streaming parser (language.md §4). Completed statements are parsed once and cached; the pending tail is parsed
/// again on every update after implicit closing. A batch parse is a one-chunk stream that has ended.
library;

import 'errors.dart';
import 'lexer.dart';
import 'library_spec.dart';
import 'materialize.dart';
import 'parse_result.dart';
import 'program.dart';
import 'source.dart';
import 'statements.dart';

/// Closes an unterminated string (adding a `\` first when the text ends mid-escape), then unclosed brackets in reverse
/// order. A closer that does not match is skipped and leaves the stack alone. Comments are skipped as the lexer does;
/// when the text ends inside one, the closers go on a new line.
({String text, bool closed}) closeImplicitly(String text) {
  final stack = <String>[];
  String? quote;
  var inComment = false;
  var midEscape = false;
  final n = text.length;
  for (var i = 0; i < n; i++) {
    final c = text[i];
    if (inComment) {
      if (c == '\n') inComment = false;
      continue;
    }
    if (quote != null) {
      if (c == r'\') {
        if (i + 1 >= n) {
          midEscape = true;
        } else {
          i++;
        }
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    switch (c) {
      case '"' || "'":
        quote = c;
      case '#':
        inComment = true;
      case '/' when i + 1 < n && text[i + 1] == '/':
        inComment = true;
      case '(':
        stack.add(')');
      case '[':
        stack.add(']');
      case '{':
        stack.add('}');
      case ')' || ']' || '}':
        if (stack.isNotEmpty && stack.last == c) stack.removeLast();
    }
  }
  if (quote == null && stack.isEmpty) return (text: text, closed: false);
  final out = StringBuffer(text);
  if (quote != null) {
    if (midEscape) out.write(r'\');
    out.write(quote);
  }
  if (inComment && stack.isNotEmpty) out.write('\n');
  out.writeAll(stack.reversed);
  return (text: out.toString(), closed: true);
}

/// Accepts the whole text so far on every update. Not thread-safe; one per message.
class StreamingParser {
  StreamingParser(this.library);

  final LibrarySpec library;

  final _completed = <Statement>[];

  /// The prepared text the completed statements came from, up to and including the newline that ended the last.
  String _prefix = '';
  bool _ended = false;

  /// Names of the completed statements, in source order (for tests and diagnostics).
  List<String> get completedNames => [for (final s in _completed) s.name];

  /// Parses [fullText], the whole response so far, while the stream is open.
  ParseResult set(String fullText) {
    if (_ended) reset();
    return _parse(fullText, streaming: true);
  }

  /// Ends the stream (language.md §4, rule 7): the pending tail is closed and completed, and the result equals a batch
  /// parse. [fullText] defaults to the text of the last [set]. A later [set] starts a new stream.
  ParseResult end([String? fullText]) {
    final r = _parse(fullText ?? _lastText, streaming: false);
    _ended = true;
    return r;
  }

  void reset() {
    _completed.clear();
    _prefix = '';
    _ended = false;
  }

  String _lastText = '';

  ParseResult _parse(String fullText, {required bool streaming}) {
    _lastText = fullText;
    try {
      final prepared = prepareSource(fullText);
      if (!prepared.startsWith(_prefix)) {
        // Reconciliation (rule 4), for example a fence opener arrived: parse again from the start.
        _completed.clear();
        _prefix = '';
      }
      _advance(prepared);

      final pendingText = prepared.substring(_prefix.length);
      final closing = closeImplicitly(pendingText);
      final pending = splitStatements(closing.text).statements;
      final completedNames = {for (final s in _completed) s.name};
      final statements = [
        ..._completed,
        for (var i = 0; i < pending.length; i++)
          // Rule 3: only the last pending statement can have needed closing.
          if (!streaming || !closing.closed || i < pending.length - 1 || !completedNames.contains(pending[i].name))
            pending[i],
      ];
      return _result(statements, prepared, incomplete: closing.closed, streaming: streaming);
    } on Object catch (e) {
      return ParseResult(
        tree: null,
        errors: [OpenUiError(code: ErrorCode.parseException, message: '$e')],
        unresolved: const {},
        orphans: const {},
        incomplete: false,
        program: null,
      );
    }
  }

  /// Moves every statement of the new text that can no longer change into the cache (rule 1).
  void _advance(String prepared) {
    final tail = prepared.substring(_prefix.length);
    final tokens = lex(tail);
    final ranges = statementRanges(tokens);
    var consumed = 0; // characters of [tail] now completed
    for (var r = 0; r < ranges.length - 1; r++) {
      final (a, b) = ranges[r];
      // The range ended at the newline token b. It is final once the next line's first token has arrived, is not
      // `?` (statementRanges already checked that), and cannot still grow: a lone `/` may become a `//` comment.
      var j = b + 1;
      while (tokens[j].kind == TokenKind.newline) {
        j++;
      }
      final next = tokens[j];
      if (next.kind == TokenKind.eof || next.end >= tail.length) break;
      final s = statementFromTokens(tokens.sublist(a, b), _prefix.length);
      if (s != null) _completed.add(s);
      consumed = tokens[b].end;
    }
    _prefix = prepared.substring(0, _prefix.length + consumed);
  }

  ParseResult _result(List<Statement> statements, String prepared,
      {required bool incomplete, required bool streaming}) {
    if (statements.isEmpty) {
      final errors = prepared.trim().isEmpty || streaming
          ? <OpenUiError>[]
          : [const OpenUiError(code: ErrorCode.parseFailed, message: 'the response has text but yields no statements')];
      return ParseResult(
        tree: null,
        errors: errors,
        unresolved: const {},
        orphans: const {},
        incomplete: incomplete,
        program: null,
      );
    }
    final program = Program.build(statements, library, incomplete: incomplete);
    final m = materialize(program, library, streaming: streaming);
    return ParseResult(
      tree: m.root,
      errors: m.errors,
      unresolved: m.unresolved,
      orphans: program.orphans,
      incomplete: incomplete,
      program: program,
    );
  }
}
