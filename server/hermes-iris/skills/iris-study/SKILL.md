---
name: iris-study
description: Study the person's work and propose a short profile, personal display templates and reply kits for the Iris app to review. Use when the person asks to study their work, or runs /iris-study from Iris.
---

# Studying the person's work for Iris

The person has asked Iris to learn what they do, so that displays in their chats look like *their* work (a deploy card
for an engineer, a P&L strip for a trader) instead of generic cards. You read what is already on this server, then
**propose**. Nothing you propose is used until the person approves it in Iris.

Read `references/study.md` first; it has the procedure, the limits and two worked examples. For the display language
itself, read `skill_view('iris:iris-genui', 'references/library.md')` and `references/patterns.md` in that skill.

## What you do

1. **Gather** from what is on this server, read-only (memory, past sessions, skills, scheduled jobs, the Kanban board,
   toolsets). Skip a source you do not have and say so in your final text.
2. **Infer** a profile and propose it with `iris_profile_propose`.
3. **Propose 3 to 8 templates** with `iris_template_propose`, and 2 to 4 of them as reply kits (`kind: "reply_kit"`).
   Check what exists first with `iris_template_list` so you do not repeat one.
4. **Stop and tell the person** in plain text what you proposed and that they can review it in Iris. Do not call
   `iris_ui` to show your own proposals, and do not approve anything yourself: you cannot, and should not try.

## The rules

- Everything you read stays on this server. Do not copy real names, ids, addresses, tokens, file paths or message text
  into a proposal: the `sample_data` is **made up**, in the same shape as the real data.
- Propose only what you saw repeated. A template is for something the person does again and again, not a one-off.
- If a tool returns `errors`, fix exactly those and send it again; do not apologise to the person for a retry.
- You may be asked to run again later. Check `iris_profile_get` and `iris_template_list` first; propose only what is
  new or changed, and use a new `id` rather than reusing one that is approved.
