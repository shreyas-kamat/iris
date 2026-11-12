import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/genui/render/iris_library.dart';
import 'package:openui_lang/openui_lang.dart';

/// The checked-in export the Hermes plugin reads. Regenerate with
/// `IRIS_WRITE_CATALOG=1 flutter test test/features/genui/iris_library_test.dart`, then
/// `python server/hermes-iris/tools/build_skill_refs.py` and the plugin tests.
const _catalogPath = 'server/hermes-iris/catalog/v1.library.json';

String _export() =>
    '${const JsonEncoder.withIndent('  ').convert(IrisLibrary.toJson())}\n';

void main() {
  group('IrisLibrary', () {
    test('the checked-in catalog matches the Dart definitions', () {
      final file = File(_catalogPath);
      if (Platform.environment['IRIS_WRITE_CATALOG'] == '1') {
        file.writeAsStringSync(_export());
      }
      expect(
        file.readAsStringSync().replaceAll('\r\n', '\n'),
        _export(),
        reason:
            'run with IRIS_WRITE_CATALOG=1 to refresh $_catalogPath, then rebuild the skill references',
      );
    });

    test('the spec round-trips through JSON and keeps the declared order', () {
      final spec = LibrarySpec.fromJson(
        jsonDecode(jsonEncode(IrisLibrary.toJson())) as Map<String, Object?>,
      );
      expect(
        [...spec.components.keys],
        [for (final c in IrisLibrary.components) c.name],
      );
      expect(spec.root, 'Stack');
      expect(spec.id, IrisLibrary.id);
      expect(spec.functions.keys, containsAll(['Percent', 'Money', 'Ago']));
      expect(spec.actions.keys, ['Ask']);
      for (final c in IrisLibrary.components) {
        expect(
          [for (final p in spec.components[c.name]!.props) p.name],
          [for (final p in c.props) p.name],
          reason: c.name,
        );
        expect(
          [for (final p in spec.components[c.name]!.props) p.required],
          [for (final p in c.props) p.required],
          reason: c.name,
        );
      }
    });

    test(
      'required props come first and every description is a real sentence',
      () {
        for (final c in IrisLibrary.components) {
          final firstOptional = c.props.indexWhere((p) => !p.required);
          if (firstOptional >= 0) {
            expect(
              c.props.skip(firstOptional).every((p) => !p.required),
              isTrue,
              reason: c.name,
            );
          }
          expect(c.description.length, greaterThan(20), reason: c.name);
          expect(
            c.description.endsWith('.'),
            isFalse,
            reason: '${c.name}: descriptions have no final full stop',
          );
        }
      },
    );

    test('signatures print the positional order', () {
      final byName = {for (final c in IrisLibrary.components) c.name: c};
      expect(
        byName['Stack']!.signature,
        'Stack(children: any[], direction?: "column" | "row", gap?: "s" | "m" | "l")',
      );
      expect(byName['StatRow']!.signature, 'StatRow(stats: Stat[])');
      expect(
        byName['Table']!.signature,
        'Table(columns: string[], rows: any[][])',
      );
      expect(byName['Divider']!.signature, 'Divider()');
      expect(
        byName['Button']!.signature,
        'Button(label: string, action?: ActionExpression, variant?: "primary" | "secondary")',
      );
      expect(
        IrisLibrary.functions.first.signature,
        'Percent(done: number, total: number) → number',
      );
      expect(
        IrisLibrary.actions.single.signature,
        'Ask(text: string, context?: any)',
      );
    });

    test(
      'every component named in a group, a list type or Component exists',
      () {
        final names = {for (final c in IrisLibrary.components) c.name};
        for (final g in IrisLibrary.groups) {
          expect(names.containsAll(g.components), isTrue, reason: g.name);
        }
        final grouped = [for (final g in IrisLibrary.groups) ...g.components];
        expect(
          grouped.toSet(),
          names,
          reason: 'every component sits in exactly one group',
        );
        expect(grouped.length, names.length);
        final defs = (IrisLibrary.toJson()['schema']! as Map)[r'$defs'] as Map;
        final text = jsonEncode(defs);
        for (final m in RegExp(r'#/\$defs/(\w+)').allMatches(text)) {
          expect(
            defs.containsKey(m.group(1)),
            isTrue,
            reason: 'dangling ${m.group(0)}',
          );
        }
      },
    );

    test('a realistic display parses, evaluates and has no errors', () {
      final lib = IrisLibrary.toLibrarySpec();
      const code = '''
root = Stack([head, stats, tabs])
head = Text("Cron jobs", "title")
stats = StatRow([Stat("Running", "12", "+2", "up"), Stat("Failed", "1", null, "down")])
tabs = Tabs([Tab("Jobs", [Table(["Job", "State"], [["backup", "ok"], ["sync", "failed"]])]), Tab("Log", [Timeline([TimelineItem("backup", "03:00", "ok")])])])
''';
      final result = parseProgram(lib, code);
      expect(result.errors, isEmpty);
      final root = Evaluator(result, lib).evaluateRoot();
      expect(root.errors, isEmpty);
      expect(root.root!.type, 'Stack');
    });

    test('the generated prompt lists every component, grouped', () {
      final prompt = generateSystemPrompt(IrisLibrary.toLibrarySpec());
      for (final c in IrisLibrary.components) {
        expect(prompt, contains('${c.name}('), reason: c.name);
      }
      expect(prompt, contains('### Layout'));
      expect(prompt, contains('### Text and data'));
    });
  });
}
