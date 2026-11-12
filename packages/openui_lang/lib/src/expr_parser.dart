/// Recursive-descent expression parser (language.md §1.5, §1.6). It never throws; malformed input degrades.
library;

import 'ast.dart';
import 'lexer.dart';

/// Parses one statement's tokens. Newline tokens are ignored: the statement splitter already decided the extent.
class ExprParser {
  ExprParser(List<Token> tokens)
      : _t = tokens.where((t) => t.kind != TokenKind.newline).toList() {
    if (_t.isEmpty || _t.last.kind != TokenKind.eof) {
      final end = _t.isEmpty ? 0 : _t.last.end;
      _t.add(Token(TokenKind.eof, end, end));
    }
  }

  final List<Token> _t;
  int _i = 0;

  Token get _cur => _t[_i];
  TokenKind get _k => _t[_i].kind;
  TokenKind _peekKind(int n) => _t[_i + n < _t.length ? _i + n : _t.length - 1].kind;
  bool get atEnd => _k == TokenKind.eof;

  Token _next() {
    final t = _t[_i];
    if (t.kind != TokenKind.eof) _i++;
    return t;
  }

  bool _accept(TokenKind k) {
    if (_k != k) return false;
    _next();
    return true;
  }

  /// Parses `name = expression`. Returns null if the tokens do not have that shape.
  ({String name, Expr value})? parseStatement() {
    final k = _k;
    if ((k != TokenKind.reference && k != TokenKind.component && k != TokenKind.stateName) ||
        _peekKind(1) != TokenKind.assign) {
      return null;
    }
    final name = _next().value! as String;
    _next();
    return (name: name, value: parseExpression());
  }

  Expr parseExpression() => _ternary();

  Expr _ternary() {
    final cond = _or();
    if (_k != TokenKind.question) return cond;
    _next();
    final a = _ternary();
    _accept(TokenKind.colon);
    final b = _ternary();
    return TernaryExpr(cond, a, b);
  }

  Expr _or() {
    var l = _and();
    while (_k == TokenKind.or) {
      _next();
      l = BinaryExpr('||', l, _and());
    }
    return l;
  }

  Expr _and() {
    var l = _equality();
    while (_k == TokenKind.and) {
      _next();
      l = BinaryExpr('&&', l, _equality());
    }
    return l;
  }

  Expr _equality() {
    var l = _comparison();
    while (_k == TokenKind.eq || _k == TokenKind.neq) {
      final op = _next().kind == TokenKind.eq ? '==' : '!=';
      l = BinaryExpr(op, l, _comparison());
    }
    return l;
  }

  static const _cmp = {TokenKind.gt: '>', TokenKind.lt: '<', TokenKind.gte: '>=', TokenKind.lte: '<='};

  Expr _comparison() {
    var l = _additive();
    while (_cmp.containsKey(_k)) {
      final op = _cmp[_next().kind]!;
      l = BinaryExpr(op, l, _additive());
    }
    return l;
  }

  Expr _additive() {
    var l = _multiplicative();
    while (_k == TokenKind.plus || _k == TokenKind.minus) {
      final op = _next().kind == TokenKind.plus ? '+' : '-';
      l = BinaryExpr(op, l, _multiplicative());
    }
    return l;
  }

  static const _mul = {TokenKind.star: '*', TokenKind.slash: '/', TokenKind.percent: '%'};

  Expr _multiplicative() {
    var l = _unary();
    while (_mul.containsKey(_k)) {
      final op = _mul[_next().kind]!;
      l = BinaryExpr(op, l, _unary());
    }
    return l;
  }

  Expr _unary() {
    if (_k == TokenKind.not) {
      _next();
      return UnaryExpr('!', _unary());
    }
    if (_k == TokenKind.minus) {
      _next();
      return UnaryExpr('-', _unary());
    }
    return _postfix();
  }

  Expr _postfix() {
    var e = _primary();
    while (true) {
      if (_k == TokenKind.dot) {
        _next();
        e = MemberExpr(e, _keyText(allowStateDrop: false));
      } else if (_k == TokenKind.lBracket) {
        _next();
        final idx = parseExpression();
        _accept(TokenKind.rBracket);
        e = IndexExpr(e, idx);
      } else {
        return e;
      }
    }
  }

  /// A key or field: a name, string, number, component name or `$` name. Anything else reads as `?`.
  String _keyText({bool allowStateDrop = true}) {
    final t = _cur;
    switch (t.kind) {
      case TokenKind.reference || TokenKind.component || TokenKind.string:
        _next();
        return t.value! as String;
      case TokenKind.number:
        _next();
        return formatNumber(t.value! as double);
      case TokenKind.stateName:
        _next();
        final v = t.value! as String;
        return allowStateDrop ? v.substring(1) : v;
      case TokenKind.eof || TokenKind.rParen || TokenKind.rBracket || TokenKind.rBrace:
        return '?';
      default:
        _next();
        return '?';
    }
  }

  Expr _primary() {
    final t = _cur;
    switch (t.kind) {
      case TokenKind.string:
        _next();
        return StrLit(t.value! as String);
      case TokenKind.number:
        _next();
        return NumLit(t.value! as double);
      case TokenKind.trueKw:
        _next();
        return const BoolLit(true);
      case TokenKind.falseKw:
        _next();
        return const BoolLit(false);
      case TokenKind.nullKw:
        _next();
        return const NullLit();
      case TokenKind.lBracket:
        _next();
        return ArrayExpr(_arguments(TokenKind.rBracket));
      case TokenKind.lBrace:
        _next();
        return _object();
      case TokenKind.lParen:
        _next();
        final e = parseExpression();
        _accept(TokenKind.rParen);
        return e;
      case TokenKind.component:
        _next();
        if (_k == TokenKind.lParen) {
          _next();
          return CallExpr(t.value! as String, _arguments(TokenKind.rParen));
        }
        return RefExpr(t.value! as String);
      case TokenKind.builtin:
        _next();
        final name = t.value! as String;
        if (_k == TokenKind.lParen) {
          _next();
          final args = _arguments(TokenKind.rParen);
          return name == 'Action' ? CallExpr('Action', args) : FnExpr(name, args);
        }
        return FnExpr(name, const []);
      case TokenKind.stateName:
        _next();
        if (_k == TokenKind.assign) {
          _next();
          return AssignExpr(t.value! as String, parseExpression());
        }
        return RefExpr(t.value! as String);
      case TokenKind.reference:
        _next();
        if (_k == TokenKind.lParen) {
          // `Count(x)` without `@` is the reference `Count`; the arguments are lost (language.md §1.5).
          _skipBalanced();
        }
        return RefExpr(t.value! as String);
      default:
        // A stray operator or closer where an operand belongs. Consume operators, leave closers for the caller.
        if (t.kind != TokenKind.eof &&
            t.kind != TokenKind.rParen &&
            t.kind != TokenKind.rBracket &&
            t.kind != TokenKind.rBrace) {
          _next();
        }
        return const NullLit();
    }
  }

  void _skipBalanced() {
    var depth = 0;
    while (!atEnd) {
      final k = _next().kind;
      if (k == TokenKind.lParen) depth++;
      if (k == TokenKind.rParen && --depth <= 0) return;
    }
  }

  bool _isCloser(TokenKind k) => k == TokenKind.rParen || k == TokenKind.rBracket || k == TokenKind.rBrace;

  List<Expr> _arguments(TokenKind close) {
    final out = <Expr>[];
    while (true) {
      while (_accept(TokenKind.comma)) {}
      if (atEnd) break;
      if (_k == close) {
        _next();
        break;
      }
      if (_isCloser(_k)) {
        // A closer that does not match is skipped.
        _next();
        continue;
      }
      final before = _i;
      out.add(parseExpression());
      if (_i == before) _next();
    }
    return out;
  }

  Expr _object() {
    final entries = <(String, Expr)>[];
    while (true) {
      while (_accept(TokenKind.comma)) {}
      if (atEnd) break;
      if (_k == TokenKind.rBrace) {
        _next();
        break;
      }
      if (_k == TokenKind.rParen || _k == TokenKind.rBracket) {
        _next();
        continue;
      }
      final key = _keyText();
      _accept(TokenKind.colon);
      entries.add((key, parseExpression()));
    }
    return ObjectExpr(entries);
  }
}
