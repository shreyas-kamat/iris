import 'errors.dart';
import 'library_spec.dart';
import 'materialize.dart';
import 'parse_result.dart';
import 'program.dart';
import 'source.dart';
import 'statements.dart';

/// Parses [text] against [library] as one batch. Never throws: an internal failure is a fatal `parse-exception`.
ParseResult parseProgram(LibrarySpec library, String text) {
  try {
    final prepared = prepareSource(text);
    final split = splitStatements(prepared);
    if (split.statements.isEmpty) {
      final errors = prepared.trim().isEmpty
          ? <OpenUiError>[]
          : [const OpenUiError(code: ErrorCode.parseFailed, message: 'the response has text but yields no statements')];
      return ParseResult(
        tree: null,
        errors: errors,
        unresolved: const {},
        orphans: const {},
        incomplete: split.incomplete,
        program: null,
      );
    }
    final program = Program.build(split.statements, library, incomplete: split.incomplete);
    final m = materialize(program, library);
    return ParseResult(
      tree: m.root,
      errors: m.errors,
      unresolved: m.unresolved,
      orphans: program.orphans,
      incomplete: split.incomplete,
      program: program,
    );
  } on Object catch (e) {
    return ParseResult(
      tree: null,
      errors: [OpenUiError(code: ErrorCode.parseException, message: '$e')],
      unresolved: const {},
      orphans: const {},
      incomplete: false,
      program: null,
    );
  }
}

/// Parses [chunks] as a stream, then ends the stream.
ParseResult parseStream(LibrarySpec library, List<String> chunks) {
  throw UnimplementedError('parseStream arrives with task 1.5');
}
