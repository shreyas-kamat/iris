# Phase 6 server probe — 2026-10-16

Run with `flutter test --tags live --run-skipped test/live/phase6_probe_live_test.dart` against the user's Hermes
dashboard. Every call used an id that does not exist, so nothing changed. "Present" means the method answered
(with an error about the id, or with a result); "MISSING" means "unknown method".

| Method | Result |
|---|---|
| session.undo | present (4001, session not found) |
| session.branch_stored | present (4008) |
| session.compress | present (4001) |
| session.active_list | present (answered) |
| connection.respond | present (4001) |
| config.set busy | present (answered) |
| config.set reasoning | present (4001) |
| config.set fast | present (4001) |

Every method Phase 6 needs exists on this server. Missing methods on other servers get "not supported on this
server" in the UI (see the plan's Review Focus 2).
