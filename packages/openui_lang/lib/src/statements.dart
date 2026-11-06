/// Splits a prepared program into statements (language.md §1.4). Boundaries are decided on tokens so that
/// strings holding newlines, brackets and multi-line ternaries need no special cases.
library;

import 'ast.dart';
import 'expr_parser.dart';
import 'lexer.dart';

enum StatementKind { value, state, query, mutation }

class Statement {
  const Statement(this.name, this.kind, this.expr, this.start, this.end);

  final String name;
  final StatementKind kind;
  final Expr expr;

  /// Source span of the statement text.
  final int start;
  final int end;

  @override
  String toString() => '$name(${kind.name}) = $expr';
}

class SplitResult {
  const SplitResult(this.statements, {required this.incomplete});
  final List<Statement> statements;

  /// True when the input ended inside an unclosed string or bracket.
  final bool incomplete;
}

StatementKind _classify(String name, Expr e) {
  if (e is CallExpr && e.name == 'Query') return StatementKind.query;
  if (e is CallExpr && e.name == 'Mutation') return StatementKind.mutation;
  if (name.startsWith(r'$')) return StatementKind.state;
  return StatementKind.value;
}

/// Groups token indexes into statements. Returns the half-open token ranges; every range but the last ends at the
/// newline token that ended it, the last at `eof`.
List<(int, int)> statementRanges(List<Token> tokens) {
  final out = <(int, int)>[];
  var begin = 0;
  var depth = 0;
  var openTernary = 0; // unmatched `?`
  var needOperand = false; // after a ternary `:` until the first operand token
  for (var i = 0; i < tokens.length; i++) {
    final k = tokens[i].kind;
    if (k == TokenKind.eof) break;
    switch (k) {
      case TokenKind.lParen || TokenKind.lBracket || TokenKind.lBrace:
        depth++;
        needOperand = false;
      case TokenKind.rParen || TokenKind.rBracket || TokenKind.rBrace:
        if (depth > 0) depth--;
        needOperand = false;
      case TokenKind.question when depth == 0:
        openTernary++;
      case TokenKind.colon when depth == 0 && openTernary > 0:
        openTernary--;
        needOperand = true;
      case TokenKind.newline:
        if (depth > 0) break;
        if (openTernary > 0 || needOperand) break;
        var j = i + 1;
        while (j < tokens.length && tokens[j].kind == TokenKind.newline) {
          j++;
        }
        if (j < tokens.length && tokens[j].kind == TokenKind.question) break;
        out.add((begin, i));
        begin = i + 1;
      default:
        needOperand = false;
    }
  }
  out.add((begin, tokens.length - 1));
  return out;
}

SplitResult splitStatements(String prepared) {
  final lexed = lexAll(prepared);
  final tokens = lexed.tokens;
  final statements = <Statement>[];
  var depthAtEnd = 0;
  for (final t in tokens) {
    switch (t.kind) {
      case TokenKind.lParen || TokenKind.lBracket || TokenKind.lBrace:
        depthAtEnd++;
      case TokenKind.rParen || TokenKind.rBracket || TokenKind.rBrace:
        if (depthAtEnd > 0) depthAtEnd--;
      default:
    }
  }
  for (final (a, b) in statementRanges(tokens)) {
    final s = statementFromTokens(tokens.sublist(a, b));
    if (s != null) statements.add(s);
  }
  return SplitResult(statements, incomplete: lexed.unterminatedString || depthAtEnd > 0);
}

/// Parses one statement's tokens, or null when they do not form `name = expression`. [offset] shifts the span.
Statement? statementFromTokens(List<Token> slice, [int offset = 0]) {
  if (slice.where((t) => t.kind != TokenKind.newline).isEmpty) return null;
  final parsed = ExprParser(slice).parseStatement();
  if (parsed == null) return null;
  return Statement(
    parsed.name,
    _classify(parsed.name, parsed.value),
    parsed.value,
    slice.first.start + offset,
    slice.last.end + offset,
  );
}
