# Conformance fixtures the Python port does not fully check

The fixtures are the Dart package's vendored copy (`packages/openui_lang/test/fixtures/`, one copy shared by both
sides). The Python port parses and validates; it has no evaluator, by design (plan 2.4, spec D10).

| What | Count | Reason |
|---|---|---|
| `editing/*` | 5 fixtures, not run | Edit mode (language.md section 7) is out of v1. |
| `state/005-validation-rules` | not run | `validation.json` checks form-field rules (`required`, `minLength`, ...) at input time. That is the client's runtime; the server never validates user input. |
| Tree comparison (`expected.json` `root`) | 29 of 53 fixtures | The tree holds a computed value (a ternary, arithmetic, `@Count`, an action, a `$state` read), which only an evaluator can resolve. The other 24 compare the whole tree. |

For those 29 the structural expectations still hold and are checked: the error multiset (code and statement id),
`unresolved`, `orphans` and `incomplete`. `test_enough_trees_are_compared_in_full` fails if the 24 drop.
