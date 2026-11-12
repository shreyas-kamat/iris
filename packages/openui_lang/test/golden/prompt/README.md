# Prompt goldens

Each `<name>.txt` is the output of OpenUI's `generateSystemPrompt` (packages/lang-core at commit `eea983e`, MIT) for
`<library>.library.json` and the options named in `test/prompt_test.dart`. Regenerate with the TypeScript reference
(`DO_NOT_TRACK=1`, telemetry stubbed) only when the generator or the library changes on purpose.

The Python port (`server/hermes-iris/openui/prompt.py`, plan 2.5) must produce the same bytes from the same files.
