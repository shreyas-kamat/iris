import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

void main() {
  final json = (jsonDecode(File('test/fixtures/library.json').readAsStringSync()) as Map).cast<String, Object?>();
  final lib = LibrarySpec.fromJson(json);

  test('metadata and root', () {
    expect(lib.id, 'fixtures');
    expect(lib.root, 'Stack');
    expect(lib.components.length, 12);
  });
  test('positional order is the key order of properties', () {
    expect(lib.components['Button']!.props.map((p) => p.name), ['label', 'action', 'variant', 'share']);
    expect(lib.components['Input']!.props.map((p) => p.name), ['name', 'placeholder', 'value', 'rules']);
  });
  test('required flags', () {
    final input = lib.components['Input']!.props;
    expect(input.where((p) => p.required).map((p) => p.name), ['name']);
  });
  test('bindable props come from the signature', () {
    expect(lib.components['Input']!.props.where((p) => p.bindable).map((p) => p.name), ['value']);
    expect(lib.components['Select']!.props.where((p) => p.bindable).map((p) => p.name), ['value']);
    expect(lib.components['Button']!.props.any((p) => p.bindable), isFalse);
  });
  test('functions and actions', () {
    expect(lib.functions.keys, ['Upper']);
    expect(lib.functions['Upper']!.params.single.name, 'text');
    expect(lib.actions.keys, ['CopyToClipboard']);
  });
  test('JSON round trip', () {
    expect(jsonEncode(LibrarySpec.fromJson(lib.toJson()).toJson()), jsonEncode(json));
  });
}
