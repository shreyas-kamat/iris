# openui_lang

A pure-Dart implementation of [OpenUI Lang](https://github.com/thesysdev/openui) 1.0 for Iris: a lexer, a streaming
parser, an evaluator with a two-way state store, validation, and a deterministic system-prompt generator. No Flutter
and no `dart:ui`, so it also runs in plain `dart test` and on a server.

It follows the language-neutral spec and passes OpenUI's conformance fixtures (vendored under `test/fixtures/`, MIT,
see `NOTICE`). Editing mode is out of v1.

## Conformance

`dart test test/conformance_test.dart`: **54 passed, 5 skipped, 0 failed.** Each fixture runs batch and streamed (a
character at a time, and split in two at every boundary). The skips are listed with their reasons in
`FIXTURES_SKIPPED.md`: the five `editing/*` cases (edit mode is out of v1) and the renderer-level `interactions.json`
checks, which Iris runs against its own widgets.

## Usage

```dart
import 'package:openui_lang/openui_lang.dart';

final library = LibrarySpec.fromJson(jsonDecode(libraryJson) as Map<String, Object?>);

// 1. The system prompt for the model. Same library and options give the same bytes.
final prompt = generateSystemPrompt(library, options: const PromptOptions(bindings: true));

// 2. Parse a finished program, or stream one in.
final done = parseProgram(library, text);
final parser = StreamingParser(library);
final partial = parser.set(textSoFar); // call again with the whole text on every chunk
final last = parser.end();             // final result equals parseProgram on the same text

// 3. Evaluate. The store holds `$state`; widgets write it, and a re-parse never clobbers what the person changed.
final evaluator = Evaluator(last, library);
final (:root, :errors) = evaluator.evaluateRoot();
evaluator.store.set('name', 'Ada');
```

`ParseResult` carries the `tree`, structured `errors` (each with a code and, where useful, the component signature as a
`hint`), `unresolved` and `orphans` names, `incomplete`, declared `state` and `statementCount`. A mistake removes the
smallest unit that is wrong; everything else still renders.

## The prompt generator

`generateSystemPrompt` is a byte-for-byte port of OpenUI's reference generator for the v1 feature set: components
(optionally grouped), built-in functions, action steps, `$variable` bindings, streaming guidance, examples and extra
rules. It teaches nothing the client cannot do: no `Query`, `Mutation`, `@Run`, edit mode or inline mode. The goldens in
`test/golden/prompt/` were produced by the TypeScript reference; the Python port in `server/hermes-iris` must reproduce
them from the same library files.

## Rulings where the spec is silent

The evaluator follows the reference runtime, with these deliberate differences (details in the Phase 9 progress log,
G3): a runtime throw makes that prop `null`; `@Sort` uses a root-collation stand-in for `localeCompare` that is right
for Latin text; the `url` validation rule requires a host; references nest at most 64 deep and `@Each` visits at most
1,000 elements.

## Licence and attribution

OpenUI Lang is an open specification from Thesys Inc. (MIT). This package implements it in Dart and checks it against
OpenUI's conformance fixtures and prompt goldens at commit `eea983e`. The attribution and the exact files are in
`NOTICE`; the fixtures' licence text is `test/fixtures/LICENSE`.
