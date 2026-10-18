# Phase 7 device pass — 2026-10-18

Build: release APK (71.8 MB) built from commit `df53190`, plus nothing uncommitted in `lib/`. Emulator: Pixel_9
(1080x2424), driven by Claude over `adb` (taps, `input text`, screenshots read by eye). The demo was walked in light
mode; dark mode, 200% text, 320 pt width and reduced motion were checked on the Scheduled and Tasks tabs as noted.

Two emulator problems, neither the app's: the display went white after install (cold-booted with
`-no-snapshot-load`), and after the cold boot the emulator could not resolve DNS (restarted with
`-dns-server 8.8.8.8,1.1.1.1`; the first sign-in attempt showed the app's own "server took too long" card, which is
the expected message for an unreachable server).

## Demo (no server needed)
- Welcome → Try the demo: home shows Sessions | Scheduled | Tasks — PASS
- Scheduled: four jobs; failed one in red; paused one off; the new-job button — PASS
- Pause and resume a job; the switch moves at once — PASS (pause showed "paused" and the switch off; resume turned it on and the detail said Enabled)
- Job detail: Run now says Started; a past run appears and opens — PASS with a gap: the past run appeared ("just now") and opened as an empty demo chat; the "Started" toast was not caught (the screenshot came about a second after the tap)
- New job: a bad schedule ("every blursday") shows the message under Schedule — PASS ("Couldn't parse 'every blursday'", red field); Cancel then asked "Discard changes?"
- Edit a job; Delete asks first — PASS (Edit opened filled in; Delete asked, then removed the job: 4 jobs became 3)
- Tasks: chips with counts; Running card has the clock and "2 of 5 subtasks"; Blocked cards show each kind — PASS (NEEDS INPUT, DEPENDENCY, CAPABILITY, TRANSIENT; "1 warning" on the last)
- An empty Review column says Hermes moves tasks there — PASS (after moving t_26 to Done: "Nothing in Review · Hermes moves tasks here. You can't add one yourself.")
- Task detail t_26: parent link, subtasks, comments, runs; Move to Done; Running is locked — PASS (Running and Review show a lock and "Set by Hermes" in the Move sheet; the move to Done worked)
- New task: Create waits for a title; the task appears — PASS (Create was disabled with no title; "Device pass task" appeared in To do as t_41)
- Chat ⋯ menu: every row; while replying the history rows are dimmed with a reason — PASS (all rows present; while a reply ran, Branch, Archive, Compress, Undo and Delete said "Stop the reply first"; Rename, Pin, Export and Session info stayed on)
- Rename from the menu; Session info; Copy session id; Compress; Undo — PASS (title changed; Session info showed profile, model, last active, messages, context, id; "Copied session id"; "Compressed"; "Undid the last turn" and the prompt came back into the composer)
- Export as Markdown: the share sheet opens with a .md file — PASS ("Sharing 1 file: morning-inbox-digest.md")
- Settings → Profiles: three profiles; switch with the circle; create "notes"; edit its SOUL; rename; delete by typing the name — PASS (the SOUL typed on create was there when the profile was reopened, which is the Task 15 fix working; rename worked; delete needed the name typed)
- Search with focus: the scope bar appears; All profiles groups by profile; tapping a hit under another profile opens it — PASS ("the" gave 6 chats under Default and Homelab; tapping the Homelab hit switched the profile pill to homelab and opened the chat)

## Real server (hermes.shreyaskamat.in)
- Cold start: the tabs appear only if the server has the plugins — SKIPPED (the user asked to skip the real-server checks)
- Scheduled and Tasks load; pull to refresh; a poll updates the list within 15 s — SKIPPED (same)
- (Live write test already covered create/pause/trigger/delete: see Task 15.)
- Reached before skipping: the app found the Hermes dashboard at that address ("Hermes dashboard found, version unknown") and the sign-in form was filled in; the result of Sign in was not looked at.

## Cross-cutting
- Light mode on every new screen — PASS (the whole demo walk above was light)
- Dark mode — PASS on the Scheduled tab and the Tasks tab (checked by eye); the dark chat menu and Profiles are covered by the goldens from Task 14
- 320 pt wide: nothing overflows — PASS (`wm size 640x1136`, density 320, together with 200% text). Observation, not a failure: at that size the tab control stacks into three rows and, with the header, takes about half the screen, leaving little room for the list
- Font size 200%: nothing clips or overflows — PASS on Scheduled (job card wraps, switch stays), Tasks (chip row scrolls, "New task" and the section label wrap) and the stacked tab control. The "g" of "Triage" in the chip sits very close to the chip's bottom edge at 200%
- Reduced motion (animation scales set to 0): the segmented thumb jumps, no ticker runs — INCONCLUSIVE: with the scales at 0 the thumb was already at its final position in the first screenshot, but a screenshot is slower than the 250 ms move, so this cannot show the difference, and tickers cannot be seen over `adb`. The widget tests for the segmented control and the new screens cover the no-animation path
- TalkBack names the segments, the switch states, the ⋯ button — NOT RUN (TalkBack was not driven over `adb`). The semantics tests in Tasks 3, 5, 7, 9 and 11 cover the labels
- Cold restart keeps the theme and profile — SKIPPED (the user asked to skip the real-server checks; the demo does not keep either, by design)

## Observations (no fix made)
- In the demo, every profile shows the same jobs and tasks (the demo's data is not per profile).
- The demo's To do and Review columns both hold a task titled "Rotate gateway API keys" (t_24 and t_26) because of the plan's seed data.
- Running cards' clocks in the demo keep counting from when the demo opened (4 and 11 minutes at start).

Result: no FAIL. Not covered on a device: the real-server checks (skipped by the user), TalkBack (not run) and reduced motion (inconclusive).
