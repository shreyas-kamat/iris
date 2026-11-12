# Skipped conformance fixtures

| Fixtures | Reason |
|---|---|
| `editing/*` (5 cases) | Edit mode (language.md §7) is out of v1 (spec, Phase 0 findings). |
| `interactions.json` in 12 action/state cases | Level 2 (renderer) checks; Iris runs them in Phase 3/4 with its own widgets. Level 1 still runs. |
