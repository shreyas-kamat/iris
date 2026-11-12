/// Lexer for OpenUI Lang 1.0 (language.md §1.3). It never throws: a character that matches no rule is skipped.
library;

enum TokenKind {
  component,
  reference,
  stateName,
  builtin,
  string,
  number,
  trueKw,
  falseKw,
  nullKw,
  assign,
  eq,
  neq,
  gt,
  lt,
  gte,
  lte,
  plus,
  minus,
  star,
  slash,
  percent,
  and,
  or,
  not,
  question,
  colon,
  dot,
  comma,
  lParen,
  rParen,
  lBracket,
  rBracket,
  lBrace,
  rBrace,
  newline,
  eof,
}

class Token {
  const Token(this.kind, this.start, this.end, [this.value]);

  final TokenKind kind;

  /// Offset of the first character in the source.
  final int start;

  /// Offset just past the last character.
  final int end;

  /// Name (without `@`; `$` kept for state names), decoded string, or `double` for numbers.
  final Object? value;

  @override
  String toString() => 'Token(${kind.name}${value == null ? '' : ' $value'} @$start)';
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isAlpha(int c) => (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a) || c == 0x5f;
bool _isAlnum(int c) => _isAlpha(c) || _isDigit(c);

/// Tokens after which a `-` is subtraction, not the sign of a number (language.md §1.3).
const _valueEnds = {
  TokenKind.number,
  TokenKind.string,
  TokenKind.reference,
  TokenKind.component,
  TokenKind.rParen,
  TokenKind.rBracket,
  TokenKind.trueKw,
  TokenKind.falseKw,
  TokenKind.nullKw,
  TokenKind.stateName,
  TokenKind.builtin,
};

/// Tokens plus whether the text ended inside a string.
typedef LexResult = ({List<Token> tokens, bool unterminatedString});

List<Token> lex(String src) => lexAll(src).tokens;

LexResult lexAll(String src) {
  var unterminated = false;
  final tokens = <Token>[];
  final n = src.length;
  var i = 0;

  int at(int k) => k < n ? src.codeUnitAt(k) : -1;
  void add(TokenKind kind, int start, [Object? value]) => tokens.add(Token(kind, start, i, value));
  void one(TokenKind kind) {
    final start = i++;
    add(kind, start);
  }

  void pair(TokenKind single, TokenKind double_, int second) {
    final start = i;
    if (at(i + 1) == second) {
      i += 2;
      add(double_, start);
    } else {
      i++;
      add(single, start);
    }
  }

  void skipLine() {
    while (i < n && src.codeUnitAt(i) != 0x0a) {
      i++;
    }
  }

  while (i < n) {
    final c = src.codeUnitAt(i);
    switch (c) {
      case 0x20 || 0x09 || 0x0d: // space, tab, and \r (consumed before \n; a lone \r is just skipped)
        i++;
      case 0x0a:
        one(TokenKind.newline);
      case 0x23: // #
        skipLine();
      case 0x2f: // /
        if (at(i + 1) == 0x2f) {
          skipLine();
        } else {
          one(TokenKind.slash);
        }
      case 0x3d:
        pair(TokenKind.assign, TokenKind.eq, 0x3d);
      case 0x21:
        pair(TokenKind.not, TokenKind.neq, 0x3d);
      case 0x3e:
        pair(TokenKind.gt, TokenKind.gte, 0x3d);
      case 0x3c:
        pair(TokenKind.lt, TokenKind.lte, 0x3d);
      case 0x26: // & or &&
        pair(TokenKind.and, TokenKind.and, 0x26);
      case 0x7c: // | or ||
        pair(TokenKind.or, TokenKind.or, 0x7c);
      case 0x2e:
        one(TokenKind.dot);
      case 0x3f:
        one(TokenKind.question);
      case 0x3a:
        one(TokenKind.colon);
      case 0x2c:
        one(TokenKind.comma);
      case 0x2b:
        one(TokenKind.plus);
      case 0x2a:
        one(TokenKind.star);
      case 0x25:
        one(TokenKind.percent);
      case 0x28:
        one(TokenKind.lParen);
      case 0x29:
        one(TokenKind.rParen);
      case 0x5b:
        one(TokenKind.lBracket);
      case 0x5d:
        one(TokenKind.rBracket);
      case 0x7b:
        one(TokenKind.lBrace);
      case 0x7d:
        one(TokenKind.rBrace);
      case 0x22:
        final start = i;
        final r = _doubleQuoted(src, i);
        unterminated = !r.closed;
        i = r.end;
        add(TokenKind.string, start, r.value);
      case 0x27:
        final start = i;
        final r = _singleQuoted(src, i);
        unterminated = !r.closed;
        i = r.end;
        add(TokenKind.string, start, r.value);
      case 0x24 || 0x40: // $name or @name
        if (_isAlpha(at(i + 1))) {
          final start = i;
          var j = i + 1;
          while (j < n && _isAlnum(src.codeUnitAt(j))) {
            j++;
          }
          i = j;
          if (c == 0x24) {
            add(TokenKind.stateName, start, src.substring(start, j));
          } else {
            add(TokenKind.builtin, start, src.substring(start + 1, j));
          }
        } else {
          i++;
        }
      default:
        if (_isDigit(c) || (c == 0x2d && _isDigit(at(i + 1)) && !_afterValue(tokens))) {
          final start = i;
          final r = _number(src, i);
          i = r.end;
          add(TokenKind.number, start, r.value);
        } else if (c == 0x2d) {
          one(TokenKind.minus);
        } else if (_isAlpha(c)) {
          final start = i;
          var j = i;
          while (j < n && _isAlnum(src.codeUnitAt(j))) {
            j++;
          }
          i = j;
          final word = src.substring(start, j);
          switch (word) {
            case 'true':
              add(TokenKind.trueKw, start);
            case 'false':
              add(TokenKind.falseKw, start);
            case 'null':
              add(TokenKind.nullKw, start);
            default:
              final upper = c >= 0x41 && c <= 0x5a;
              add(upper ? TokenKind.component : TokenKind.reference, start, word);
          }
        } else {
          i++; // unknown character, including a lone surrogate half
        }
    }
  }
  tokens.add(Token(TokenKind.eof, n, n));
  return (tokens: tokens, unterminatedString: unterminated);
}

bool _afterValue(List<Token> tokens) => tokens.isNotEmpty && _valueEnds.contains(tokens.last.kind);

({int end, double value}) _number(String src, int from) {
  final n = src.length;
  var i = from;
  bool digit(int k) => k < n && _isDigit(src.codeUnitAt(k));
  if (src.codeUnitAt(i) == 0x2d) i++;
  while (digit(i)) {
    i++;
  }
  if (i < n && src.codeUnitAt(i) == 0x2e && digit(i + 1)) {
    i++;
    while (digit(i)) {
      i++;
    }
  }
  var dangling = false;
  if (i < n && (src.codeUnitAt(i) == 0x65 || src.codeUnitAt(i) == 0x45)) {
    i++;
    if (i < n && (src.codeUnitAt(i) == 0x2b || src.codeUnitAt(i) == 0x2d)) i++;
    final expStart = i;
    while (digit(i)) {
      i++;
    }
    dangling = i == expStart;
  }
  return (end: i, value: dangling ? double.nan : double.parse(src.substring(from, i)));
}

({int end, String value, bool closed}) _doubleQuoted(String src, int from) {
  final n = src.length;
  final out = StringBuffer();
  var i = from + 1;
  while (i < n) {
    final c = src[i];
    if (c == '"') return (end: i + 1, value: out.toString(), closed: true);
    if (c != r'\') {
      out.write(c);
      i++;
      continue;
    }
    if (i + 1 >= n) {
      i++; // dangling backslash at the end of a streaming buffer
      break;
    }
    final e = src[i + 1];
    i += 2;
    switch (e) {
      case 'n':
        out.write('\n');
      case 't':
        out.write('\t');
      case 'r':
        out.write('\r');
      case 'b':
        out.write('\b');
      case 'f':
        out.write('\f');
      case 'u':
        final stop = n < i + 4 ? n : i + 4;
        final hex = src.substring(i, stop);
        final code = hex.length == 4 ? int.tryParse(hex, radix: 16) : null;
        if (code != null) {
          out.writeCharCode(code);
        } else {
          // Partly received or malformed escape: keep what arrived as text, as the reference does.
          out.write(r'\u');
          out.write(hex);
        }
        i = stop;
      default: // \" \\ \/ and any other escaped character: the character itself
        out.write(e);
    }
  }
  return (end: n, value: out.toString(), closed: false);
}

({int end, String value, bool closed}) _singleQuoted(String src, int from) {
  final n = src.length;
  final out = StringBuffer();
  var i = from + 1;
  while (i < n) {
    final c = src[i];
    if (c == "'") return (end: i + 1, value: out.toString(), closed: true);
    if (c == r'\') {
      i++;
      if (i < n) {
        final e = src[i];
        out.write(switch (e) {
          'n' => '\n',
          't' => '\t',
          _ => e,
        });
        i++;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return (end: n, value: out.toString(), closed: false);
}
