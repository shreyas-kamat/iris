import 'library_spec.dart';
import 'parse_result.dart';
import 'streaming.dart';

/// Parses [text] against [library] as one batch: a one-chunk stream that has ended (language.md §4, rule 7). Never
/// throws: an internal failure is a fatal `parse-exception`.
ParseResult parseProgram(LibrarySpec library, String text) => StreamingParser(library).end(text);

/// Parses [chunks] as a stream, then ends the stream.
ParseResult parseStream(LibrarySpec library, List<String> chunks) {
  final parser = StreamingParser(library);
  final text = StringBuffer();
  for (final c in chunks) {
    text.write(c);
    parser.set(text.toString());
  }
  return parser.end(text.toString());
}
