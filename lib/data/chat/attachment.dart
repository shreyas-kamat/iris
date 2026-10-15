/// A file sent with a prompt, and how the prompt names it. Hermes stages a
/// file in the session and answers with an `@file:` reference; the prompt
/// carries those references ahead of the typed text, the way Hermes Desktop
/// and Conduit send them.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

final class Attachment {
  const Attachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  /// Larger files are refused before upload: base64 over the socket grows
  /// them by a third.
  static const maxBytes = 20 * 1024 * 1024;
  static const maxPerMessage = 5;

  static const _types = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.pdf': 'application/pdf',
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.csv': 'text/csv',
    '.json': 'application/json',
  };

  String get mimeType =>
      _types[p.extension(name).toLowerCase()] ?? 'application/octet-stream';

  bool get isImage => mimeType.startsWith('image/');

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// The prompt Hermes receives: each reference on its own line, a blank
/// line, then the typed text.
String promptWithReferences(String text, List<String> references) {
  if (references.isEmpty) return text;
  final head = references.join('\n');
  return text.trim().isEmpty ? head : '$head\n\n$text';
}

final _reference = RegExp(r'''^@file:(?:"([^"]*)"|'([^']*)'|`([^`]*)`|(\S+))\s*$''');

/// A stored prompt's leading `@file:` lines as file names, and the rest.
(List<String>, String) splitReferences(String prompt) {
  final lines = prompt.split('\n');
  final names = <String>[];
  var i = 0;
  for (; i < lines.length; i++) {
    final match = _reference.firstMatch(lines[i].trim());
    if (match == null) break;
    final path = match[1] ?? match[2] ?? match[3] ?? match[4]!;
    names.add(p.posix.basename(path));
  }
  if (names.isEmpty) return (const [], prompt);
  return (names, lines.skip(i).join('\n').trim());
}

/// A path as Hermes reads it back whole: quoted when it holds whitespace,
/// brackets or quotes (its `format_reference_value`).
String formatReferenceValue(String value) {
  if (!RegExp(r'''[\s()\[\]{}"'`]''').hasMatch(value)) return value;
  for (final quote in const ['`', '"', "'"]) {
    if (!value.contains(quote)) return '$quote$value$quote';
  }
  return value;
}
