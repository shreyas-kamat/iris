/// Parses every prefix of every vendored fixture program and prints one JSON line per prefix, for the Python port's
/// cross-check (`server/hermes-iris/tests/test_crosscheck_dart.py`). Run from the package root:
///
///     dart run tool/dump_parse.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';

void main() {
  final root = Directory('test/fixtures');
  final library = LibrarySpec.fromJson(
    (jsonDecode(File('${root.path}/library.json').readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );
  final dirs =
      root
          .listSync()
          .whereType<Directory>()
          .expand((area) => area.listSync().whereType<Directory>())
          .where(
            (d) =>
                File('${d.path}/input.oui').existsSync() ||
                File('${d.path}/chunks.json').existsSync(),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final dir in dirs) {
    final id = dir.path
        .replaceAll(r'\', '/')
        .replaceFirst('test/fixtures/', '');
    final chunks = File('${dir.path}/chunks.json');
    final text = chunks.existsSync()
        ? (jsonDecode(chunks.readAsStringSync()) as List).cast<String>().join()
        : File('${dir.path}/input.oui').readAsStringSync();
    final runes = text.runes.toList();
    for (var i = 0; i <= runes.length; i++) {
      final prefix = String.fromCharCodes(runes.take(i));
      final r = parseProgram(library, prefix);
      final tree = jsonEncode(r.summary());
      stdout.writeln(
        jsonEncode({
          'id': id,
          'i': i,
          'errors':
              (r.errors.map((e) => '${e.code}|${e.statementId ?? '*'}').toList()
                ..sort()),
          'unresolved': r.unresolved.toList()..sort(),
          'orphans': r.orphans.toList()..sort(),
          'incomplete': r.incomplete,
          'tree': tree.contains(deferredMarker) ? null : r.summary(),
        }),
      );
    }
  }
}
