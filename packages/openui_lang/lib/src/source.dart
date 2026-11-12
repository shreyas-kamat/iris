/// Source preparation (language.md §1.2): marker lines, fence extraction, trimming.
/// Comment stripping is done by the lexer, which already ignores markers inside strings.
library;

final _stmtStart = RegExp(r'^\s*[A-Za-z_$][A-Za-z0-9_]*\s*=(?!=)');

bool _startsStatement(String line) => _stmtStart.hasMatch(line);

bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('#');
}

/// Toggles the "inside a double-quoted string" state across [line].
bool _scanString(String line, bool inString) {
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inString && c == r'\') {
      i++;
    } else if (c == '"') {
      inString = !inString;
    }
  }
  return inString;
}

String prepareSource(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith(']]>openui:'))
      .toList();

  final blocks = <List<String>>[];
  final outside = <String>[];
  List<String>? block;
  var skipping = false;
  var inString = false;
  var sawFence = false;

  for (final line in lines) {
    final t = line.trimLeft();
    final isFenceLine = t.startsWith('```') && !inString && !_closesOnSameLine(t);
    if (block == null) {
      if (isFenceLine) {
        sawFence = true;
        final rest = t.substring(3).trim();
        final tag = rest.split(RegExp(r'\s+')).first;
        skipping = tag == 'openui-js';
        block = <String>[];
        final code = rest.length > tag.length ? rest.substring(tag.length).trim() : '';
        if (code.isNotEmpty && !skipping) {
          block.add(code);
          inString = _scanString(code, false);
        }
        blocks.add(block);
        if (skipping) blocks.removeLast();
      } else {
        outside.add(line);
        // Outside blocks a string opens only on a statement line.
        if (inString || _startsStatement(line)) inString = _scanString(line, inString);
      }
    } else {
      if (isFenceLine) {
        block = null;
        skipping = false;
        inString = false;
      } else if (!skipping) {
        block.add(line);
        inString = _scanString(line, inString);
      }
    }
  }

  if (!sawFence) return text.replaceAll('\r\n', '\n').split('\n').where((l) => !l.trimLeft().startsWith(']]>openui:')).join('\n').trim();

  final blockText = blocks.map((b) => b.join('\n')).where((b) => b.isNotEmpty).toList();
  final firstCode = blockText.isEmpty
      ? null
      : blockText.first.split('\n').firstWhere((l) => l.trim().isNotEmpty && !_isComment(l), orElse: () => '');
  if (firstCode != null && _startsStatement(firstCode)) return blockText.join('\n').trim();
  final out = outside.join('\n');
  if (out.split('\n').any(_startsStatement)) return out.trim();
  return blockText.join('\n').trim();
}

/// Three backticks that close again on the same line are inline code, not a fence.
bool _closesOnSameLine(String trimmed) => trimmed.indexOf('```', 3) != -1;
