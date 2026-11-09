import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/demo/demo_content.dart';
import 'package:iris/demo/demo_script.dart';
import 'package:iris/features/genui/render/iris_library.dart';
import 'package:openui_lang/openui_lang.dart';

final _lib = IrisLibrary.toLibrarySpec();

/// Every `iris_ui` call a script makes, with its decoded arguments.
List<({ToolStep step, Map<String, Object?> args})> _displays(
  DemoScript script,
) => [
  for (final step in script.steps.whereType<ToolStep>())
    if (step.name == 'iris_ui')
      (step: step, args: jsonDecode(step.input) as Map<String, Object?>),
];

/// The study's `iris_template_propose` calls with their decoded arguments.
List<Map<String, Object?>> _proposals(DemoScript script, String tool) => [
  for (final step in script.steps.whereType<ToolStep>())
    if (step.name == tool) jsonDecode(step.input) as Map<String, Object?>,
];

DemoScript _script(String prompt) =>
    demoScripts.firstWhere((s) => s.prompt == prompt);

void main() {
  test('every demo display is valid Iris Lang and draws a root', () {
    var count = 0;
    for (final script in demoScripts) {
      for (final display in _displays(script)) {
        count++;
        final code = display.args['code'] as String?;
        expect(code, isNotNull, reason: script.prompt);
        final result = parseProgram(_lib, code!);
        expect(result.errors, isEmpty, reason: code);
        expect(
          Evaluator(result, _lib).evaluateRoot().root,
          isNotNull,
          reason: code,
        );
      }
    }
    // A card and a reply kit. The study's templates are proposals, not
    // displays, so they are checked in their own test.
    expect(count, 2);
  });

  test(
    'every demo display names a surface, keeps its text, and is accepted',
    () {
      for (final script in demoScripts) {
        for (final display in _displays(script)) {
          final id = display.args['surface_id'] as String?;
          expect(id, isNotNull, reason: script.prompt);
          expect(id, isNotEmpty, reason: script.prompt);
          // Text stays complete (D7): the fallback is never empty.
          final fallback = display.args['fallback'] as String?;
          expect(fallback?.trim(), isNotEmpty, reason: script.prompt);
          final answer =
              jsonDecode(display.step.output) as Map<String, Object?>;
          expect(answer['ok'], isTrue, reason: script.prompt);
        }
      }
    },
  );

  test(
    'a suggested prompt shows a reply kit that docks above the composer',
    () {
      final kits = [
        for (final script in demoScripts)
          if (_displays(script).any((d) => d.args['placement'] == 'reply_kit'))
            script,
      ];
      expect(kits, isNotEmpty);
      final kit = kits.single;
      // The question is in the reply text; the kit only offers the answers.
      expect(kit.steps.whereType<SayStep>(), isNotEmpty);
    },
  );

  test(
    'the study result proposes a profile and templates that parse once expanded',
    () {
      final script = _script('Set up my work profile');
      expect(_proposals(script, 'iris_profile_propose'), hasLength(1));

      final templates = _proposals(script, 'iris_template_propose');
      expect(templates, hasLength(2));
      for (final template in templates) {
        for (final key in const [
          'id',
          'name',
          'when',
          'data_schema',
          'program',
          'sample_data',
        ]) {
          expect(template.containsKey(key), isTrue, reason: '$key missing');
        }
        // The plugin expands a template by putting its sample data in `data`
        // and running the program after it (see UiTemplate.expanded).
        final expanded =
            'data = ${jsonEncode(template['sample_data'])}\n'
            '${template['program']}';
        final result = parseProgram(_lib, expanded);
        expect(result.errors, isEmpty, reason: expanded);
        expect(
          Evaluator(result, _lib).evaluateRoot().root,
          isNotNull,
          reason: expanded,
        );
      }
    },
  );
}
