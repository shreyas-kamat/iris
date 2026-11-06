import 'dart:convert';
import 'dart:io';

import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

LibrarySpec _lib(String name) => LibrarySpec.fromJson(
  jsonDecode(File('test/golden/prompt/$name.library.json').readAsStringSync())
      as Map<String, Object?>,
);

String _golden(String name) =>
    File('test/golden/prompt/$name.txt').readAsStringSync();

void main() {
  // The goldens were produced by OpenUI's own `generateSystemPrompt` (lang-core at eea983e, DO_NOT_TRACK=1)
  // for the same library and options; see test/golden/prompt/README.md.
  group('generateSystemPrompt matches the reference byte for byte', () {
    test('fixture library, defaults (no bindings)', () {
      expect(generateSystemPrompt(_lib('fixture')), _golden('fixture-plain'));
    });

    test('fixture library, bindings on', () {
      expect(
        generateSystemPrompt(
          _lib('fixture'),
          options: const PromptOptions(bindings: true),
        ),
        _golden('fixture-bindings'),
      );
    });

    test('built-in functions without bindings', () {
      expect(
        generateSystemPrompt(
          _lib('fixture'),
          options: const PromptOptions(builtinFunctions: true),
        ),
        _golden('fixture-builtins-only'),
      );
    });

    test('preamble, examples and additional rules', () {
      expect(
        generateSystemPrompt(
          _lib('fixture'),
          options: const PromptOptions(
            bindings: true,
            preamble: 'You write Iris displays.',
            examples: ['root = Stack([t])\nt = Text("Hello")'],
            additionalRules: ['Keep it short.', 'British English.'],
          ),
        ),
        _golden('fixture-options'),
      );
    });

    test(
      'component groups, with unknown and repeated names and an Other group',
      () {
        expect(
          generateSystemPrompt(
            _lib('grouped'),
            options: const PromptOptions(bindings: true),
          ),
          _golden('grouped-bindings'),
        );
      },
    );

    test('a library with no actions, functions or action props', () {
      expect(generateSystemPrompt(_lib('mini')), _golden('mini-plain'));
      expect(
        generateSystemPrompt(
          _lib('mini'),
          options: const PromptOptions(bindings: true),
        ),
        _golden('mini-bindings'),
      );
    });
  });

  test('the output is deterministic', () {
    const options = PromptOptions(
      bindings: true,
      examples: ['root = Stack([])'],
    );
    expect(
      generateSystemPrompt(_lib('fixture'), options: options),
      generateSystemPrompt(_lib('fixture'), options: options),
    );
  });

  test('the root component name appears in the rules', () {
    final prompt = generateSystemPrompt(_lib('fixture'));
    expect(prompt, contains('every program must define `root = Stack(...)`'));
    expect(prompt, contains('1. root = Stack(...) is the FIRST line'));
  });

  test(
    'only teaches what the client supports: no Query, Mutation, @Run, or edit mode',
    () {
      final prompt = generateSystemPrompt(
        _lib('fixture'),
        options: const PromptOptions(bindings: true),
      );
      for (final word in [
        'Query(',
        'Mutation(',
        '@Run',
        'Edit Mode',
        'Inline Mode',
      ]) {
        expect(prompt, isNot(contains(word)), reason: word);
      }
    },
  );
}
