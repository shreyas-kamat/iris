import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

/// Runs the vendored OpenUI 1.0 fixtures (test/fixtures/, see NOTICE). Each case is its own test.
/// Comparison rules: fixtures/README.md. Editing, interaction and validation checks are listed in FIXTURES_SKIPPED.md.
void main() {
  final root = Directory('test/fixtures');
  final library = LibrarySpec.fromJson(
    (jsonDecode(File('${root.path}/library.json').readAsStringSync()) as Map).cast<String, Object?>(),
  );

  final cases = root
      .listSync()
      .whereType<Directory>()
      .expand((area) => area.listSync().whereType<Directory>())
      .where((d) => File('${d.path}/expected.json').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final dir in cases) {
    final name = dir.path.replaceAll(r'\', '/').replaceFirst('test/fixtures/', '');
    final area = name.split('/').first;
    final expected = (jsonDecode(File('${dir.path}/expected.json').readAsStringSync()) as Map).cast<String, Object?>();
    final chunksFile = File('${dir.path}/chunks.json');
    final inputFile = File('${dir.path}/input.oui');

    // v1 skips: edit mode (spec D, out of v1) and cases with no program input (validation-only).
    if (area == 'editing') {
      test(name, () {}, skip: 'edit mode is out of v1 (FIXTURES_SKIPPED.md)');
      continue;
    }
    if (!chunksFile.existsSync() && !inputFile.existsSync()) {
      test(name, () {}, skip: 'validation-only case, runs with task 1.6 (FIXTURES_SKIPPED.md)');
      continue;
    }

    test(name, () {
      final chunks = chunksFile.existsSync()
          ? (jsonDecode(chunksFile.readAsStringSync()) as List).cast<String>()
          : [inputFile.readAsStringSync()];
      final batch = parseProgram(library, chunks.join());
      _expectMatches(batch, expected);
      if (chunksFile.existsSync()) {
        _expectMatches(parseStream(library, chunks), expected);
      }
    });
  }
}

void _expectMatches(ParseResult actual, Map<String, Object?> expected) {
  expect(actual.root, equals(expected['root']), reason: 'root');
  expect(_multiset(actual.errors.map(_codeAndId)), equals(_multiset(_expectedErrors(expected))), reason: 'errors');
  expect(actual.unresolved.toSet(), equals(((expected['unresolved'] as List?) ?? const []).cast<String>().toSet()));
  expect(actual.orphans.toSet(), equals(((expected['orphans'] as List?) ?? const []).cast<String>().toSet()));
  expect(actual.incomplete, equals(expected['incomplete'] ?? false), reason: 'incomplete');
  if (expected.containsKey('state')) expect(actual.state, equals(expected['state']), reason: 'state');
}

Iterable<String> _expectedErrors(Map<String, Object?> expected) =>
    ((expected['errors'] as List?) ?? const []).map((e) => _codeAndId((e as Map).cast<String, Object?>()));

String _codeAndId(Map<String, Object?> e) => '${e['code']}|${e['statementId'] ?? '*'}';

List<String> _multiset(Iterable<String> xs) => xs.toList()..sort();
