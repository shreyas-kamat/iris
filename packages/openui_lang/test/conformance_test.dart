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
      .where((d) => File('${d.path}/expected.json').existsSync() || File('${d.path}/validation.json').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final dir in cases) {
    final name = dir.path.replaceAll(r'\', '/').replaceFirst('test/fixtures/', '');
    final area = name.split('/').first;
    final chunksFile = File('${dir.path}/chunks.json');
    final inputFile = File('${dir.path}/input.oui');

    // v1 skips edit mode (spec D, out of v1).
    if (area == 'editing') {
      test(name, () {}, skip: 'edit mode is out of v1 (FIXTURES_SKIPPED.md)');
      continue;
    }
    final validationFile = File('${dir.path}/validation.json');
    if (validationFile.existsSync()) {
      test(name, () {
        final cases = ((jsonDecode(validationFile.readAsStringSync()) as Map)['cases'] as List).cast<Map<Object?, Object?>>();
        for (final c in cases) {
          final rules = (c['rules']! as Map).cast<String, Object?>();
          expect(validateRules(c['value'], rules) == null, c['valid'], reason: '$rules on ${c['value']}');
        }
      });
      continue;
    }

    final expected = (jsonDecode(File('${dir.path}/expected.json').readAsStringSync()) as Map).cast<String, Object?>();
    test(name, () {
      final chunks = chunksFile.existsSync()
          ? (jsonDecode(chunksFile.readAsStringSync()) as List).cast<String>()
          : [inputFile.readAsStringSync()];
      _expectMatches(library, parseProgram(library, chunks.join()), expected);
      if (chunksFile.existsSync()) {
        _expectMatches(library, parseStream(library, chunks), expected);
      }
    });
  }
}

/// The fixtures' Upper (conformance.test.ts in the OpenUI repo).
Object? _upper(Map<String, Object?> a) => (a['text']! as String).toUpperCase();

/// Evaluates at stream end with no data returned: queries read their defaults, mutations are idle.
void _expectMatches(LibrarySpec library, ParseResult actual, Map<String, Object?> expected) {
  final ev = Evaluator(actual, library, functions: {'Upper': _upper});
  final out = ev.evaluateRoot();
  final errors = [...actual.errors, ...out.errors];
  expect(ev.summarize(out.root), equals(expected['root']), reason: 'root');
  expect(_multiset(errors.map((e) => _codeAndId(e.toJson()))), equals(_multiset(_expectedErrors(expected))),
      reason: 'errors');
  expect(actual.unresolved, equals(((expected['unresolved'] as List?) ?? const []).cast<String>().toSet()));
  expect(actual.orphans, equals(((expected['orphans'] as List?) ?? const []).cast<String>().toSet()));
  expect(actual.incomplete, equals(expected['incomplete'] ?? false), reason: 'incomplete');
  if (expected.containsKey('state')) expect(actual.state, equals(expected['state']), reason: 'state');
  for (final want in ((expected['errorObjects'] as List?) ?? const []).cast<Map<Object?, Object?>>()) {
    final w = want.cast<String, Object?>();
    expect(
      errors.map((e) => e.toJson()).any((got) => w.entries.every((kv) => got[kv.key] == kv.value)),
      isTrue,
      reason: 'error object $w in $errors',
    );
  }
}

Iterable<String> _expectedErrors(Map<String, Object?> expected) =>
    ((expected['errors'] as List?) ?? const []).map((e) => _codeAndId((e as Map).cast<String, Object?>()));

String _codeAndId(Map<String, Object?> e) => '${e['code']}|${e['statementId'] ?? '*'}';

List<String> _multiset(Iterable<String> xs) => xs.toList()..sort();
