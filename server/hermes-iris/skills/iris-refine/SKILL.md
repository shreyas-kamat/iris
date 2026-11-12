---
name: iris-refine
description: Refine the person's Iris displays from how they were used, by proposing changes to approved templates, new templates and retirements. Use when the person asks to refine their displays, or runs /iris-refine from Iris, or a weekly refine is scheduled.
---

# Refining the person's displays for Iris

The person has displays (templates) they approved earlier. Iris counted what happened to them: which were shown, which
the person used, opened in full, dismissed, or marked "Not useful". You read those counts and **propose** small
improvements. Nothing you propose is used until the person approves it in Iris, and the version they approved stays in
use until then.

Read `references/refine.md` first; it has the procedure, the limits and two worked examples. For the display language
itself, read `skill_view('iris:iris-genui', 'references/library.md')` and `references/patterns.md` in that skill.

## What you do

1. **Look at the numbers** with `iris_usage_summary`, and at what exists with `iris_template_list` and
   `iris_profile_get`. If there is too little to go on, say so and stop; do not guess.
2. **Pick at most a few changes** that the numbers support:
   - change an approved template: `iris_template_refine(id, reason, ...the fields you want different)`;
   - suggest retiring one: `iris_template_refine(id, reason, retire: true)`;
   - add something the person keeps asking for without a template: `iris_template_propose` with a new id.
3. **Stop and tell the person** in plain text what you proposed and why, and that they can review it in Iris. Do not
   call `iris_ui` to show your own proposals, and do not approve anything yourself: you cannot, and should not try.

## The rules

- Every proposal needs a one-line reason that points at the counts, not at a feeling.
- Never fabricate numbers, and never name a template you did not see in the tool results.
- Keep the data you read on this server: the `sample_data` stays **made up**, as in the study.
- If a tool returns `errors`, fix exactly those and send it again; do not apologise to the person for a retry.
