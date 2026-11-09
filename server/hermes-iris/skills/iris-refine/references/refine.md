# The refinement, step by step

You are tuning a small, personal set of displays from evidence. A few well-chosen changes beat a rewrite, and doing
nothing is a good answer when the numbers do not point anywhere.

## 1. Read

- `iris_usage_summary` gives counts only (no content): `turns`, `turns_with_display`, then per approved template how
  often it was **shown**, and how often the app saw it **used** (on screen for a couple of seconds), **expanded**
  (opened in full), **dismissed**, or marked **not_useful**. `plain_displays` counts the displays you made without a
  template. `first_ts` and `last_ts` say how long the counts cover.
- `iris_template_list` gives each template's id, name, when to use it, kind and whether a change already waits
  (`has_proposal`). Do not propose again over a change that is still waiting; mention it instead.
- `iris_profile_get` tells you what the person does, so a change fits their work.

If a template was **never shown**, that is not a verdict on the template: it may simply not have come up. If there are
**too little** data (for example fewer than about ten turns, or fewer than three showings of a template), say what you
saw and propose nothing for it.

## 2. Decide

Read the counts per template:

- Shown often, **expanded** often: the card hides what the person wants. Put that content on the card, or make the
  summary line say more.
- Shown often, **dismissed** or **not_useful**: it is noise. Shorten it, drop the fields nobody reads, or **retire** it.
- Shown, rarely **used** and never expanded: it may be fine and quiet. Leave it.
- The same request keeps coming as `plain_displays` with no template: propose a **new template** for it with
  `iris_template_propose` (a new id; an approved one is never overwritten).

Make **one change** per template, with a clear reason. Prefer small changes to the program (a field, a row, an order)
over a new shape; the person approved the old one and will compare them side by side.

## 3. Propose

`iris_template_refine(id, reason, ...)`:

- `reason` is one line (at most 300 characters) that cites the counts: "Opened in full 6 of 9 times; it needs the time
  it started."
- Give only the fields you want different (`name`, `when`, `kind`, `data_schema`, `program`, `sample_data`); the rest
  are kept from the approved template. If the program reads new data, change the schema and the made-up sample to match.
- It is checked like a new template. Fix any `errors`, one line each.
- `retire: true` takes no other fields. It asks the person to retire the template; they decide.

```json refine
{
  "id": "deploy-status",
  "reason": "Opened in full 6 of 9 times: the card hides when the deploy started.",
  "data_schema": {
    "type": "object",
    "properties": {
      "service": {"type": "string", "maxLength": 40},
      "state": {"type": "string", "enum": ["good", "warn", "bad"]},
      "label": {"type": "string", "maxLength": 30},
      "since": {"type": "string", "maxLength": 40},
      "started": {"type": "string", "maxLength": 40},
      "checks": {"type": "array", "maxItems": 6, "items": {"type": "object"}}
    },
    "required": ["service", "state", "label", "since", "started"]
  },
  "program": "root = Card([pill, since, started, checks], data.service)\npill = StatusPill(data.label, data.state)\nsince = KeyValue(\"Since\", data.since)\nstarted = KeyValue(\"Started\", data.started)\nchecks = Stack(@Each(data.checks, \"c\", ListRow(c.name, c.detail, c.result)))",
  "sample_data": {
    "service": "api",
    "state": "good",
    "label": "Healthy",
    "since": "09:12",
    "started": "09:04",
    "checks": [{"name": "Tests", "detail": "412 passed", "result": "ok"}]
  }
}
```

```json refine
{
  "id": "deploy-status",
  "retire": true,
  "reason": "Shown 14 times, dismissed 9, never opened in full or marked used."
}
```

(Those two are alternatives for the same template; a later proposal replaces an earlier one.)

## What not to propose

- **Changes the numbers do not support.** No counts, no change. Never fabricate a count or a reason.
- **Secrets and identifiers.** Redact as in the study: the `sample_data` is made up.
- **Rewrites.** If a template needs a different shape, that is a new template with a new id.
- **Many at once.** More than three or four proposals at a time is too many to review.

## 4. Finish

Reply in plain text: what the counts showed, each proposal by template name with its reason, and anything you left
alone and why. Say that nothing is used until they approve it in Iris, and that the version they approved before stays
in use until then. Do not show the changes with `iris_ui` and do not claim anything was approved.
